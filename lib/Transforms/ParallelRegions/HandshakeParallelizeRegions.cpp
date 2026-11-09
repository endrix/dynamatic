//===- HandshakeParallelizeRegions.cpp - Run regions concurrently -*- C++
//-*-===//
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
// nothing in a region waits on another. A group it cannot rewire is declined
// with a warning and left sequential.
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
#include "llvm/ADT/SmallPtrSet.h"
#include "llvm/ADT/SmallVector.h"
#include <optional>
#include <string>

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
  /// The attribute's entry, kept when the group runs in parallel.
  Attribute attr;
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

/// Why a group's regions cannot run in parallel, and where it shows.
struct Refusal {
  Operation *at = nullptr;
  std::string why;
};

/// What became of a group: rewired, left sequential (with a warning), or an
/// attribute the pass cannot read (an error).
enum class Outcome { DONE, DECLINED, FAILED };

struct HandshakeParallelizeRegionsPass
    : public dynamatic::impl::HandshakeParallelizeRegionsBase<
          HandshakeParallelizeRegionsPass> {
  using HandshakeParallelizeRegionsBase::HandshakeParallelizeRegionsBase;

  void runDynamaticPass() override;

private:
  /// Rewires one group, the `index`th of the attribute, or declines it and
  /// leaves the circuit as it was. `archs` is rewritten in place when
  /// `haveArchs` and the group is rewired.
  Outcome parallelize(handshake::FuncOp funcOp, unsigned index,
                      const RegionGroup &group, SmallVectorImpl<ArchBB> &archs,
                      bool haveArchs);
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
    group.attr = dict;
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

/// One step back along a path that hands every token on unchanged, and when
/// it comes: a branch (either side of a conditional one), a fork or lazy
/// fork, a buffer, a one-input merge, a blocker of one input, or a channel
/// taken apart and put together again (`bundle(unbundle(x))`). Null where the
/// step is anything else. A value a region hands the next is rewired past
/// such steps only, and what only they took is erased after.
static Value passedOn(Operation *op) {
  if (auto condBr = dyn_cast<ConditionalBranchOp>(op))
    return condBr.getDataOperand();
  if (isa<BranchOp, ForkOp, LazyForkOp, BufferOp>(op))
    return op->getOperand(0);
  if (isa<MergeOp, BlockerOp>(op) && op->getNumOperands() == 1)
    return op->getOperand(0);
  if (auto bundle = dyn_cast<BundleOp>(op)) {
    if (bundle->getNumOperands() != 2 || bundle->getNumResults() != 1)
      return {};
    auto unbundle = bundle->getOperand(0).getDefiningOp<UnbundleOp>();
    if (!unbundle || unbundle->getNumOperands() != 1 ||
        unbundle->getNumResults() != 2 ||
        bundle->getOperand(0) != unbundle->getResult(0) ||
        bundle->getOperand(1) != unbundle->getResult(1) ||
        bundle->getResult(0).getType() != unbundle->getOperand(0).getType())
      return {};
    return unbundle->getOperand(0);
  }
  return {};
}

/// The same, and a blocker's forwarded (first) operand whatever else it waits
/// for: what a value is, not when it comes. A back edge through such a
/// blocker still hands its mux the mux's value; a later region that took the
/// value past it would no longer wait for the blocker's other inputs.
static Value sameValueAs(Operation *op) {
  if (isa<BlockerOp>(op))
    return op->getOperand(0);
  return passedOn(op);
}

namespace {

/// Where a source comes from, for comparing two: followed back through what
/// keeps a value (sameValueAs), the value it reaches and the conditional
/// branches on the way (condition, side), or the constant it reaches. Not
/// `known` on a ring of wires.
struct Root {
  Value value;
  handshake::ConstantOp constant;
  SmallVector<std::pair<Value, unsigned>> filters;
  bool known = true;
};

/// Follows a value that leaves a region back to where it came in: the entry
/// block, a block before the group, or a constant inside a region. Only
/// wires (passedOn) and loop-carried muxes that carry the value unchanged may
/// lie on the way; anything else computes the value inside the region, which
/// makes it a live-out the next region genuinely waits for, and `refusal`
/// says so. Every refusal declines the group, so the results it caches are
/// all successes.
class Resolver {
public:
  Resolver(const llvm::DenseMap<unsigned, Place> &places, unsigned entry)
      : places(places), entry(entry) {}

  /// Where the value region `from` hands region `from + 1` through `val`
  /// came in.
  FailureOr<Source> resolveCrossing(Value val, unsigned from) {
    user = from + 1;
    return resolve(val, from, /*filtered=*/false);
  }

  Refusal refusal;

private:
  const llvm::DenseMap<unsigned, Place> &places;
  unsigned entry;
  /// The region the crossing being resolved goes into, which the refusals
  /// name.
  unsigned user = 0;
  /// The muxes whose loop-entry operand is being followed: one met again is
  /// a cycle no loop entry breaks.
  SmallPtrSet<Operation *, 8> resolving;
  /// What `resolve` found, by (value, 2 * region + filtered).
  llvm::DenseMap<std::pair<Value, unsigned>, Source> resolved;
  /// The muxes found to carry their loop-entry value, and where it came in.
  llvm::DenseMap<Operation *, Source> carried;

  bool inRegion(Operation *op, unsigned at) const {
    Place p = placeOf(getLogicBB(op), places);
    return p.kind == Place::REGION && p.region == at;
  }

  /// A walk back through the wires of one region: where it stopped, and
  /// whether it stepped through a conditional branch, which chooses the
  /// tokens it hands on.
  struct Walk {
    Value val;
    bool filtered = false;
  };
  FailureOr<Walk> throughWires(Value val, unsigned at,
                               Value (*step)(Operation *));

  FailureOr<Source> resolve(Value val, unsigned at, bool filtered);
  FailureOr<Source> resolveUncached(Value val, unsigned at, bool filtered);
  LogicalResult carriesItself(Operation *mux, unsigned at, const Source &init);

  LogicalResult refuse(Operation *at, const Twine &why) {
    refusal = {at, why.str()};
    return failure();
  }
};

} // namespace

static Root rootOf(const Source &src) {
  Root root;
  if (src.constant) {
    root.constant = src.constant;
    return root;
  }
  Value val = src.value;
  SmallPtrSet<Operation *, 8> seen;
  while (Operation *def = val.getDefiningOp()) {
    Value prev = sameValueAs(def);
    if (!prev)
      break;
    if (!seen.insert(def).second) {
      root.known = false;
      return root;
    }
    if (auto condBr = dyn_cast<ConditionalBranchOp>(def))
      root.filters.push_back({condBr.getConditionOperand(),
                              cast<OpResult>(val).getResultNumber()});
    val = prev;
  }
  root.constant = val.getDefiningOp<handshake::ConstantOp>();
  root.value = val;
  return root;
}

/// Whether two sources are one value: they meet at one value through the
/// same branches taken the same way (the same tokens), or at two constants
/// of one value and type.
static bool sameRoot(Root a, Root b) {
  if (!a.known || !b.known)
    return false;
  if (a.constant || b.constant)
    return a.constant && b.constant &&
           a.constant.getValue() == b.constant.getValue() &&
           a.constant.getResult().getType() == b.constant.getResult().getType();
  return a.value == b.value && a.filters == b.filters;
}

FailureOr<Resolver::Walk> Resolver::throughWires(Value val, unsigned at,
                                                 Value (*step)(Operation *)) {
  Walk walk{val};
  SmallPtrSet<Operation *, 8> seen;
  while (Operation *def = walk.val.getDefiningOp()) {
    if (!inRegion(def, at))
      break;
    Value prev = step(def);
    if (!prev)
      break;
    if (!seen.insert(def).second)
      return refuse(def, "this value only goes round a ring of wires in "
                         "region " +
                             Twine(at) + ", and region " + Twine(user) +
                             " uses it");
    walk.filtered |= isa<ConditionalBranchOp>(def);
    walk.val = prev;
  }
  return walk;
}

FailureOr<Source> Resolver::resolve(Value val, unsigned at, bool filtered) {
  auto key = std::make_pair(val, 2 * at + (filtered ? 1 : 0));
  if (auto it = resolved.find(key); it != resolved.end())
    return it->second;
  FailureOr<Source> src = resolveUncached(val, at, filtered);
  if (succeeded(src))
    resolved[key] = *src;
  return src;
}

FailureOr<Source> Resolver::resolveUncached(Value val, unsigned at,
                                            bool filtered) {
  Value cur = val;
  while (true) {
    FailureOr<Walk> walk = throughWires(cur, at, passedOn);
    if (failed(walk))
      return failure();
    cur = walk->val;
    filtered |= walk->filtered;
    Operation *def = cur.getDefiningOp();
    if (!def)
      return Source{cur, {}};
    std::optional<unsigned> bb = getLogicBB(def);
    Place p = placeOf(bb, places);
    if (p.kind == Place::ENTRY)
      return Source{cur, {}};
    // A value from a block BEFORE the group is a value of the firing, like
    // one from the entry (the regions may read it directly; see the edges
    // parallelize admits), but only as the crossing had it: a branch or a mux
    // on the way chose which of its tokens went on.
    if (p.kind == Place::OUTSIDE && *bb < entry &&
        !isa<handshake::ControlType>(cur.getType())) {
      if (filtered)
        return refuse(def, "region " + Twine(user) +
                               " would take a value of a block before the "
                               "group past the branches and muxes of a "
                               "region that choose its tokens");
      return Source{cur, {}};
    }
    // Region `at` received it through the previous region's exit: where it
    // came into that one.
    if (p.kind == Place::REGION && p.region + 1 == at) {
      at = p.region;
      filtered = true;
      continue;
    }
    if (p.kind != Place::REGION || p.region != at)
      return refuse(def, "a value region " + Twine(user) +
                             " uses comes from neither the entry block nor "
                             "region " +
                             Twine(at));
    if (auto cst = dyn_cast<ConstantOp>(def))
      return Source{{}, cst};
    if (isa<BlockerOp>(def))
      return refuse(def, "region " + Twine(user) +
                             " would take this value past a blocker of "
                             "region " +
                             Twine(at) +
                             ", which also waits for its other "
                             "inputs");
    if (isa<MuxOp, MergeOp>(def)) {
      if (auto it = carried.find(def); it != carried.end())
        return it->second;
      Value init;
      for (Value data : cast<MergeLikeOpInterface>(def).getDataOperands()) {
        if (isBackedge(data, def))
          continue;
        if (init)
          return refuse(def, "this merge carries two distinct values into "
                             "region " +
                                 Twine(user));
        init = data;
      }
      if (!init)
        return refuse(def, "this merge has no loop entry operand");
      if (!resolving.insert(def).second)
        return refuse(def, "this merge's loop entry leads back to it");
      FailureOr<Source> src = resolve(init, at, /*filtered=*/true);
      if (succeeded(src) && failed(carriesItself(def, at, *src)))
        src = failure();
      resolving.erase(def);
      if (succeeded(src))
        carried[def] = *src;
      return src;
    }
    return refuse(def, "region " + Twine(at) +
                           " computes this value and region " + Twine(user) +
                           " uses it");
  }
}

/// Whether the back edges of `mux`, of region `at`, hand it the value its
/// loop-entry operand brings (`init`, where that came in). Followed back
/// through what keeps a value (sameValueAs), each must lead to the mux, or
/// to another mux or merge of the region (an inner loop's, a join block's)
/// that carries the value in turn: every operand of that one must lead back
/// the same way, or bring that same value in (the same entry value through a
/// ring of its own, a copy of the same constant). Then whatever leaves
/// through the mux is that value. A back edge that leads anywhere else
/// brings a value the loop made, and what leaves is the last of those.
LogicalResult Resolver::carriesItself(Operation *mux, unsigned at,
                                      const Source &init) {
  std::optional<Root> initRoot;
  SmallPtrSet<Operation *, 8> carriers = {mux};
  SmallVector<Value> pending;
  for (Value data : cast<MergeLikeOpInterface>(mux).getDataOperands())
    if (isBackedge(data, mux))
      pending.push_back(data);
  while (!pending.empty()) {
    FailureOr<Walk> walk =
        throughWires(pending.pop_back_val(), at, sameValueAs);
    if (failed(walk))
      return failure();
    Operation *src = walk->val.getDefiningOp();
    if (src && carriers.contains(src))
      continue;
    if (src && isa<MuxOp, MergeOp>(src) && inRegion(src, at)) {
      carriers.insert(src);
      llvm::append_range(pending,
                         cast<MergeLikeOpInterface>(src).getDataOperands());
      continue;
    }
    FailureOr<Source> other = resolve(walk->val, at, /*filtered=*/true);
    if (succeeded(other)) {
      if (!initRoot)
        initRoot = rootOf(init);
      if (sameRoot(rootOf(*other), *initRoot))
        continue;
    }
    return refuse(mux, "region " + Twine(at) +
                           "'s loop updates this value and region " +
                           Twine(user) + " uses it");
  }
  return success();
}

Outcome HandshakeParallelizeRegionsPass::parallelize(
    handshake::FuncOp funcOp, unsigned index, const RegionGroup &group,
    SmallVectorImpl<ArchBB> &archs, bool haveArchs) {
  unsigned n = group.regions.size();

  // A group this pass cannot rewire runs as the sequential lowering built it:
  // a warning on the function says why (and a note where), and nothing has
  // been changed yet when one fires.
  auto decline = [&](Operation *at, const Twine &why) {
    InFlightDiagnostic diag = funcOp->emitWarning()
                              << "the regions of group " << index << " of '"
                              << REGIONS_ATTR
                              << "' run one after the other: " << why;
    if (at && at != funcOp.getOperation())
      diag.attachNote(at->getLoc()) << "here";
    return Outcome::DECLINED;
  };

  // Place every block of the group; a block named twice is a malformed group.
  llvm::DenseMap<unsigned, Place> places;
  auto place = [&](unsigned bb, Place p) -> LogicalResult {
    if (!places.insert({bb, p}).second)
      return funcOp->emitError() << "block " << bb << " appears twice in a '"
                                 << REGIONS_ATTR << "' group";
    return success();
  };
  if (failed(place(group.entry, {Place::ENTRY, 0})))
    return Outcome::FAILED;
  for (auto [i, blocks] : llvm::enumerate(group.regions))
    for (unsigned bb : blocks)
      if (failed(place(bb, {Place::REGION, (unsigned)i})))
        return Outcome::FAILED;
  if (failed(place(group.successor, {Place::SUCCESSOR, 0})))
    return Outcome::FAILED;

  LogicBBs bbs = getLogicBBs(funcOp);
  for (auto &[bb, p] : places) {
    if (!bbs.blocks.contains(bb)) {
      funcOp->emitError() << "block " << bb << " named in '" << REGIONS_ATTR
                          << "' has no operation";
      return Outcome::FAILED;
    }
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
        auto refuse = [&](const Twine &why) { return decline(op, why); };
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
                return refuse("region " + Twine(src.region) + " has two exits");
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
            // A value from a block BEFORE the group is a value of the firing,
            // like one from the entry: computed once, forked to whichever
            // regions read it (the parser's actions copy a block into two
            // arrays in one loop, then push each array in its own). Control
            // from outside, and anything from a block after the group, is a
            // shape this pass does not know.
            if (!isCtrl && blockOf(val) && *blockOf(val) < group.entry)
              break;
            return refuse("a block outside the group feeds region " + Twine(i));
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
          return decline(op, "a value of region " +
                                 Twine(placeOf(bb, places).region) +
                                 " is used outside the group");
      }
    }
  }

  if (!entryCtrl)
    return decline(nullptr, "no control edge from block " + Twine(group.entry) +
                                " into the first region's control merge");
  for (unsigned i = 1; i < n; ++i) {
    if (!serialCtrl[i])
      return decline(nullptr, "no control edge from region " + Twine(i - 1) +
                                  " into region " + Twine(i) +
                                  "'s control merge");
  }
  if (!succCtrl)
    return decline(nullptr, "no control edge from the last region into block " +
                                Twine(group.successor) + "'s control merge");

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
        if (!dstOp) {
          op->emitError() << "memory dependence names an unknown access '"
                          << dstName << "'";
          return Outcome::FAILED;
        }
        std::optional<unsigned> dstRegion = regionOf(dstOp);
        if (dstRegion && *dstRegion != *region)
          return decline(op, "a memory dependence with '" + dstName +
                                 "' crosses from region " + Twine(*region) +
                                 " to region " + Twine(*dstRegion));
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
        return decline(lsq, "this LSQ serves both region " + Twine(*seen) +
                                " and region " + Twine(*region));
      seen = region;
    }
  }

  // Where every value a region hands the next came in, before anything is
  // changed: a refusal leaves the circuit as it was.
  Resolver resolver(places, group.entry);
  SmallVector<std::pair<OpOperand *, Source>> resolved;
  for (OpOperand *opd : dataCrossings) {
    unsigned from = placeOf(blockOf(opd->get()), places).region;
    FailureOr<Source> src = resolver.resolveCrossing(opd->get(), from);
    if (failed(src))
      return decline(resolver.refusal.at, resolver.refusal.why);
    resolved.push_back({opd, *src});
  }

  // Rewire the data, then the control.
  OpBuilder builder(funcOp.getContext());
  Value start = funcOp.getArguments().back();
  llvm::DenseMap<Operation *, Value> entryConstants;
  SmallVector<Operation *> maybeDead;
  for (auto &[opd, src] : resolved) {
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
  auto join =
      JoinOp::create(builder, succMerge.getLoc(), succCtrl.getType(), exitCtrl);
  setBB(join, group.successor);
  succMerge->setOperand(succOperand, join.getResult());

  // The wires that only existed to carry a value out of a region are now
  // dead: the exit branch, and behind it the muxes, forks and constants that
  // threaded the value through the loop. Erase what nothing uses any more,
  // back to the first operation that still has a consumer: what the values
  // were rewired past (the wires passedOn steps through, and the unbundle a
  // channel put together again came from), muxes, merges and constants.
  // In materialized input a sink is the only consumer of such a wire; it
  // counts as no consumer and goes with the wire. One operation may be
  // reached twice (two crossings from one fork's results, two operands of an
  // erased one from one producer); the second time it is gone.
  SmallPtrSet<Operation *, 16> erased;
  while (!maybeDead.empty()) {
    Operation *op = maybeDead.pop_back_val();
    if (!op || erased.contains(op))
      continue;
    if (!passedOn(op) && !isa<UnbundleOp, MuxOp, MergeOp, ConstantOp>(op))
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
    erased.insert(op);
    op->erase();
  }

  if (!haveArchs)
    return Outcome::DONE;

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
  return Outcome::DONE;
}

void HandshakeParallelizeRegionsPass::runDynamaticPass() {
  // Functions may sit inside another operation (a streamblocks actor holds
  // its actions' functions), so walk rather than list the module's own.
  SmallVector<handshake::FuncOp> funcOps;
  getOperation().walk(
      [&](handshake::FuncOp funcOp) { funcOps.push_back(funcOp); });
  for (handshake::FuncOp funcOp : funcOps) {
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

    // A declined group leaves the attribute: nothing after this pass may take
    // its regions for parallel ones.
    SmallVector<Attribute> kept;
    for (auto [i, group] : llvm::enumerate(groups)) {
      switch (parallelize(funcOp, i, group, archs, haveArchs)) {
      case Outcome::DONE:
        kept.push_back(group.attr);
        break;
      case Outcome::DECLINED:
        break;
      case Outcome::FAILED:
        return signalPassFailure();
      }
    }
    if (kept.empty())
      funcOp->removeAttr(REGIONS_ATTR);
    else if (kept.size() != groups.size())
      funcOp->setAttr(REGIONS_ATTR, ArrayAttr::get(&getContext(), kept));
    if (haveArchs)
      buffer::writeFrequenciesAttr(funcOp, archs);
  }
}
