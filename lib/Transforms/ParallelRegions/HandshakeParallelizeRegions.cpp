//===- HandshakeParallelizeRegions.cpp - Run regions concurrently -*- C++ -*-===//
//
// Dynamatic is under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// Implements the --handshake-parallelize-regions pass.
//
// The sequential lowering chains sibling loop nests: the exit branch of one
// hands the control token to the entry merge of the next. Given the groups of
// regions an analysis has declared independent, the pass forks the entry
// block's control into every region of a group at once and joins the regions'
// exit tokens in the successor block. Values that entered a region through the
// previous region's exit branch are re-sourced from the entry block, so that
// nothing in a region waits on another.
//
//===----------------------------------------------------------------------===//

#include "dynamatic/Analysis/NameAnalysis.h"
#include "dynamatic/Dialect/Handshake/HandshakeAttributes.h"
#include "dynamatic/Dialect/Handshake/HandshakeInterfaces.h"
#include "dynamatic/Dialect/Handshake/HandshakeOps.h"
#include "dynamatic/Dialect/Handshake/HandshakeTypes.h"
#include "dynamatic/Support/Attribute.h"
#include "dynamatic/Support/CFG.h"
#include "dynamatic/Support/LLVM.h"
#include "dynamatic/Transforms/BufferPlacement/Utils/BufferingSupport.h"
#include "experimental/Support/StdProfiler.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/Value.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"
#include <optional>

using namespace mlir;
using namespace dynamatic;
using namespace dynamatic::handshake;
using dynamatic::experimental::ArchBB;

#include "dynamatic/Transforms/Passes.h" // IWYU pragma: keep
namespace dynamatic {
#define GEN_PASS_DEF_HANDSHAKEPARALLELIZEREGIONS
#include "dynamatic/Transforms/Passes.h.inc"
} // namespace dynamatic

/// The function attribute the analysis writes and this pass consumes.
static constexpr llvm::StringLiteral REGIONS_ATTR("handshake.parallel_regions");

namespace {

/// One entry of the attribute: the block whose control starts the regions,
/// the regions in the order the sequential lowering ran them, and the block
/// they all lead to.
struct RegionGroup {
  unsigned entry;
  SmallVector<SmallVector<unsigned>> regions;
  unsigned successor;
};

/// Where a block sits with respect to one group.
struct Place {
  enum Kind { NONE, ENTRY, REGION, SUCCESSOR, OUTSIDE } kind = NONE;
  unsigned region = 0;
};

/// What a value that crosses from one region into the next resolves to once
/// followed back through the region it comes from: a value the entry block
/// (or a function argument) provides, or a constant the lowering materialized
/// inside the region.
struct Source {
  Value value;
  handshake::ConstantOp constant;
};

struct HandshakeParallelizeRegionsPass
    : public dynamatic::impl::HandshakeParallelizeRegionsBase<
          HandshakeParallelizeRegionsPass> {
  using HandshakeParallelizeRegionsBase::HandshakeParallelizeRegionsBase;

  void runDynamaticPass() override;

private:
  /// Rewires one group. `archs` is rewritten in place when `haveArchs`.
  LogicalResult parallelize(handshake::FuncOp funcOp, const RegionGroup &group,
                            SmallVectorImpl<ArchBB> &archs, bool haveArchs);
};

} // namespace

static LogicalResult parseGroups(handshake::FuncOp funcOp,
                                 SmallVectorImpl<RegionGroup> &groups) {
  Attribute attr = funcOp->getAttr(REGIONS_ATTR);
  if (!attr)
    return success();
  auto malformed = [&]() {
    return funcOp->emitError()
           << "'" << REGIONS_ATTR
           << "' must be an array of {entry, regions, successor} "
              "dictionaries, regions being an array of at least two arrays "
              "of block ids";
  };
  auto asUnsigned = [](Attribute a, unsigned &out) {
    auto integer = dyn_cast_if_present<IntegerAttr>(a);
    if (!integer || integer.getValue().isNegative())
      return false;
    out = integer.getValue().getZExtValue();
    return true;
  };
  auto array = dyn_cast<ArrayAttr>(attr);
  if (!array)
    return malformed();
  for (Attribute entry : array) {
    auto dict = dyn_cast<DictionaryAttr>(entry);
    if (!dict)
      return malformed();
    RegionGroup group;
    if (!asUnsigned(dict.get("entry"), group.entry) ||
        !asUnsigned(dict.get("successor"), group.successor))
      return malformed();
    auto regions = dyn_cast_if_present<ArrayAttr>(dict.get("regions"));
    if (!regions || regions.size() < 2)
      return malformed();
    for (Attribute region : regions) {
      auto blocks = dyn_cast<ArrayAttr>(region);
      if (!blocks || blocks.empty())
        return malformed();
      SmallVector<unsigned> ids;
      for (Attribute block : blocks) {
        unsigned id;
        if (!asUnsigned(block, id))
          return malformed();
        ids.push_back(id);
      }
      group.regions.push_back(std::move(ids));
    }
    groups.push_back(std::move(group));
  }
  return success();
}

/// Block arguments belong to the entry block; results belong to the block of
/// their producer, if it has one.
static std::optional<unsigned> blockOf(Value val) {
  if (auto res = dyn_cast<OpResult>(val))
    return getLogicBB(res.getOwner());
  return ENTRY_BB;
}

static Place placeOf(std::optional<unsigned> bb,
                     const llvm::DenseMap<unsigned, Place> &places) {
  if (!bb)
    return {Place::NONE, 0};
  if (auto it = places.find(*bb); it != places.end())
    return it->second;
  return {Place::OUTSIDE, 0};
}

LogicalResult HandshakeParallelizeRegionsPass::parallelize(
    handshake::FuncOp funcOp, const RegionGroup &group,
    SmallVectorImpl<ArchBB> &archs, bool haveArchs) {
  unsigned n = group.regions.size();

  // Place every block of the group; a block named twice is a malformed group.
  llvm::DenseMap<unsigned, Place> places;
  auto place = [&](unsigned bb, Place p) -> LogicalResult {
    if (!places.insert({bb, p}).second)
      return funcOp->emitError() << "block " << bb << " appears twice in a '"
                                 << REGIONS_ATTR << "' group";
    return success();
  };
  if (failed(place(group.entry, {Place::ENTRY, 0})))
    return failure();
  for (auto [i, blocks] : llvm::enumerate(group.regions))
    for (unsigned bb : blocks)
      if (failed(place(bb, {Place::REGION, (unsigned)i})))
        return failure();
  if (failed(place(group.successor, {Place::SUCCESSOR, 0})))
    return failure();

  LogicBBs bbs = getLogicBBs(funcOp);
  for (auto &[bb, p] : places) {
    if (!bbs.blocks.contains(bb))
      return funcOp->emitError() << "block " << bb << " named in '"
                                 << REGIONS_ATTR << "' has no operation";
  }

  // Walk every edge that lands in a block of the group and classify it. The
  // sequential shape admits exactly one control edge from the entry into the
  // first region, one from each region's exit into the next region's entry
  // merge, and one from the last region into the successor's merge; data may
  // flow from the entry into any region, from a region into the next (to be
  // re-sourced below), and from the last region into the successor.
  Value entryCtrl;
  ControlMergeOp entryMerge;
  SmallVector<Value> serialCtrl(n);
  SmallVector<ControlMergeOp> serialMerge(n);
  SmallVector<unsigned> serialOperand(n);
  Value succCtrl;
  ControlMergeOp succMerge;
  unsigned succOperand = 0;
  SmallVector<OpOperand *> dataCrossings;

  for (auto &[bb, ops] : bbs.blocks) {
    Place dst = placeOf(bb, places);
    if (dst.kind == Place::OUTSIDE)
      continue;
    for (Operation *op : ops) {
      for (OpOperand &opd : op->getOpOperands()) {
        Value val = opd.get();
        Place src = placeOf(blockOf(val), places);
        // Memory interfaces and other block-less operations sit outside the
        // CFG; their ports are not control flow.
        if (src.kind == Place::NONE)
          continue;
        bool isCtrl = isa<handshake::ControlType>(val.getType());
        auto refuse = [&](const Twine &why) {
          return op->emitError() << "cannot run the regions of '"
                                 << REGIONS_ATTR << "' in parallel: " << why;
        };
        switch (dst.kind) {
        case Place::ENTRY:
          if (src.kind == Place::REGION)
            return refuse("a region feeds the entry block, the group sits "
                          "inside a loop");
          break;
        case Place::SUCCESSOR:
          if (src.kind != Place::REGION)
            break;
          // A result streamed straight into the end takes part in no control
          // flow (see checkFuncInvariants).
          if (isa<EndOp>(op))
            break;
          if (src.region + 1 != n)
            return refuse("region " + Twine(src.region) +
                          " feeds the successor block; only the last region "
                          "may");
          if (isCtrl) {
            if (!isa<ControlMergeOp>(op))
              return refuse("the last region's control reaches the successor "
                            "block outside its control merge");
            if (succCtrl)
              return refuse("the last region has two exits");
            succCtrl = val;
            succMerge = cast<ControlMergeOp>(op);
            succOperand = opd.getOperandNumber();
          }
          break;
        case Place::REGION: {
          unsigned i = dst.region;
          switch (src.kind) {
          case Place::REGION:
            if (src.region == i)
              break;
            if (src.region + 1 != i)
              return refuse("region " + Twine(src.region) + " feeds region " +
                            Twine(i) + ", which does not follow it");
            if (isCtrl) {
              if (!isa<ControlMergeOp>(op))
                return refuse("region " + Twine(src.region) +
                              "'s control reaches region " + Twine(i) +
                              " outside its control merge");
              if (serialCtrl[i])
                return refuse("region " + Twine(src.region) +
                              " has two exits");
              serialCtrl[i] = val;
              serialMerge[i] = cast<ControlMergeOp>(op);
              serialOperand[i] = opd.getOperandNumber();
            } else {
              dataCrossings.push_back(&opd);
            }
            break;
          case Place::ENTRY:
            if (i == 0 && isCtrl && isa<ControlMergeOp>(op)) {
              if (entryCtrl)
                return refuse("the entry block has two control edges into "
                              "the first region");
              entryCtrl = val;
              entryMerge = cast<ControlMergeOp>(op);
            }
            break;
          case Place::SUCCESSOR:
            return refuse("the successor block feeds region " + Twine(i) +
                          ", the group sits inside a loop");
          case Place::OUTSIDE:
            return refuse("a block outside the group feeds region " +
                          Twine(i));
          case Place::NONE:
            break;
          }
          break;
        }
        case Place::OUTSIDE:
        case Place::NONE:
          break;
        }
      }
    }
  }
  // Edges out of a region into a block outside the group.
  for (auto &[bb, ops] : bbs.blocks) {
    if (placeOf(bb, places).kind != Place::REGION)
      continue;
    for (Operation *op : ops) {
      for (Operation *user : op->getUsers()) {
        Place dst = placeOf(getLogicBB(user), places);
        if (dst.kind == Place::OUTSIDE)
          return op->emitError()
                 << "cannot run the regions of '" << REGIONS_ATTR
                 << "' in parallel: a value of region "
                 << placeOf(bb, places).region
                 << " is used outside the group";
      }
    }
  }

  if (!entryCtrl)
    return funcOp->emitError() << "no control edge from block " << group.entry
                               << " into the first region's control merge";
  for (unsigned i = 1; i < n; ++i) {
    if (!serialCtrl[i])
      return funcOp->emitError()
             << "no control edge from region " << i - 1 << " into region "
             << i << "'s control merge";
  }
  if (!succCtrl)
    return funcOp->emitError()
           << "no control edge from the last region into block "
           << group.successor << "'s control merge";

  // The exit token of a region is what the sequential shape handed to the
  // next region, or to the successor for the last one.
  SmallVector<Value> exitCtrl(n);
  for (unsigned i = 0; i + 1 < n; ++i)
    exitCtrl[i] = serialCtrl[i + 1];
  exitCtrl[n - 1] = succCtrl;

  // A memory dependence across two regions orders them; the analysis should
  // not have grouped them, but the attribute is data and may be wrong.
  NameAnalysis &names = getAnalysis<NameAnalysis>();
  auto regionOf = [&](Operation *op) -> std::optional<unsigned> {
    Place p = placeOf(getLogicBB(op), places);
    if (p.kind == Place::REGION)
      return p.region;
    return std::nullopt;
  };
  for (auto &[bb, ops] : bbs.blocks) {
    for (Operation *op : ops) {
      std::optional<unsigned> region = regionOf(op);
      if (!region)
        continue;
      auto deps = getDialectAttr<MemDependenceArrayAttr>(op);
      if (!deps)
        continue;
      for (MemDependenceAttr dep : deps.getDependencies()) {
        StringRef dstName = dep.getDstAccess();
        Operation *dstOp = names.getOp(dstName);
        if (!dstOp)
          return op->emitError() << "memory dependence names an unknown access '"
                                 << dstName << "'";
        std::optional<unsigned> dstRegion = regionOf(dstOp);
        if (dstRegion && *dstRegion != *region)
          return op->emitError()
                 << "cannot run the regions of '" << REGIONS_ATTR
                 << "' in parallel: a memory dependence with '" << dstName
                 << "' crosses from region " << *region
                 << " to region " << *dstRegion;
      }
    }
  }
  // An LSQ orders the accesses of its groups by arrival; two regions on one
  // queue would be interleaved in whatever order they happen to run.
  for (LSQOp lsq : funcOp.getOps<LSQOp>()) {
    std::optional<unsigned> seen;
    for (Value in : lsq.getInputs()) {
      Operation *def = in.getDefiningOp();
      if (!def)
        continue;
      std::optional<unsigned> region = regionOf(def);
      if (!region)
        continue;
      if (seen && *seen != *region)
        return lsq->emitError()
               << "cannot run the regions of '" << REGIONS_ATTR
               << "' in parallel: this LSQ serves both region " << *seen
               << " and region " << *region;
      seen = region;
    }
  }

  // Follow a value that leaves region `from` back to where it came in. Only
  // wires (branches, forks, buffers) and loop-carried muxes may lie on the
  // way; anything else computes the value inside the region, which makes it
  // a live-out the next region genuinely waits for.
  auto resolve = [&](Value val, unsigned from, Source &src) -> LogicalResult {
    Value cur = val;
    while (true) {
      Operation *def = cur.getDefiningOp();
      if (!def) {
        src.value = cur;
        return success();
      }
      Place p = placeOf(getLogicBB(def), places);
      if (p.kind == Place::ENTRY) {
        src.value = cur;
        return success();
      }
      if (p.kind != Place::REGION || p.region != from)
        return def->emitError()
               << "cannot run the regions of '" << REGIONS_ATTR
               << "' in parallel: a value region " << from + 1
               << " uses comes from neither the entry block nor region "
               << from;
      if (auto cst = dyn_cast<ConstantOp>(def)) {
        src.constant = cst;
        return success();
      }
      if (auto condBr = dyn_cast<ConditionalBranchOp>(def)) {
        cur = condBr.getDataOperand();
        continue;
      }
      if (auto br = dyn_cast<BranchOp>(def)) {
        cur = br.getOperand();
        continue;
      }
      if (auto fork = dyn_cast<ForkOp>(def)) {
        cur = fork.getOperand();
        continue;
      }
      if (auto buf = dyn_cast<BufferOp>(def)) {
        cur = buf.getOperand();
        continue;
      }
      if (isa<MuxOp, MergeOp>(def)) {
        Value init;
        for (Value data : cast<MergeLikeOpInterface>(def).getDataOperands()) {
          if (isBackedge(data, def))
            continue;
          if (init)
            return def->emitError()
                   << "cannot run the regions of '" << REGIONS_ATTR
                   << "' in parallel: this merge carries two distinct values "
                      "into region "
                   << from + 1;
          init = data;
        }
        if (!init)
          return def->emitError() << "merge has no loop entry operand";
        cur = init;
        continue;
      }
      return def->emitError()
             << "cannot run the regions of '" << REGIONS_ATTR
             << "' in parallel: region " << from
             << " computes this value and region " << from + 1
             << " uses it";
    }
  };

  // Rewire the data first (it may fail), then the control.
  OpBuilder builder(funcOp.getContext());
  Value start = funcOp.getArguments().back();
  llvm::DenseMap<Operation *, Value> entryConstants;
  SmallVector<Operation *> maybeDead;
  for (OpOperand *opd : dataCrossings) {
    unsigned from = placeOf(blockOf(opd->get()), places).region;
    Source src;
    if (failed(resolve(opd->get(), from, src)))
      return failure();
    maybeDead.push_back(opd->get().getDefiningOp());
    if (src.constant) {
      Value &clone = entryConstants[src.constant];
      if (!clone) {
        builder.setInsertionPointToStart(funcOp.getBodyBlock());
        auto cst = ConstantOp::create(builder, src.constant.getLoc(),
                                      src.constant.getValue(), start);
        setBB(cst, group.entry);
        clone = cst.getResult();
      }
      opd->set(clone);
    } else {
      opd->set(src.value);
    }
  }
  for (unsigned i = 1; i < n; ++i)
    serialMerge[i]->setOperand(serialOperand[i], entryCtrl);
  builder.setInsertionPoint(succMerge);
  auto join = JoinOp::create(builder, succMerge.getLoc(), succCtrl.getType(),
                             exitCtrl);
  setBB(join, group.successor);
  succMerge->setOperand(succOperand, join.getResult());

  // The wires that only existed to carry a value out of a region are now
  // dead: the exit branch, and behind it the muxes, forks and constants that
  // threaded the value through the loop. Erase what nothing uses any more,
  // back to the first operation that still has a consumer.
  // In materialized input a sink is the only consumer of such a wire; it
  // counts as no consumer and goes with the wire.
  while (!maybeDead.empty()) {
    Operation *op = maybeDead.pop_back_val();
    if (!op || !isa<ConditionalBranchOp, BranchOp, ForkOp, BufferOp, MuxOp,
                    MergeOp, ConstantOp>(op))
      continue;
    SmallVector<Operation *> sinks;
    bool dead = true;
    for (Operation *user : op->getUsers()) {
      if (isa<SinkOp>(user))
        sinks.push_back(user);
      else
        dead = false;
    }
    if (!dead)
      continue;
    for (Operation *sink : sinks)
      sink->erase();
    for (Value operand : op->getOperands())
      maybeDead.push_back(operand.getDefiningOp());
    op->erase();
  }

  if (!haveArchs)
    return success();

  // The serial edges between regions are gone; every region now starts from
  // the entry and ends in the successor, as often as the first and the last
  // did.
  auto headBB = [&](unsigned i) {
    return *getLogicBB(i == 0 ? entryMerge : serialMerge[i]);
  };
  auto exitBB = [&](unsigned i) {
    return *getLogicBB(exitCtrl[i].getDefiningOp());
  };
  auto find = [&](unsigned src, unsigned dst) -> ArchBB * {
    for (ArchBB &arch : archs)
      if (arch.srcBB == src && arch.dstBB == dst)
        return &arch;
    return nullptr;
  };
  ArchBB *entryArch = find(group.entry, headBB(0));
  ArchBB *exitArch = find(exitBB(n - 1), group.successor);
  unsigned entryTrans = entryArch ? entryArch->numTrans : 1;
  unsigned exitTrans = exitArch ? exitArch->numTrans : 1;
  for (unsigned i = 1; i < n; ++i) {
    unsigned src = exitBB(i - 1), dst = headBB(i);
    llvm::erase_if(archs, [&](const ArchBB &arch) {
      return arch.srcBB == src && arch.dstBB == dst;
    });
  }
  for (unsigned i = 1; i < n; ++i)
    archs.emplace_back(group.entry, headBB(i), entryTrans, false);
  for (unsigned i = 0; i + 1 < n; ++i)
    archs.emplace_back(exitBB(i), group.successor, exitTrans, false);
  return success();
}

void HandshakeParallelizeRegionsPass::runDynamaticPass() {
  for (handshake::FuncOp funcOp : getOperation().getOps<handshake::FuncOp>()) {
    SmallVector<RegionGroup> groups;
    if (failed(parseGroups(funcOp, groups)))
      return signalPassFailure();
    if (groups.empty())
      continue;

    SmallVector<ArchBB> archs;
    bool haveArchs = false;
    if (!frequencies.empty()) {
      std::string path = frequencies;
      if (failed(experimental::StdProfiler::readCSV(path, archs))) {
        funcOp->emitError() << "failed to read transition frequencies from '"
                            << frequencies << "'";
        return signalPassFailure();
      }
      haveArchs = true;
    } else if (buffer::hasFrequenciesAttr(funcOp)) {
      if (failed(buffer::readFrequenciesAttr(funcOp, archs)))
        return signalPassFailure();
      haveArchs = true;
    }

    for (const RegionGroup &group : groups)
      if (failed(parallelize(funcOp, group, archs, haveArchs)))
        return signalPassFailure();
    if (haveArchs)
      buffer::writeFrequenciesAttr(funcOp, archs);
  }
}
