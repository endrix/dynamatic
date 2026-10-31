//===- TimingModels.cpp - Parse/Represent comp. timing models ---*- C++ -*-===//
//
// Dynamatic is under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// Definitions for timing modeling infrastructure, including the LLVM-style
// fromJSON functions that deserialize a JSON value into a specific object (see
// advanced documentation in ::llvm::json::Value).
//
//===----------------------------------------------------------------------===//

#include "dynamatic/Support/TimingModels.h"
#include "dynamatic/Dialect/Handshake/HandshakeInterfaces.h"
#include "dynamatic/Dialect/Handshake/HandshakeOps.h"
#include "dynamatic/Support/JSON/JSON.h"
#include "mlir/Support/LogicalResult.h"
#include "llvm/ADT/TypeSwitch.h"
#include "llvm/Support/JSON.h"
#include <fstream>

using namespace llvm;
using namespace mlir;
using namespace dynamatic;
using namespace dynamatic::handshake;

namespace ljson = llvm::json;

//===----------------------------------------------------------------------===//
// TimingDatabse definitions
//===----------------------------------------------------------------------===//

unsigned dynamatic::getOpDatawidth(Operation *op) {
  // Handshake operations have various semantics and must be handled on a
  // case-by-case basis
  return llvm::TypeSwitch<Operation *, unsigned>(op)
      .Case<handshake::SelectOp>([&](auto) {
        // The first operand of SelectOp is always an 1-bit wide control signal,
        // so here we look up the width of the second or third input's bitwidth
        return getHandshakeTypeBitWidth(op->getOperand(1).getType());
      })
      .Case<handshake::ArithOpInterface>([&](auto) {
        // This option matches all the handshake equivalent of arith/math
        // operations
        return getHandshakeTypeBitWidth(op->getOperand(0).getType());
      })
      .Case<handshake::MergeLikeOpInterface>(
          [&](handshake::MergeLikeOpInterface mergeLikeOp) {
            return getHandshakeTypeBitWidth(
                mergeLikeOp.getDataOperands().front().getType());
          })
      .Case<handshake::PriorityOp>([&](handshake::PriorityOp priorityOp) {
        // both inputs and the output are one type
        return getHandshakeTypeBitWidth(priorityOp.getHi().getType());
      })
      .Case<handshake::RaceOp>([&](handshake::RaceOp race) {
        // the decision's: the tokens are of its type, the flags one bit
        return getHandshakeTypeBitWidth(race.getResult().getType());
      })
      .Case<handshake::CommitOp, handshake::StandInOp>([&](auto) {
        // the channel through it; the kill is a raw wire beside it
        return getHandshakeTypeBitWidth(op->getOperand(0).getType());
      })
      .Case<handshake::BufferOp, handshake::ForkOp, handshake::LazyForkOp,
            handshake::BranchOp, handshake::SinkOp>([&](auto) {
        return getHandshakeTypeBitWidth(op->getOperand(0).getType());
      })
      .Case<handshake::ConditionalBranchOp>(
          [&](handshake::ConditionalBranchOp condOp) {
            return getHandshakeTypeBitWidth(condOp.getDataOperand().getType());
          })
      .Case<handshake::SourceOp, handshake::ConstantOp>([&](auto) {
        return getHandshakeTypeBitWidth(op->getResult(0).getType());
      })
      .Case<handshake::EndOp, handshake::JoinOp, handshake::BlockerOp>(
          [&](auto) {
            if (op->getNumOperands() == 0)
              return 0u;
            return getHandshakeTypeBitWidth(op->getOperand(0).getType());
          })
      .Case<handshake::LoadOp, handshake::StoreOp>([&](auto) {
        return std::max(getHandshakeTypeBitWidth(op->getOperand(0).getType()),
                        getHandshakeTypeBitWidth(op->getOperand(1).getType()));
      })
      .Case<handshake::MemoryOpInterface>(
          [&](handshake::MemoryOpInterface memOp) {
            FuncMemoryPorts ports = getMemoryPorts(memOp);
            return std::max(ports.ctrlWidth,
                            std::max(ports.addrWidth, ports.ctrlWidth));
          })
      .Default([&](auto) {
        op->emitError() << "Operation is unsupported in timing model";
        assert(false && "unsupported operation");
        return dynamatic::MAX_DATAWIDTH;
      });
}

LogicalResult TimingModel::getTotalDataDelay(unsigned bitwidth,
                                             double &delay) const {
  auto unitDelayOrFail = dataDelay.select(bitwidth);
  if (failed(unitDelayOrFail))
    return failure();
  delay = unitDelayOrFail->get();
  return success();
}

/// A handshake delay of a port model at `bitwidth` (PortModel::validDelayAt).
static double delayAt(const BitwidthDepMetric<double> &delays, double atOne,
                      unsigned bitwidth) {
  if (auto delay = delays.select(bitwidth); succeeded(delay))
    return delay->get();
  if (auto widest = delays.widestBitwidth(); succeeded(widest))
    return delays.data.at(*widest);
  return atOne;
}

double TimingModel::PortModel::dataDelayAt(unsigned bitwidth) const {
  return delayAt(dataDelay, 0.0, bitwidth);
}

double TimingModel::PortModel::validDelayAt(unsigned bitwidth) const {
  return delayAt(validDelays, validDelay, bitwidth);
}

double TimingModel::PortModel::readyDelayAt(unsigned bitwidth) const {
  return delayAt(readyDelays, readyDelay, bitwidth);
}

void TimingDatabase::insertTimingModel(StringRef timingModelKey,
                                       TimingModel &model) {
  models.try_emplace(timingModelKey, model);
}

const TimingModel *TimingDatabase::getModel(StringRef timingModelKey) const {
  auto it = models.find(timingModelKey);
  if (it == models.end())
    return nullptr;
  return &it->second;
}

/// The number of channels a unit joins or splits, as its RTL's SIZE parameter
/// counts them (HandshakeToHW sets it the same way), for the units whose
/// handshake grows with it: a fork's ready is an AND over its outputs, a
/// mux's data a select tree over its inputs; and a stand-in's kills, an OR
/// into its registers. 0 for every other unit.
static unsigned getUnitSize(Operation *op) {
  return llvm::TypeSwitch<Operation *, unsigned>(op)
      .Case<handshake::ForkOp, handshake::LazyForkOp>(
          [](auto forkOp) { return forkOp->getNumResults(); })
      .Case<handshake::MuxOp>(
          [](handshake::MuxOp muxOp) { return muxOp.getDataOperands().size(); })
      .Case<handshake::ControlMergeOp>([](handshake::ControlMergeOp cmergeOp) {
        return cmergeOp.getDataOperands().size();
      })
      .Case<handshake::MergeOp, handshake::FirstOp, handshake::JoinOp,
            handshake::BlockerOp>(
          [](auto joinOp) { return joinOp->getNumOperands(); })
      // a race by its inputs, tokens and flags together, as a first by its
      // operands -- each input's ready reads the others' valids -- or by its
      // candidates where it has more (ALTERNATIVES: candidates of one answer
      // add terms, not inputs): a size's shapes have as many inputs and at
      // most as many candidates, so the larger of the two is a bound from
      // above
      .Case<handshake::RaceOp>([](handshake::RaceOp race) {
        return std::max<unsigned>(race->getNumOperands(),
                                  race.getCandidates().size());
      })
      .Case<handshake::StandInOp>([](handshake::StandInOp standIn) {
        return static_cast<unsigned>(standIn.getKills().size());
      })
      .Default([](Operation *) { return 0u; });
}

const TimingModel *TimingDatabase::getModel(Operation *op) const {
  StringRef baseName = op->getName().getStringRef();

  // A buffer's six types are one unit, with an entry each beside the base
  // entry, which reduces over them: `handshake.buffer.ONE_SLOT_BREAK_R`. The
  // types share no path -- an opaque slot registers its data and valid, a
  // transparent one passes them through a multiplexer its register selects.
  // A model with no entry for the type times the buffer by the base entry.
  if (auto bufferOp = dyn_cast<handshake::BufferOp>(op)) {
    std::string typeKey =
        (baseName + "." + handshake::stringifyEnum(bufferOp.getBufferType()))
            .str();
    if (const TimingModel *model = getModel(StringRef(typeKey)))
      return model;
  }

  // A load a commit stops (`handshake.kill_domain`) is another circuit, one
  // that counts the words it owes and drops them on a kill (HandshakeToHW's
  // KILL_DROP): its own entry, `handshake.load.kill_drop`, where the model
  // has one; the base entry, the plain load's, otherwise.
  if (isa<handshake::LoadOp>(op) && op->hasAttr(handshake::KILL_DOMAIN_ATTR)) {
    if (const TimingModel *model =
            getModel(StringRef((baseName + ".kill_drop").str())))
      return model;
  }

  // A commit whose kill comes when its token is first offered
  // (`kill_at_valid`) is another circuit too, a flip-flop more and its kill
  // from the valid alone: `handshake.commit.at_valid`, where the model has
  // one; the base entry, the transfer's, otherwise.
  if (auto commit = dyn_cast<handshake::CommitOp>(op);
      commit && commit.getKillAtValid()) {
    if (const TimingModel *model =
            getModel(StringRef((baseName + ".at_valid").str())))
      return model;
  }

  // A race whose inputs reopen only after its answer was taken
  // (`reopen_after_taken`) is another circuit with entries of its own, sized
  // as the plain race's (`handshake.race.reopen_after_taken.size.<N>`), where
  // the model has them; the plain race's entries otherwise.
  std::string raceVariant;
  if (auto race = dyn_cast<handshake::RaceOp>(op);
      race && race.getReopenAfterTaken()) {
    raceVariant = (baseName + ".reopen_after_taken").str();
    std::string prefix = raceVariant + ".";
    if (models.count(raceVariant) ||
        llvm::any_of(models, [&](const auto &entry) {
          return entry.getKey().starts_with(prefix);
        }))
      baseName = raceVariant;
  }

  // A unit whose delays grow with its size is characterised at several sizes,
  // each an entry `<name>.size.<N>` beside the base entry, for the same reason
  // a multiplier's step is in its key: an entry nests by retiming path,
  // bitwidth and clock period, and a size is none of those. The op is timed
  // by the smallest size at or above its own, a bound from above, as a width
  // is; past the largest, by the largest, with a remark. A model with no
  // sized entries for the unit times it by its base entry.
  if (unsigned size = getUnitSize(op)) {
    std::string prefix = (baseName + ".size.").str();
    std::optional<uint64_t> nearest, largest;
    for (const auto &entry : models) {
      StringRef key = entry.getKey();
      if (!key.starts_with(prefix))
        continue;
      uint64_t candidate;
      if (key.drop_front(prefix.size()).getAsInteger(10, candidate))
        continue;
      if (candidate >= size && (!nearest || candidate < *nearest))
        nearest = candidate;
      if (!largest || candidate > *largest)
        largest = candidate;
    }
    if (nearest)
      return getModel(StringRef(prefix + std::to_string(*nearest)));
    if (largest) {
      std::string wanted = prefix + std::to_string(size);
      std::string largestKey = prefix + std::to_string(*largest);
      if (reportedMissingImpls.insert(wanted).second)
        op->emitRemark() << "TimingDatabase::getModel: no timing model for \""
                         << wanted << "\"; the entry for \"" << largestKey
                         << "\", the largest size characterised, is used "
                            "instead";
      return getModel(StringRef(largestKey));
    }
  }

  // if the operation is a floating point operation with multiple
  // possible implementations
  if (auto fpuImplInterface =
          llvm::dyn_cast<dynamatic::handshake::FPUImplInterface>(op)) {
    // include the implementation in the key
    std::string timingModelKey =
        (baseName + "." + stringifyEnum(fpuImplInterface.getFPUImpl())).str();
    return getModel(timingModelKey);
  }

  // An implementation chosen before placement is named in the op's
  // hw.parameters, and the model keys it the way it keys the floating-point
  // units: the sequential divider is `handshake.divui.sequential` and the
  // sequential multiplier `handshake.muli.sequential.<STEP>`, since STEP
  // multiplier bits a cycle are STEP rows of adders and a delay of their own.
  // The step is in the key rather than in the entry because the entry's
  // nesting is by retiming path, bitwidth and clock period, and an
  // implementation is not one of those.
  if (auto params = op->getAttrOfType<DictionaryAttr>("hw.parameters")) {
    auto impl = dyn_cast_or_null<StringAttr>(params.get("IMPL"));
    // The base entry is the pipelined implementation, the one Dynamatic
    // ships; an op that names it is timed by it with nothing to say.
    if (impl && impl.getValue() != "pipelined") {
      std::string implKey = (baseName + "." + impl.getValue()).str();
      std::string variantKey = implKey;
      std::optional<uint64_t> step;
      if (auto stepAttr = dyn_cast_or_null<IntegerAttr>(params.get("STEP"))) {
        step = stepAttr.getValue().getZExtValue();
        variantKey += "." + std::to_string(*step);
      }
      if (const TimingModel *model = getModel(StringRef(variantKey)))
        return model;
      // A step the model does not hold: the nearest larger one it holds. A
      // multiplier's step is clamped to its width, so a narrow op under a
      // wide step asks for its own width as the step, and the wider step's
      // unit at that width is the same unit; a step chosen smaller than any
      // characterised one is timed by the next one up, a bound from above.
      if (step) {
        std::string prefix = implKey + ".";
        std::optional<uint64_t> nearest;
        for (const auto &entry : models) {
          StringRef key = entry.getKey();
          if (!key.starts_with(prefix))
            continue;
          uint64_t candidate;
          if (key.drop_front(prefix.size()).getAsInteger(10, candidate))
            continue;
          if (candidate >= *step && (!nearest || candidate < *nearest))
            nearest = candidate;
        }
        if (nearest) {
          std::string nearestKey = prefix + std::to_string(*nearest);
          if (reportedMissingImpls.insert(variantKey).second)
            op->emitRemark()
                << "TimingDatabase::getModel: no timing model for \""
                << variantKey << "\"; the entry for \"" << nearestKey
                << "\", the nearest larger step, is used instead";
          return getModel(StringRef(nearestKey));
        }
      }
      if (const TimingModel *model = getModel(StringRef(implKey)))
        return model;
      // The model does not describe the implementation this operation will be
      // built as, and the base entry is some other implementation's: say so,
      // once per key, since a model is asked for an operation once per signal
      // and once per constraint.
      if (reportedMissingImpls.insert(variantKey).second)
        op->emitRemark() << "TimingDatabase::getModel: no timing model for \""
                         << variantKey << "\"; the entry for \"" << baseName
                         << "\" is used instead";
    }
  }

  return getModel(baseName);
}

FailureOr<double> TimingDatabase::getLatency(Operation *op,
                                             SignalType signalType,
                                             double targetPeriod,
                                             unsigned pathId) const {
  // Our current timing model doesn't have latency information for valid and
  // ready signals; assume it is 0.
  if (signalType != SignalType::DATA)
    return 0.0;

  // A latency the operation carries is its latency when its implementation
  // was chosen before placement: a sequential divider or multiplier
  // (hw.parameters IMPL = "sequential", BITWIDTH cycles a result where the
  // model's pipelined unit takes a fixed few) says so on the op, and the
  // model's entry is for the other implementation. Any other op's latency
  // is the model's, whatever it carries: set-unit-impl-attr may run again
  // with another model or period and must not read its own earlier write.
  if (auto attr = op->getAttrOfType<IntegerAttr>("latency"))
    if (auto params = op->getAttrOfType<DictionaryAttr>("hw.parameters"))
      if (auto impl = dyn_cast_or_null<StringAttr>(params.get("IMPL")))
        if (impl.getValue() == "sequential")
          return static_cast<double>(attr.getInt());

  const TimingModel *model = getModel(op);
  if (!model) {
    op->emitWarning() << "TimingDatabase::getLatency: no timing model for op";
    return failure();
  }

  // Walk inward through the path -> bitwidth -> clock-period nesting.
  auto latAndMaxFreqByBitwidth = model->latAndMaxFreqByPath.select(pathId);
  if (failed(latAndMaxFreqByBitwidth)) {
    op->emitWarning()
        << "TimingDatabase::getLatency: no entry for retiming-path id "
        << pathId;
    return failure();
  }
  auto latAndMaxFreqByClockPeriod = latAndMaxFreqByBitwidth->get().select(op);
  if (failed(latAndMaxFreqByClockPeriod)) {
    // The operation is wider than the widest characterised bitwidth. Its
    // latency is still known: a unit's latency is its stage count, a
    // generator parameter that does not change with the width (the same
    // number is handed to the generator as LATENCY), so the widest entry
    // holds for any wider operation. Only the delay is unknown, and the
    // delay lookups keep failing for such a width.
    auto widest = latAndMaxFreqByBitwidth->get().widestBitwidth();
    if (failed(widest)) {
      op->emitWarning()
          << "TimingDatabase::getLatency: bitwidth not characterised in the "
             "timing model";
      return failure();
    }
    op->emitRemark() << "TimingDatabase::getLatency: bitwidth "
                     << getOpDatawidth(op)
                     << " is above the widest characterised (" << *widest
                     << "); the latency is the widest entry's";
    latAndMaxFreqByClockPeriod = latAndMaxFreqByBitwidth->get().select(*widest);
  }
  auto latencyOrFail =
      latAndMaxFreqByClockPeriod->get().selectLatency(targetPeriod);
  if (failed(latencyOrFail)) {
    op->emitWarning()
        << "TimingDatabase::getLatency: no latency data for target period "
        << targetPeriod;
    return failure();
  }
  double latency = *latencyOrFail;

  // FIXME: We compensante for the fact that the LSQ has roughly 3 extra cycles
  // of latency on loads compared to an MC here because our timing models are
  // currenty unable to account for this. It's obviosuly very bad to
  // special-case this here so we should find a way to properly express this
  // information in our models.
  if (auto loadOp = dyn_cast<handshake::LoadOp>(op)) {
    auto memOp = findMemInterface(loadOp.getAddressResult());
    if (isa_and_present<handshake::LSQOp>(memOp))
      latency += 3;
  }
  return latency;
}

double TimingDatabase::getInitiationInterval(Operation *op) const {
  // The interval is read the same way the latency above is: only from an
  // operation whose implementation was chosen before placement and runs one
  // operation at a time. The model's units are pipelined, so a unit that
  // does not say otherwise accepts an operand set every cycle.
  if (auto attr = op->getAttrOfType<IntegerAttr>("initiation_interval"))
    if (auto params = op->getAttrOfType<DictionaryAttr>("hw.parameters"))
      if (auto impl = dyn_cast_or_null<StringAttr>(params.get("IMPL")))
        if (impl.getValue() == "sequential" && attr.getInt() >= 1)
          return static_cast<double>(attr.getInt());
  return 1.0;
}

LogicalResult TimingDatabase::getInternalCombinationalDelay(
    Operation *op, SignalType signalType, double &delay,
    double targetPeriod) const // Our current timing model doesn't have latency
                               // information for valid and
// ready signals, assume it is 0
{
  const TimingModel *model = getModel(op);
  if (!model)
    return failure();

  // Internal combinational delay uses retiming path 0. Walk inward through
  // the path -> bitwidth -> clock-period nesting.
  auto latAndMaxFreqByBitwidth = model->latAndMaxFreqByPath.select(0);
  if (failed(latAndMaxFreqByBitwidth))
    return failure();
  auto latAndMaxFreqByClockPeriod = latAndMaxFreqByBitwidth->get().select(op);
  if (failed(latAndMaxFreqByClockPeriod))
    return failure();
  auto delayOrFail =
      latAndMaxFreqByClockPeriod->get().selectDelay(targetPeriod);
  if (failed(delayOrFail))
    return failure();
  delay = *delayOrFail;

  return success();
}

LogicalResult TimingDatabase::getInternalDelay(Operation *op,
                                               SignalType signalType,
                                               double &delay) const {
  const TimingModel *model = getModel(op);
  if (!model)
    return failure();

  switch (signalType) {
  case SignalType::DATA: {
    auto delayOrFail = model->dataDelay.select(op);
    if (failed(delayOrFail))
      return failure();
    delay = delayOrFail->get();
    return success();
  }
  case SignalType::VALID:
    delay = model->validDelay;
    return success();
  case SignalType::READY:
    delay = model->readyDelay;
    return success();
  }
}

LogicalResult TimingDatabase::getPortDelay(Operation *op, SignalType signalType,
                                           PortType portType,
                                           double &delay) const {
  const TimingModel *model = getModel(op);
  if (!model)
    return failure();

  const TimingModel::PortModel &portModel =
      portType == PortType::IN ? model->inputModel : model->outputModel;

  unsigned bitwidth = getOpDatawidth(op);
  switch (signalType) {
  case SignalType::DATA:
    delay = portModel.dataDelayAt(bitwidth);
    return success();
  case SignalType::VALID:
    delay = portModel.validDelayAt(bitwidth);
    return success();
  case SignalType::READY:
    delay = portModel.readyDelayAt(bitwidth);
    return success();
  }
}

LogicalResult TimingDatabase::getTotalDelay(Operation *op,
                                            SignalType signalType,
                                            double &delay) const {
  const TimingModel *model = getModel(op);
  if (!model)
    return failure();
  switch (signalType) {
  case SignalType::DATA:
    return model->getTotalDataDelay(getOpDatawidth(op), delay);
  case SignalType::VALID:
    delay = model->validDelay;
    return success();
  case SignalType::READY:
    delay = model->readyDelay;
    return success();
  }
}

const SpecTimingModel *
TimingDatabase::getSpecModel(StringRef timingModelKey) const {
  auto it = specModels.find(timingModelKey);
  if (it == specModels.end())
    return nullptr;
  return &it->second;
}

const SpecTimingModel *TimingDatabase::getSpecModel(Operation *op) const {
  if (!op)
    return nullptr;
  return getSpecModel(op->getName().getStringRef());
}

static FailureOr<SignalType> signalTypeFromString(StringRef s) {
  if (s == "data")
    return SignalType::DATA;
  if (s == "valid")
    return SignalType::VALID;
  if (s == "ready")
    return SignalType::READY;
  llvm::errs() << "spec timing port has unrecognised signal kind \"" << s
               << "\"\n";
  return failure();
}

// reads an array of delays into a delay list, or fails
// the delay of the path is a function of its bitwidth
static FailureOr<SpecTimingDelayList>
parseDelayList(const ljson::Array *delays) {
  // check array of delays exists
  if (!delays) {
    llvm::errs() << "spec timing object has no array of delays\n";
    return failure();
  }

  // struct to store parsed info in
  SpecTimingDelayList delayList;

  // for each delay
  for (const ljson::Value &delayVal : *delays) {
    // get as json object
    const ljson::Object *delayObj = delayVal.getAsObject();
    if (!delayObj) {
      llvm::errs() << "spec timing delay is not a JSON object\n";
      return failure();
    }

    // declare the delay struct
    SpecTimingDelay delay;

    // read the delay
    std::optional<double> d = delayObj->getNumber("delay");
    if (!d) {
      llvm::errs() << "spec timing delay has no delay\n";
      return failure();
    }
    // store in struct
    delay.delay = *d;

    // read the bitwidth
    std::optional<int64_t> bw = delayObj->getInteger("bitwidth");
    if (!bw) {
      llvm::errs() << "spec timing delay has no bitwidth\n";
      return failure();
    }
    // store bitwidth in struct
    delay.bitwidth = *bw;

    // move into the delay list
    delayList.addDelay(std::move(delay));
  }
  return delayList;
}

// reads a port name and signal kind into a port, or fails
static FailureOr<SpecTimingPort> parsePort(const ljson::Object *portObj) {
  // check port exists
  if (!portObj) {
    llvm::errs() << "spec timing port is not a JSON object\n";
    return failure();
  }

  // struct to save the info in
  SpecTimingPort port;

  // read the port name (whether input or output)
  std::optional<StringRef> portName = portObj->getString("name");
  if (!portName) {
    llvm::errs() << "spec timing port has no name\n";
    return failure();
  }
  // save in struct
  port.name = portName->str();

  // read the signal kind as a string
  std::optional<StringRef> signalName = portObj->getString("signal");
  if (!signalName) {
    llvm::errs() << "spec timing port has no signal\n";
    return failure();
  }

  // convert the signal string to a SignalType enum
  FailureOr<SignalType> signalType = signalTypeFromString(*signalName);
  if (failed(signalType))
    // signalTypeFromString prints the error message if failed
    return failure();

  // save in struct
  port.signal = *signalType;

  return port;
}

// reads a port2port edge [from port, to port, delay list] or fails
static FailureOr<SpecTimingPort2Port>
parsePort2Port(const ljson::Object *edgeObj) {
  // struct to store info in
  SpecTimingPort2Port edge;

  // read the 'from' port
  FailureOr<SpecTimingPort> from = parsePort(edgeObj->getObject("from"));
  if (failed(from))
    // parsePort prints the error message if failed
    return failure();

  // store in struct
  edge.from = *from;

  // read the 'to' port
  FailureOr<SpecTimingPort> to = parsePort(edgeObj->getObject("to"));
  if (failed(to))
    // parsePort prints the error message if failed
    return failure();

  // store in struct
  edge.to = *to;

  // read the list of delays
  FailureOr<SpecTimingDelayList> delayList =
      parseDelayList(edgeObj->getArray("delayList"));
  if (failed(delayList))
    // parseDelayList prints the error message if failed
    return failure();

  // store in struct
  edge.delayList = std::move(*delayList);

  return edge;
}

// reads a port2reg port delay [port, delay list] or fails
static FailureOr<SpecTimingPort2Reg>
parsePort2Reg(const ljson::Object *portDelayObj) {
  // struct to store info
  SpecTimingPort2Reg portDelay;

  // read the port
  FailureOr<SpecTimingPort> port = parsePort(portDelayObj);
  if (failed(port))
    // parsePort prints the error message if failed
    return failure();

  // store in struct
  portDelay.port = *port;

  // read the list of delays
  FailureOr<SpecTimingDelayList> delayList =
      parseDelayList(portDelayObj->getArray("delayList"));
  if (failed(delayList))
    // parseDelayList prints the error message if failed
    return failure();

  // store in struct
  portDelay.delayList = std::move(*delayList);

  return portDelay;
}

// reads a reg2port port delay [port, delay list] or fails
static FailureOr<SpecTimingReg2Port>
parseReg2Port(const ljson::Object *portDelayObj) {
  // struct to save into
  SpecTimingReg2Port portDelay;

  // read the port
  FailureOr<SpecTimingPort> port = parsePort(portDelayObj);
  if (failed(port))
    // parsePort prints the error message if failed
    return failure();

  // store tos truct
  portDelay.port = *port;

  // read the list of delays
  FailureOr<SpecTimingDelayList> delayList =
      parseDelayList(portDelayObj->getArray("delayList"));
  if (failed(delayList))
    // parseDelayList prints the error message if failed
    return failure();

  // store to struct
  portDelay.delayList = std::move(*delayList);

  return portDelay;
}

LogicalResult TimingDatabase::readSpecTimingFromJSON(std::string &jsonpath,
                                                     TimingDatabase &timingDB) {
  // open the file
  std::ifstream inputFile(jsonpath);
  if (!inputFile.is_open()) {
    llvm::errs() << "Failed to open spec timing JSON at \"" << jsonpath
                 << "\"\n";
    return failure();
  }

  // read the file into a string
  std::string jsonString;
  std::string line;
  while (std::getline(inputFile, line))
    jsonString += line;

  // parse the string as JSON
  llvm::Expected<ljson::Value> value = ljson::parse(jsonString);
  if (!value) {
    llvm::errs() << "Failed to parse spec timing JSON in \"" << jsonpath
                 << "\"\n";
    return failure();
  }

  // get as an object
  const ljson::Object *root = value->getAsObject();
  if (!root) {
    llvm::errs() << "Spec timing JSON root must be an object\n";
    return failure();
  }

  // read one timing model per type of unit
  for (const auto &unitEntry : *root) {
    // key is the operation type this info is for
    StringRef unitKey = unitEntry.first;

    // get characterization info as object
    const ljson::Object *timingModelInfo = unitEntry.second.getAsObject();
    if (!timingModelInfo) {
      llvm::errs() << "spec timing model is not a JSON object\n";
      return failure();
    }

    // declare the model we will fill in
    SpecTimingModel model;

    // read the port2port edges as an arry
    const ljson::Array *port2portArr = timingModelInfo->getArray("port2port");
    if (!port2portArr) {
      llvm::errs() << "spec timing unit has no port2port array\n";
      return failure();
    }

    // for each port2port edge
    for (const ljson::Value &port2portVal : *port2portArr) {

      // get as json object
      const ljson::Object *port2portObj = port2portVal.getAsObject();
      if (!port2portObj) {
        llvm::errs() << "port2port delay is not a JSON object\n";
        return failure();
      }

      // parse into struct
      FailureOr<SpecTimingPort2Port> port2port = parsePort2Port(port2portObj);
      if (failed(port2port))
        // parsePort2Port prints the error message if failed
        return failure();

      // store in model
      model.port2port.push_back(std::move(*port2port));
    }

    // read the port2reg delays as an array
    const ljson::Array *port2regArr = timingModelInfo->getArray("port2reg");
    if (!port2regArr) {
      llvm::errs() << "spec timing unit has no port2reg array\n";
      return failure();
    }

    // for each port2reg port delay
    for (const ljson::Value &port2regVal : *port2regArr) {

      // get as json object
      const ljson::Object *port2regObj = port2regVal.getAsObject();
      if (!port2regObj) {
        llvm::errs() << "port2reg delay is not a JSON object\n";
        return failure();
      }

      // parse into struct
      FailureOr<SpecTimingPort2Reg> port2reg = parsePort2Reg(port2regObj);

      if (failed(port2reg))
        // parsePort2Reg prints the error message if failed
        return failure();

      // store in model
      model.port2reg.push_back(std::move(*port2reg));
    }

    // read the reg2port delays as an array
    const ljson::Array *reg2portArr = timingModelInfo->getArray("reg2port");
    if (!reg2portArr) {
      llvm::errs() << "spec timing unit has no reg2port array\n";
      return failure();
    }

    // for each reg2port port delay
    for (const ljson::Value &reg2portVal : *reg2portArr) {

      // get as json object
      const ljson::Object *reg2portObj = reg2portVal.getAsObject();
      if (!reg2portObj) {
        llvm::errs() << "reg2port delay is not a JSON object\n";
        return failure();
      }

      // parse into struct
      FailureOr<SpecTimingReg2Port> reg2port = parseReg2Port(reg2portObj);
      if (failed(reg2port))
        // parseReg2Port prints the error message if failed
        return failure();

      // store in model
      model.reg2port.push_back(std::move(*reg2port));
    }

    // store the unit's model under its key
    timingDB.specModels[unitKey] = std::move(model);
  }
  return success();
}

LogicalResult TimingDatabase::readFromJSON(std::string &jsonpath,
                                           TimingDatabase &timingDB) {
  // Open the timing database
  std::ifstream inputFile(jsonpath);
  if (!inputFile.is_open()) {
    llvm::errs() << "Failed to open timing database\n";
    return failure();
  }

  // Read the JSON content from the file and into a string
  std::string jsonString;
  std::string line;
  while (std::getline(inputFile, line))
    jsonString += line;

  // Try to parse the string as a JSON
  llvm::Expected<ljson::Value> value = ljson::parse(jsonString);
  if (!value) {
    llvm::errs() << "Failed to parse timing models in \"" << jsonpath << "\"\n";
    return failure();
  }

  // Deserialize into a timing database
  ljson::Path::Root jsonRoot(jsonpath);
  return success(fromJSON(*value, timingDB, ljson::Path(jsonRoot)));
}

//===----------------------------------------------------------------------===//
// JSON parsing
//===----------------------------------------------------------------------===//

/// Returns from the enclosing function if the argument evaluates to false. This
/// is useful in the fromJSON functions.
#define FW_FALSE(ret)                                                          \
  if (!(ret))                                                                  \
    return false;

/// Parses an unsigned number representing a bitwidth from a JSON key. Returns
/// true and sets the second argument to the parsed number if the key represents
/// a valid unsigned number; returns false otherwise.
static bool bitwidthFromJSON(const ljson::ObjectKey &value, unsigned &bitwidth,
                             ljson::Path path) {
  StringRef key = value;
  if (std::any_of(key.begin(), key.end(),
                  [](char c) { return !std::isdigit(c); })) {
    path.report("expected unsigned integer for bitwidth");
    return false;
  }
  bitwidth = std::stoi(key.str());
  return true;
}

/// Parses an unsigned number representing a retiming-path id from a JSON key.
/// Returns true and sets the second argument to the parsed number if the key
/// represents a valid unsigned number; returns false otherwise.
static bool pathIdFromJSON(const ljson::ObjectKey &value, unsigned &pathId,
                           ljson::Path path) {
  StringRef key = value;
  if (std::any_of(key.begin(), key.end(),
                  [](char c) { return !std::isdigit(c); })) {
    path.report("expected unsigned integer for retiming-path id");
    return false;
  }
  pathId = std::stoi(key.str());
  return true;
}

/// Deserializes an object of type T that is nested under a list of keys inside
/// the passed JSON object. Behaves like the fromJSON functions (See
/// ::llvm::json::Value's documentation).
template <typename T>
static bool deserializeNested(ArrayRef<std::string> keys,
                              const ljson::Object *object, T &out,
                              ljson::Path path) {
  assert(!keys.empty() && "list of keys must be non-empty");

  size_t lastElem = keys.size() - 1;
  const ljson::Object *currentObj = object;
  ljson::Path currentPath = path;
  for (auto [idx, k] : llvm::enumerate(keys)) {
    currentPath = currentPath.field(k);
    if (idx == lastElem) {
      if (const ljson::Value *value = currentObj->get(k))
        return fromJSON(*value, out, currentPath);
      path.report("expected last key in path to exist");
      return false;
    }
    if (const ljson::Object *nextObject = currentObj->getObject(k))
      currentObj = nextObject;
    else {
      path.report("expected last key in path to exist");
      return false;
    }
  }

  return true;
}

bool dynamatic::fromJSON(const ljson::Value &value,
                         BitwidthDepMetric<double> &metric, ljson::Path path) {
  const ljson::Object *object = value.getAsObject();
  if (!object) {
    path.report("expected JSON object");
    return false;
  }

  for (const auto &[bitwidthKey, metricValue] : *object) {
    unsigned bitwidth;
    if (!bitwidthFromJSON(bitwidthKey, bitwidth, path.field(bitwidthKey)))
      return false;
    double dataValue;
    if (!fromJSON(metricValue, dataValue, path.field(bitwidthKey))) {
      return false;
    }
    metric.data[bitwidth] = dataValue;
  }
  return true;
}

bool dynamatic::fromJSON(const ljson::Value &value, DelayDepMetric &metric,
                         ljson::Path path) {
  const ljson::Object *object = value.getAsObject();

  if (!object) {
    path.report("expected JSON object");
    return false;
  }

  // Key-value pair of {delay : latency, delay : latency}
  for (const auto &[delayKey, latencyValue] : *object) {
    double delay = std::stod(delayKey.str());
    double latency;
    if (!fromJSON(latencyValue, latency, path.field(delayKey)))
      return false;
    metric.data[delay] = latency;
  }

  return true;
}

bool dynamatic::fromJSON(const ljson::Value &value,
                         BitwidthDepMetric<DelayDepMetric> &metric,
                         ljson::Path path) {

  const ljson::Object *object = value.getAsObject();

  if (!object) {
    path.report("expected JSON object");
    return false;
  }

  // The outer keys are bitwidths; each maps to a delay-dependent
  // timing metric.
  for (const auto &[bitwidthKey, metricValue] : *object) {
    unsigned bitwidth;
    if (!bitwidthFromJSON(bitwidthKey, bitwidth, path.field(bitwidthKey)))
      return false;

    DelayDepMetric delayDepStruct;
    if (!fromJSON(metricValue, delayDepStruct, path.field(bitwidthKey)))
      return false;

    metric.data[bitwidth] = delayDepStruct;
  }

  return true;
}

bool dynamatic::fromJSON(const ljson::Value &value,
                         PathDepMetric &latAndMaxFreqByPath, ljson::Path path) {
  const ljson::Object *object = value.getAsObject();
  if (!object) {
    path.report("expected JSON object");
    return false;
  }

  // The outer keys are retiming-path ids; each maps to a bitwidth-dependent
  // timing metric.
  for (const auto &[pathKey, metricValue] : *object) {
    unsigned pathId;
    if (!pathIdFromJSON(pathKey, pathId, path.field(pathKey)))
      return false;

    BitwidthDepMetric<DelayDepMetric> bitwidthMetric;
    if (!fromJSON(metricValue, bitwidthMetric, path.field(pathKey)))
      return false;

    latAndMaxFreqByPath.data[pathId] = bitwidthMetric;
  }

  return true;
}

static const std::string LATENCY[] = {"latency"};
static const std::string DELAY[] = {"delay", "data"};
static const std::string DELAY_VALID[] = {"delay", "valid", "1"};
static const std::string DELAY_READY[] = {"delay", "ready", "1"};
static const std::string DELAY_VALID_WIDTHS[] = {"delay", "valid"};
static const std::string DELAY_READY_WIDTHS[] = {"delay", "ready"};
static const std::string DELAY_VR[] = {"delay", "VR"};
static const std::string DELAY_CV[] = {"delay", "CV"};
static const std::string DELAY_CR[] = {"delay", "CR"};
static const std::string DELAY_VC[] = {"delay", "VC"};
static const std::string DELAY_VD[] = {"delay", "VD"};
static const std::string DELAY_VK[] = {"delay", "VK"};
static const std::string DELAY_RK[] = {"delay", "RK"};

bool dynamatic::fromJSON(const ljson::Value &value,
                         TimingModel::PortModel &model, ljson::Path path) {
  const ljson::Object *object = value.getAsObject();
  if (!object) {
    path.report("expected JSON object");
    return false;
  }

  // Deserialize the data delays
  FW_FALSE(deserializeNested(DELAY, object, model.dataDelay, path));
  // Deserialize the valid/ready delays
  FW_FALSE(deserializeNested(DELAY_VALID, object, model.validDelay, path));
  FW_FALSE(deserializeNested(DELAY_READY, object, model.readyDelay, path));
  // and the same at every width the model has them at, "1" among them
  FW_FALSE(
      deserializeNested(DELAY_VALID_WIDTHS, object, model.validDelays, path));
  FW_FALSE(
      deserializeNested(DELAY_READY_WIDTHS, object, model.readyDelays, path));
  return true;
}

bool dynamatic::fromJSON(const ljson::Value &value, TimingModel &model,
                         ljson::Path path) {

  const ljson::Object *object = value.getAsObject();
  if (!object) {
    path.report("expected JSON object");
    return false;
  }

  // Deserialize the latency and max frequency
  FW_FALSE(deserializeNested(LATENCY, object, model.latAndMaxFreqByPath, path));
  // Deserialize the data delays
  FW_FALSE(deserializeNested(DELAY, object, model.dataDelay, path));
  // Deserialize the valid/ready delay
  FW_FALSE(deserializeNested(DELAY_VALID, object, model.validDelay, path));
  FW_FALSE(deserializeNested(DELAY_READY, object, model.readyDelay, path));

  // Deserialize the wire-to-wire delays
  FW_FALSE(deserializeNested(DELAY_VR, object, model.validToReady, path));
  FW_FALSE(deserializeNested(DELAY_CV, object, model.condToValid, path));
  FW_FALSE(deserializeNested(DELAY_CR, object, model.condToReady, path));
  FW_FALSE(deserializeNested(DELAY_VC, object, model.validToCond, path));
  FW_FALSE(deserializeNested(DELAY_VD, object, model.validToData, path));
  // A commit's kill (`handshake.commit`), where the model has it: optional,
  // since no other unit has a kill out.
  if (const ljson::Object *delays = object->getObject("delay")) {
    if (delays->get("VK"))
      FW_FALSE(deserializeNested(DELAY_VK, object, model.validToKill, path));
    if (delays->get("RK"))
      FW_FALSE(deserializeNested(DELAY_RK, object, model.readyToKill, path));
  }

  // Deserialize the input ports' model
  if (const ljson::Value *value = object->get("inport")) {
    FW_FALSE(fromJSON(*value, model.inputModel, path.field("inport")));
  } else {
    path.report("expected to find \"inport\" key");
    return false;
  }

  // Deserialize the output ports' model
  if (const ljson::Value *value = object->get("outport")) {
    FW_FALSE(fromJSON(*value, model.outputModel, path.field("outport")));
  } else {
    path.report("expected to find \"outport\" key");
    return false;
  }

  return true;
}

bool dynamatic::fromJSON(const ljson::Value &jsonValue,
                         TimingDatabase &timingDB, ljson::Path path) {
  const ljson::Object *components = jsonValue.getAsObject();
  if (!components)
    return false;

  for (const auto &[timingModelKey, cmpInfo] : *components) {
    TimingModel model;
    ljson::Path keyPath = path.field(timingModelKey);
    fromJSON(cmpInfo, model, keyPath);
    timingDB.insertTimingModel(timingModelKey, model);
  }
  return true;
}
