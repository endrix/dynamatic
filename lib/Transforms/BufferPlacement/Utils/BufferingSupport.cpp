//===- BufferingSupport.cpp - Support for buffer placement ------*- C++ -*-===//
//
// Dynamatic is under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// Infrastructure for working around the buffer placement pass.
//
//===----------------------------------------------------------------------===//

#include "dynamatic/Transforms/BufferPlacement/Utils/BufferingSupport.h"
#include "dynamatic/Analysis/NameAnalysis.h"
#include "dynamatic/Dialect/Handshake/HandshakeOps.h"
#include "dynamatic/Support/Attribute.h"
#include "dynamatic/Support/CFG.h"
#include "mlir/IR/Attributes.h"
#include "mlir/IR/Value.h"
#include "mlir/Support/LogicalResult.h"
#include "llvm/Support/ErrorHandling.h"
#include <string>

using namespace mlir;
using namespace dynamatic;
using namespace dynamatic::handshake;
using namespace dynamatic::buffer;

bool LazyChannelBufProps::updateIR() {
  bool updated = updateIRIfNecessary();
  if (updated)
    unchangedProps = props;
  return updated;
}

ChannelBufProps &LazyChannelBufProps::operator*() {
  if (!props.has_value())
    readAttribute();
  return *props;
  ;
}

ChannelBufProps *LazyChannelBufProps::operator->() {
  if (!props.has_value())
    readAttribute();
  return &*props;
}

LazyChannelBufProps::~LazyChannelBufProps() {
  if (updateOnDestruction)
    updateIRIfNecessary();
}

void LazyChannelBufProps::readAttribute() {
  ChannelBufPropsAttr optProps =
      getOperandAttr<ChannelBufPropsAttr>(*val.getUses().begin());
  props = optProps ? optProps.getProps() : ChannelBufProps();
  unchangedProps = props;
}

bool LazyChannelBufProps::updateIRIfNecessary() {
  if (!props.has_value() || *props == *unchangedProps)
    return false;
  setOperandAttr(*val.getUses().begin(),
                 ChannelBufPropsAttr::get(val.getContext(), *props));
  return true;
}

Channel::Channel(Value value, bool updateProps)
    : value(value), consumer(*value.getUsers().begin()),
      props(value, updateProps) {
  if (OpResult res = dyn_cast<OpResult>(value)) {
    producer = value.getDefiningOp();
    return;
  }
  // Channel must be a block argument: make the parent operation the "producer"
  BlockArgument arg = cast<BlockArgument>(value);
  producer = arg.getParentBlock()->getParentOp();
}

OpOperand &Channel::getOperand() const {
  for (OpOperand &oprd : consumer->getOpOperands()) {
    if (oprd.get() == value)
      return oprd;
  }
  llvm_unreachable("channel consumer does not have value as operand");
}

Operation *dynamatic::buffer::getChannelProducer(Value channel, size_t *idx) {
  if (OpResult res = dyn_cast<OpResult>(channel)) {
    if (idx)
      *idx = res.getResultNumber();
    return channel.getDefiningOp();
  }
  // Channel must be a block argument. In this case we only support buffering
  // properties the channel maps to a Handshake function argument
  BlockArgument arg = cast<BlockArgument>(channel);
  Operation *op = arg.getParentBlock()->getParentOp();
  if (isa<handshake::FuncOp>(op)) {
    if (idx)
      *idx = arg.getArgNumber();
    return op;
  }
  return nullptr;
}

LogicalResult dynamatic::buffer::mapChannelsToProperties(
    handshake::FuncOp funcOp, const TimingDatabase &timingDB,
    llvm::MapVector<Value, ChannelBufProps> &channelProps) {

  // Combines any channel-specific buffering properties coming from IR
  // annotations to internal buffer specifications and stores the combined
  // properties into the channel map. Fails and marks the MILP unsatisfiable if
  // any of those combined buffering properties become unsatisfiable.
  auto deriveBufferingProperties = [&](Channel &channel) -> LogicalResult {
    ChannelBufProps ogProps = *channel.props;
    if (!ogProps.isSatisfiable()) {
      std::stringstream ss;
      std::string channelName;
      ss << "Channel buffering properties of channel '"
         << getUniqueName(*channel.value.getUses().begin())
         << "' are unsatisfiable " << ogProps
         << "Cannot proceed with buffer placement.";
      return channel.consumer->emitError() << ss.str();
    }

    // Check for satisfiability
    if (!channel.props->isSatisfiable()) {
      std::stringstream ss;
      std::string channelName;
      ss << "Including internal component buffers into buffering "
            "properties of channel '"
         << getUniqueName(*channel.value.getUses().begin())
         << "' made them unsatisfiable.\nProperties were " << ogProps
         << "before inclusion and were changed to " << *channel.props
         << "Cannot proceed with buffer placement.";
      return channel.consumer->emitError() << ss.str();
    }
    channelProps[channel.value] = *channel.props;
    return success();
  };

  // A value with no users has nothing to build a Channel from: dereferencing
  // `getUsers().begin()` on it is dereferencing the end iterator. Materialized
  // IR normally has none, because `materializeValue` sinks every unused value
  // -- but only those satisfying `eligibleForMaterialization`, i.e. ControlType
  // and ChannelType. A raw signal produced by `handshake.unbundle` is neither,
  // so it is never sunk (and `handshake.sink` would not accept it), and an
  // unbundled extra signal that nothing reads reaches here with no users.

  // Add channels originating from function arguments to the channel map
  for (auto [idx, arg] : llvm::enumerate(funcOp.getArguments())) {
    if (arg.use_empty())
      continue;
    Channel channel(arg, funcOp, *arg.getUsers().begin());
    if (failed(deriveBufferingProperties(channel)))
      return failure();
  }

  // Add channels originating from operations' results to the channel map
  for (Operation &op : funcOp.getOps()) {
    for (auto [idx, res] : llvm::enumerate(op.getResults())) {
      if (res.use_empty())
        continue;
      Channel channel(res, &op, *res.getUsers().begin());
      if (failed(deriveBufferingProperties(channel)))
        return failure();
    }
  }

  return success();
}

//===----------------------------------------------------------------------===//
// Transition frequencies carried by the IR
//===----------------------------------------------------------------------===//

bool dynamatic::buffer::hasFrequenciesAttr(handshake::FuncOp funcOp) {
  return funcOp->hasAttr(FREQUENCIES_ATTR_NAME);
}

LogicalResult dynamatic::buffer::readFrequenciesAttr(
    handshake::FuncOp funcOp, SmallVectorImpl<experimental::ArchBB> &archs) {
  auto malformed = [&]() {
    return funcOp->emitError()
           << "'" << FREQUENCIES_ATTR_NAME
           << "' must be an array of [srcBB, dstBB, numTransitions, "
              "isBackedge] integer quadruplets";
  };
  auto list = funcOp->getAttrOfType<ArrayAttr>(FREQUENCIES_ATTR_NAME);
  if (!list)
    return malformed();
  for (Attribute entry : list) {
    auto quad = dyn_cast<ArrayAttr>(entry);
    if (!quad || quad.size() != 4)
      return malformed();
    unsigned fields[4];
    for (auto [i, field] : llvm::enumerate(quad)) {
      auto integer = dyn_cast<IntegerAttr>(field);
      if (!integer || integer.getValue().isNegative())
        return malformed();
      fields[i] = integer.getValue().getZExtValue();
    }
    archs.emplace_back(fields[0], fields[1], fields[2], fields[3] != 0);
  }
  return success();
}

void dynamatic::buffer::writeFrequenciesAttr(
    handshake::FuncOp funcOp, ArrayRef<experimental::ArchBB> archs) {
  MLIRContext *ctx = funcOp.getContext();
  Builder builder(ctx);
  SmallVector<Attribute> entries;
  for (const experimental::ArchBB &arch : archs)
    entries.push_back(builder.getI64ArrayAttr(
        {arch.srcBB, arch.dstBB, arch.numTrans, arch.isBackEdge ? 1 : 0}));
  funcOp->setAttr(FREQUENCIES_ATTR_NAME, builder.getArrayAttr(entries));
}

bool dynamatic::buffer::hasBasicBlocks(handshake::FuncOp funcOp) {
  return llvm::any_of(funcOp.getOps(), [](Operation &op) {
    return getLogicBB(&op).has_value();
  });
}
