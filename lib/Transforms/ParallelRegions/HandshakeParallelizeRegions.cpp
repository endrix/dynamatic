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
#include "llvm/ADT/DenseSet.h"
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

/// What became of a group: rewired, or left sequential (with a warning).
enum class Outcome { DONE, DECLINED };

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
/// it comes: a branch (either side of a conditional one), a fork, a lazy fork
/// of one output, a buffer, a one-input merge, a blocker of one input, or a
/// channel taken apart and put together again (`bundle(unbundle(x))`). Null
/// where the step is anything else. A value a region hands the next is
/// rewired past such steps only, and what only they took is erased after.
static Value passedOn(Operation *op) {
  if (auto condBr = dyn_cast<ConditionalBranchOp>(op))
    return condBr.getDataOperand();
  if (isa<BranchOp, ForkOp, BufferOp>(op))
    return op->getOperand(0);
  if (isa<LazyForkOp>(op) && op->getNumResults() == 1)
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
/// for, and a lazy fork's input whichever outputs it waits for: what a value
/// is, not when it comes. A back edge through such a unit still hands its mux
/// the mux's value; a later region that took the value past it would no
/// longer wait with it.
static Value sameValueAs(Operation *op) {
  if (isa<BlockerOp, LazyForkOp>(op))
    return op->getOperand(0);
  return passedOn(op);
}

/// Whether a data value comes from a block before the group's entry: a value
/// of the firing, like one of the entry block, which a region may read
/// directly.
static bool beforeTheGroup(Value val, unsigned entry,
                           const llvm::DenseMap<unsigned, Place> &places) {
  std::optional<unsigned> bb = blockOf(val);
  return bb && placeOf(bb, places).kind == Place::OUTSIDE && *bb < entry &&
         !isa<handshake::ControlType>(val.getType());
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

/// A conditional branch a walk stepped through, and the side (result) it
/// came by.
using Branch = std::pair<Operation *, unsigned>;

/// Where a value a region hands the next came in, and what lay on the way.
struct Resolution {
  Source src;
  enum Kind { ENTRY, BEFORE, CONSTANT } kind = ENTRY;
  /// The conditional branches on the way that no loop on the way accounts
  /// for (see `forgiven`): each chose which of the source's tokens went on.
  SmallVector<Branch> unforgiven;
  /// The branches of the loops whose carrier muxes lie on the way: those
  /// their back edges come round by.
  SmallVector<Branch> loopBranches;
  /// Whether a branch, a mux's loop entry or a region's exit lies on the way.
  bool chose = false;
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
  Resolver(const llvm::DenseMap<unsigned, Place> &places, const LogicBBs &bbs,
           unsigned entry)
      : places(places), bbs(bbs), entry(entry) {}

  /// Where the value region `from` hands region `from + 1` through `val`
  /// came in, if it can be taken from there: only as the crossing had it,
  /// with no branch on the way that chose its tokens.
  FailureOr<Source> resolveCrossing(Value val, unsigned from);

  Refusal refusal;

private:
  const llvm::DenseMap<unsigned, Place> &places;
  const LogicBBs &bbs;
  unsigned entry;
  /// The region the crossing being resolved goes into, which the refusals
  /// name.
  unsigned user = 0;
  /// The muxes whose loop-entry operand is being followed: one met again is
  /// a cycle no loop entry breaks.
  SmallPtrSet<Operation *, 8> resolving;
  /// What `resolve` found, by (value, region).
  llvm::DenseMap<std::pair<Value, unsigned>, Resolution> resolved;
  /// A mux found to carry its loop-entry value: where that came in, and the
  /// branches its back edges come round by.
  struct Carried {
    Resolution init;
    SmallVector<Branch> loop;
  };
  llvm::DenseMap<Operation *, Carried> carried;
  /// The branches the loops of a region take their control round by, by
  /// region.
  llvm::DenseMap<unsigned, SmallVector<Branch>> controlLoops;

  bool inRegion(Operation *op, unsigned at) const {
    Place p = placeOf(getLogicBB(op), places);
    return p.kind == Place::REGION && p.region == at;
  }

  /// A walk back through the wires of one region: where it stopped, and the
  /// conditional branches it stepped through.
  struct Walk {
    Value val;
    SmallVector<Branch> branches;
  };
  FailureOr<Walk> throughWires(Value val, unsigned at,
                               Value (*step)(Operation *));

  FailureOr<Resolution> resolve(Value val, unsigned at);
  FailureOr<Resolution> resolveUncached(Value val, unsigned at);
  FailureOr<Carried> carry(Operation *mux, unsigned at);
  FailureOr<SmallVector<Branch>> carriesItself(Operation *mux, unsigned at,
                                               const Source &init);
  ArrayRef<Branch> controlLoopsOf(unsigned at);

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

/// The condition a conditional branch decides on, back through the wires that
/// copy it to every branch of a block.
static Value conditionOf(Operation *condBr) {
  Value cond = cast<ConditionalBranchOp>(condBr).getConditionOperand();
  SmallPtrSet<Operation *, 4> seen;
  while (Operation *def = cond.getDefiningOp()) {
    if (!isa<ForkOp, LazyForkOp, BufferOp, BranchOp>(def) ||
        !seen.insert(def).second)
      break;
    cond = def->getOperand(0);
  }
  return cond;
}

/// Whether the loops whose branches are `loops` account for `branch`: it is
/// one of theirs (a side their back edges come round by, which hands on a
/// loop's copies of one value), or it splits the same decision of the same
/// block as one of theirs, on the other side: the loop's exit, which hands on
/// the token of the pass that leaves. Any other branch chooses which tokens
/// go on.
static bool forgiven(Branch branch, ArrayRef<Branch> loops) {
  for (Branch loop : loops) {
    if (loop == branch)
      return true;
    if (loop.second != branch.second &&
        getLogicBB(loop.first) == getLogicBB(branch.first) &&
        conditionOf(loop.first) == conditionOf(branch.first))
      return true;
  }
  return false;
}

static void forgive(SmallVectorImpl<Branch> &branches, ArrayRef<Branch> loops) {
  llvm::erase_if(branches, [&](Branch b) { return forgiven(b, loops); });
}

FailureOr<Resolver::Walk> Resolver::throughWires(Value val, unsigned at,
                                                 Value (*step)(Operation *)) {
  Walk walk{val, {}};
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
    if (isa<ConditionalBranchOp>(def))
      walk.branches.push_back(
          {def, cast<OpResult>(walk.val).getResultNumber()});
    walk.val = prev;
  }
  return walk;
}

FailureOr<Source> Resolver::resolveCrossing(Value val, unsigned from) {
  user = from + 1;
  FailureOr<Resolution> res = resolve(val, from);
  if (failed(res))
    return failure();
  switch (res->kind) {
  case Resolution::ENTRY:
    if (!res->unforgiven.empty())
      return refuse(res->unforgiven.front().first,
                    "region " + Twine(user) +
                        " would take a value of the entry block past a branch "
                        "of a region that chooses its tokens");
    break;
  case Resolution::CONSTANT:
    if (!res->unforgiven.empty())
      return refuse(res->unforgiven.front().first,
                    "region " + Twine(user) +
                        " would take a constant of a region past a branch "
                        "that chooses its tokens");
    break;
  case Resolution::BEFORE:
    if (res->chose)
      return refuse(res->src.value.getDefiningOp(),
                    "region " + Twine(user) +
                        " would take a value of a block before the group past "
                        "the branches and muxes of a region that choose its "
                        "tokens");
    break;
  }
  return res->src;
}

FailureOr<Resolution> Resolver::resolve(Value val, unsigned at) {
  auto key = std::make_pair(val, at);
  if (auto it = resolved.find(key); it != resolved.end())
    return it->second;
  FailureOr<Resolution> res = resolveUncached(val, at);
  if (succeeded(res))
    resolved[key] = *res;
  return res;
}

FailureOr<Resolution> Resolver::resolveUncached(Value val, unsigned at) {
  Resolution res;
  Value cur = val;
  while (true) {
    FailureOr<Walk> walk = throughWires(cur, at, passedOn);
    if (failed(walk))
      return failure();
    cur = walk->val;
    res.chose |= !walk->branches.empty();
    llvm::append_range(res.unforgiven, walk->branches);
    // A function argument belongs to block 0, the entry or a block before it.
    Operation *def = cur.getDefiningOp();
    Place p = placeOf(blockOf(cur), places);
    // A value of the entry block comes once per firing of the group.
    if (p.kind == Place::ENTRY) {
      res.src = {cur, {}};
      res.kind = Resolution::ENTRY;
      return res;
    }
    // A value from a block BEFORE the group is a value of the firing, like
    // one from the entry (the regions may read it directly; see the edges
    // parallelize admits).
    if (beforeTheGroup(cur, entry, places)) {
      res.src = {cur, {}};
      res.kind = Resolution::BEFORE;
      return res;
    }
    // Region `at` received it through the previous region's exit: where it
    // came into that one.
    if (p.kind == Place::REGION && p.region + 1 == at) {
      at = p.region;
      res.chose = true;
      continue;
    }
    if (!def || p.kind != Place::REGION || p.region != at)
      return refuse(def, "a value region " + Twine(user) +
                             " uses comes from neither the entry block nor "
                             "region " +
                             Twine(at));
    // A constant fires on its block's control, once per pass through the
    // block: a loop's exit branch hands on the pass that leaves, as the
    // loop's control branches tell.
    if (auto cst = dyn_cast<ConstantOp>(def)) {
      forgive(res.unforgiven, controlLoopsOf(at));
      res.src = {{}, cst};
      res.kind = Resolution::CONSTANT;
      return res;
    }
    if (isa<BlockerOp>(def))
      return refuse(def, "region " + Twine(user) +
                             " would take this value past a blocker of "
                             "region " +
                             Twine(at) +
                             ", which also waits for its other "
                             "inputs");
    if (isa<LazyForkOp>(def))
      return refuse(def, "region " + Twine(user) +
                             " would take this value past a lazy fork of "
                             "region " +
                             Twine(at) + ", which waits for all its outputs");
    // A mux that carries its value: the branches of its loop (and of the
    // loops behind its loop entry) account for those on the way to it, and
    // the value came in where its loop-entry operand did.
    if (isa<MuxOp, MergeOp>(def)) {
      FailureOr<Carried> c = carry(def, at);
      if (failed(c))
        return failure();
      SmallVector<Branch> loops(c->loop);
      llvm::append_range(loops, c->init.loopBranches);
      forgive(res.unforgiven, loops);
      Resolution out = c->init;
      llvm::append_range(res.unforgiven, c->init.unforgiven);
      out.unforgiven = std::move(res.unforgiven);
      out.loopBranches = std::move(loops);
      out.chose = true;
      return out;
    }
    return refuse(def, "region " + Twine(at) +
                           " computes this value and region " + Twine(user) +
                           " uses it");
  }
}

FailureOr<Resolver::Carried> Resolver::carry(Operation *mux, unsigned at) {
  if (auto it = carried.find(mux); it != carried.end())
    return it->second;
  Value init;
  for (Value data : cast<MergeLikeOpInterface>(mux).getDataOperands()) {
    if (isBackedge(data, mux))
      continue;
    if (init)
      return refuse(mux, "this merge carries two distinct values into "
                         "region " +
                             Twine(user));
    init = data;
  }
  if (!init)
    return refuse(mux, "this merge has no loop entry operand");
  if (!resolving.insert(mux).second)
    return refuse(mux, "this merge's loop entry leads back to it");
  FailureOr<Resolution> from = resolve(init, at);
  FailureOr<SmallVector<Branch>> loop =
      succeeded(from) ? carriesItself(mux, at, from->src)
                      : FailureOr<SmallVector<Branch>>(failure());
  resolving.erase(mux);
  if (failed(loop))
    return failure();
  Carried c{*from, *loop};
  carried[mux] = c;
  return c;
}

/// Whether the back edges of `mux`, of region `at`, hand it the value its
/// loop-entry operand brings (`init`, where that came in), and if so the
/// branches they come round by. Followed back through what keeps a value
/// (sameValueAs), each must lead to the mux, or to another mux or merge of
/// the region (an inner loop's, a join block's) that carries the value in
/// turn: every operand of that one must lead back the same way, or bring that
/// same value in (the same entry value through a ring of its own, a copy of
/// the same constant). Then whatever leaves through the mux is that value. A
/// back edge that leads anywhere else brings a value the loop made, and what
/// leaves is the last of those.
FailureOr<SmallVector<Branch>>
Resolver::carriesItself(Operation *mux, unsigned at, const Source &init) {
  std::optional<Root> initRoot;
  SmallVector<Branch> loop;
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
    llvm::append_range(loop, walk->branches);
    Operation *src = walk->val.getDefiningOp();
    if (src && carriers.contains(src))
      continue;
    if (src && isa<MuxOp, MergeOp>(src) && inRegion(src, at)) {
      carriers.insert(src);
      llvm::append_range(pending,
                         cast<MergeLikeOpInterface>(src).getDataOperands());
      continue;
    }
    // Anything else brings a value in: where it cannot be told, that reason
    // stands; where it can, it must be the loop-entry operand's. (Only which
    // value: the branches on the way take the loop's own tokens.)
    FailureOr<Resolution> other = resolve(walk->val, at);
    if (failed(other))
      return failure();
    if (!initRoot)
      initRoot = rootOf(init);
    if (sameRoot(rootOf(other->src), *initRoot))
      continue;
    return refuse(mux, "region " + Twine(at) +
                           "'s loop updates this value and region " +
                           Twine(user) + " uses it");
  }
  return loop;
}

/// The branches the loops of region `at` take their control round by:
/// followed back from every back edge of a control merge of the region,
/// through what copies a control token (a one-input control merge among
/// them) and through the region's other control merges and joins (an inner
/// loop's header, every input of which leads back the same way), the
/// conditional branches on the way, with the side they are taken by.
ArrayRef<Branch> Resolver::controlLoopsOf(unsigned at) {
  if (auto it = controlLoops.find(at); it != controlLoops.end())
    return it->second;
  SmallVector<Branch> loops;
  for (auto &[bb, ops] : bbs.blocks) {
    Place p = placeOf(bb, places);
    if (p.kind != Place::REGION || p.region != at)
      continue;
    for (Operation *op : ops) {
      auto header = dyn_cast<ControlMergeOp>(op);
      if (!header)
        continue;
      SmallPtrSet<Operation *, 16> seen = {header};
      SmallVector<Value> pending;
      for (Value data : header.getDataOperands())
        if (isBackedge(data, header))
          pending.push_back(data);
      while (!pending.empty()) {
        Value val = pending.pop_back_val();
        while (Operation *def = val.getDefiningOp()) {
          if (!inRegion(def, at))
            break;
          if (auto condBr = dyn_cast<ConditionalBranchOp>(def))
            loops.push_back({def, cast<OpResult>(val).getResultNumber()});
          if (!seen.insert(def).second)
            break;
          if (auto condBr = dyn_cast<ConditionalBranchOp>(def)) {
            val = condBr.getDataOperand();
            continue;
          }
          if (auto merge = dyn_cast<ControlMergeOp>(def)) {
            if (merge.getDataOperands().size() == 1) {
              val = merge.getDataOperands().front();
              continue;
            }
            llvm::append_range(pending, merge.getDataOperands());
            break;
          }
          // A join hands the control on once every input came (the header's
          // control and an entry's arrival, say): the control came round by
          // each.
          if (isa<JoinOp>(def)) {
            llvm::append_range(pending, def->getOperands());
            break;
          }
          if (isa<BranchOp, ForkOp, LazyForkOp, BufferOp>(def) ||
              (isa<MergeOp>(def) && def->getNumOperands() == 1)) {
            val = def->getOperand(0);
            continue;
          }
          break;
        }
      }
    }
  }
  return controlLoops[at] = std::move(loops);
}

/// The blocks a group names, in the order the attribute names them: the
/// entry, the regions' blocks, the successor.
static SmallVector<unsigned> blocksOf(const RegionGroup &group) {
  SmallVector<unsigned> blocks = {group.entry};
  for (const SmallVector<unsigned> &region : group.regions)
    llvm::append_range(blocks, region);
  blocks.push_back(group.successor);
  return blocks;
}

/// Whether the function's groups fit it: every block a group names, named
/// once in that group, holds an operation, and every memory dependence of an
/// access in a region names an access. Checked for all of them before any is
/// rewired, so that an error never finds the function half rewired; the
/// first offender in the attribute's order is the one named.
static LogicalResult checkGroups(handshake::FuncOp funcOp,
                                 ArrayRef<RegionGroup> groups,
                                 NameAnalysis &names) {
  LogicBBs bbs = getLogicBBs(funcOp);
  for (const RegionGroup &group : groups) {
    llvm::SmallDenseSet<unsigned, 16> seen;
    for (unsigned bb : blocksOf(group)) {
      if (!seen.insert(bb).second)
        return funcOp->emitError() << "block " << bb << " appears twice in a '"
                                   << REGIONS_ATTR << "' group";
      if (!bbs.blocks.contains(bb))
        return funcOp->emitError() << "block " << bb << " named in '"
                                   << REGIONS_ATTR << "' has no operation";
    }
  }
  for (const RegionGroup &group : groups) {
    for (const SmallVector<unsigned> &region : group.regions) {
      for (unsigned bb : region) {
        for (Operation *op : bbs.blocks.lookup(bb)) {
          auto deps = getDialectAttr<MemDependenceArrayAttr>(op);
          if (!deps)
            continue;
          for (MemDependenceAttr dep : deps.getDependencies())
            if (!names.getOp(dep.getDstAccess()))
              return op->emitError()
                     << "memory dependence names an unknown access '"
                     << dep.getDstAccess() << "'";
        }
      }
    }
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

  // Place every block of the group (checkGroups made sure that each is
  // named once and holds an operation, before any group was rewired; one an
  // earlier group's rewiring emptied is declined).
  llvm::DenseMap<unsigned, Place> places;
  places.insert({group.entry, {Place::ENTRY, 0}});
  for (auto [i, blocks] : llvm::enumerate(group.regions))
    for (unsigned bb : blocks)
      places.insert({bb, {Place::REGION, (unsigned)i}});
  places.insert({group.successor, {Place::SUCCESSOR, 0}});

  LogicBBs bbs = getLogicBBs(funcOp);
  for (unsigned bb : blocksOf(group))
    if (!bbs.blocks.contains(bb))
      return decline(nullptr, "block " + Twine(bb) + " has no operation");

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
            if (beforeTheGroup(val, group.entry, places))
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
        // checkGroups found every access a dependence of a region names, and
        // rewiring a group erases no access.
        assert(dstOp && "a dependence names an unknown access");
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
  Resolver resolver(places, bbs, group.entry);
  SmallVector<std::pair<OpOperand *, Source>> resolved;
  for (OpOperand *opd : dataCrossings) {
    unsigned from = placeOf(blockOf(opd->get()), places).region;
    FailureOr<Source> src = resolver.resolveCrossing(opd->get(), from);
    if (failed(src))
      return decline(resolver.refusal.at, resolver.refusal.why);
    resolved.push_back({opd, *src});
  }

  // Rewire the data, then the control. A constant re-made in the entry fires
  // on the entry's control into the first region, once per firing of the
  // group (the function's start comes once per call, and the group may sit
  // in an outer loop).
  OpBuilder builder(funcOp.getContext());
  llvm::DenseMap<Operation *, Value> entryConstants;
  SmallVector<Operation *> maybeDead;
  for (auto &[opd, src] : resolved) {
    maybeDead.push_back(opd->get().getDefiningOp());
    if (src.constant) {
      Value &clone = entryConstants[src.constant];
      if (!clone) {
        if (Operation *def = entryCtrl.getDefiningOp())
          builder.setInsertionPointAfter(def);
        else
          builder.setInsertionPointToStart(funcOp.getBodyBlock());
        auto cst = ConstantOp::create(builder, src.constant.getLoc(),
                                      src.constant.getValue(), entryCtrl);
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

    // An attribute that does not fit the function fails the pass before any
    // group is rewired.
    if (failed(checkGroups(funcOp, groups, getAnalysis<NameAnalysis>())))
      return signalPassFailure();

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
