//===- CfDetectParallelRegions.cpp - Find regions that may run at once ----===//
//
// Dynamatic is under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// Implements the --cf-detect-parallel-regions pass.
//
// At the cf level a function's top level is, in the common case, a chain: a
// loop nest, a block or two of straight-line code, another nest, and so on
// to the return. Every element of that chain is done before the next one
// starts, whether or not the next one needs anything from it. This pass
// walks the chain, records what each element touches, merges the elements
// that must stay in order into one region, and records the resulting runs of
// regions -- independent of one another by construction -- in the function's
// `handshake.parallel_regions` attribute, in the block ids the lowering will
// assign (position in the function), for --handshake-parallelize-regions to
// act on after the lowering.
//
//===----------------------------------------------------------------------===//

#include "dynamatic/Analysis/NameAnalysis.h"
#include "dynamatic/Dialect/Handshake/HandshakeAttributes.h"
#include "dynamatic/Support/Attribute.h"
#include "dynamatic/Support/LLVM.h"
#include "mlir/Analysis/CFGLoopInfo.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/Dominance.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallPtrSet.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/Support/Debug.h"

#define DEBUG_TYPE "cf-detect-parallel-regions"

using namespace mlir;
using namespace dynamatic;
using namespace dynamatic::handshake;

#include "dynamatic/Transforms/Passes.h" // IWYU pragma: keep
namespace dynamatic {
#define GEN_PASS_DEF_CFDETECTPARALLELREGIONS
#include "dynamatic/Transforms/Passes.h.inc"
} // namespace dynamatic

static constexpr llvm::StringLiteral REGIONS_ATTR("handshake.parallel_regions");

namespace {

/// An access inside a segment: a memref load or store, or any other effect an
/// operation declares on a value (a read or write of a port, say), with the
/// resource it is on. Effects on the default resource are memory.
struct Access {
  Operation *op;
  Value memref;
  bool isStore;
  SideEffects::Resource *resource;
};

/// One element of a chain: a loop nest with the shape a region needs (one
/// block enters it, one block leaves it, to one place), or a straight-line
/// block between two of them.
struct Segment {
  /// The loop, or null for a straight-line block.
  CFGLoop *loop = nullptr;
  /// The blocks, in program order.
  SmallVector<Block *> blocks;
  /// Where the chain continues after this segment.
  Block *next = nullptr;
  SmallVector<Access> accesses;
  /// True when the segment holds an operation with an effect it does not tie
  /// to a value (a call, say); nothing runs beside it.
  bool opaque = false;

  bool contains(Block *block) const {
    return llvm::is_contained(blocks, block);
  }
  /// The block the segment leaves from.
  Block *last() const { return loop ? loop->getExitingBlock() : blocks.back(); }
};

using BlockIndex = llvm::DenseMap<Block *, unsigned>;

struct CfDetectParallelRegionsPass
    : public dynamatic::impl::CfDetectParallelRegionsBase<
          CfDetectParallelRegionsPass> {
  using CfDetectParallelRegionsBase::CfDetectParallelRegionsBase;

  void runDynamaticPass() override;

private:
  void analyzeFunction(func::FuncOp funcOp);
};

} // namespace

/// Whether the value is a block argument of, or produced inside, the segment.
static bool definedIn(Value val, const Segment &seg) {
  if (auto arg = dyn_cast<BlockArgument>(val))
    return seg.contains(arg.getOwner());
  return seg.contains(val.getDefiningOp()->getBlock());
}

/// Whether a value that leaves `seg` costs the next region nothing: a
/// constant, which the lowering re-makes wherever it is needed, or a block
/// argument the segment only carries around unchanged from ONE origin that is
/// itself free (a value from before the segment, or a constant). A block
/// argument two different values reach -- a loop-carried value the loop
/// updates, a flag it resets to a constant -- holds whichever the control
/// flow inside the segment chose last, so the segment computes it: anything
/// computed inside the segment is a live-out.
static bool isFreeToLeave(Value val, const Segment &seg) {
  Value origin;
  SmallVector<Value> worklist = {val};
  // A cycle among block arguments means the value only ever copies itself.
  SmallPtrSet<Value, 8> visited;
  while (!worklist.empty()) {
    Value cur = worklist.pop_back_val();
    Operation *def = cur.getDefiningOp();
    if (!definedIn(cur, seg) || isa_and_nonnull<arith::ConstantOp>(def)) {
      if (origin && origin != cur)
        return false;
      origin = cur;
      continue;
    }
    if (def)
      return false;
    if (!visited.insert(cur).second)
      continue;
    auto arg = cast<BlockArgument>(cur);
    Block *block = arg.getOwner();
    for (Block *pred : block->getPredecessors()) {
      auto branch = dyn_cast<BranchOpInterface>(pred->getTerminator());
      if (!branch)
        return false;
      for (unsigned i = 0, e = pred->getTerminator()->getNumSuccessors(); i < e;
           ++i) {
        if (pred->getTerminator()->getSuccessor(i) != block)
          continue;
        Value incoming = branch.getSuccessorOperands(i)[arg.getArgNumber()];
        if (!incoming)
          return false;
        worklist.push_back(incoming);
      }
    }
  }
  return true;
}

/// The blocks outside `seg` that read a value `seg` computes (one that is not
/// free to leave it): the block of an operation that uses it, and the block a
/// branch hands it to, when something reads the argument it becomes; and then
/// whoever reads that argument in turn, which is the value again or chosen
/// from it. The lowering threads such a value through every block between
/// the segment and its reader, so the reader is where the segment's result
/// is waited for.
static void collectReaders(const Segment &seg, Region &body,
                           SmallPtrSetImpl<Block *> &readers) {
  SmallVector<Value> worklist;
  for (Block *block : seg.blocks) {
    for (BlockArgument arg : block->getArguments())
      if (!isFreeToLeave(arg, seg))
        worklist.push_back(arg);
    for (Operation &op : *block)
      for (Value res : op.getResults())
        if (!isFreeToLeave(res, seg))
          worklist.push_back(res);
  }
  SmallPtrSet<Value, 16> seen(worklist.begin(), worklist.end());
  while (!worklist.empty()) {
    Value val = worklist.pop_back_val();
    for (OpOperand &use : val.getUses()) {
      Operation *user = body.findAncestorOpInRegion(*use.getOwner());
      if (!user)
        continue;
      Block *reader = user->getBlock();
      auto branch = dyn_cast<BranchOpInterface>(user);
      if (branch && user == use.getOwner()) {
        if (std::optional<BlockArgument> arg =
                branch.getSuccessorBlockArgument(use.getOperandNumber())) {
          // A value handed to an argument nothing reads carries nothing.
          if (arg->use_empty())
            continue;
          reader = arg->getOwner();
          if (seen.insert(*arg).second)
            worklist.push_back(*arg);
        }
      }
      if (!seg.contains(reader))
        readers.insert(reader);
    }
  }
}

/// The memory a memref value stands for, when that can be told: a function
/// argument or an allocation. Two different roots are two different
/// memories; a null root is anybody's guess.
static Value rootOf(Value memref) {
  if (auto arg = dyn_cast<BlockArgument>(memref))
    return arg.getOwner()->isEntryBlock() ? memref : Value();
  Operation *def = memref.getDefiningOp();
  return isa<memref::AllocOp, memref::AllocaOp>(def) ? memref : Value();
}

static bool connectsToMC(Operation *op) {
  auto attr = getDialectAttr<MemInterfaceAttr>(op);
  return attr && attr.connectsToMC();
}

/// Whether a recorded dependence names `dst` from `src`.
static bool dependsOn(Operation *src, Operation *dst, NameAnalysis &names) {
  auto deps = getDialectAttr<MemDependenceArrayAttr>(src);
  if (!deps)
    return false;
  StringRef dstName = names.getName(dst);
  return llvm::any_of(deps.getDependencies(), [&](MemDependenceAttr dep) {
    return StringRef(dep.getDstAccess()) == dstName;
  });
}

/// Whether the two segments' accesses may interleave. A recorded dependence
/// orders them. Two memories are free of each other. One memory both only
/// read is free. One memory one of them writes is free only when every
/// access to it goes to a memory controller AND the controllers were chosen
/// from the recorded dependences (`trustMC`): then an access on one is an
/// access the dependence analysis found free of every other, and the
/// controller executes them in arrival order. A forced controller says
/// nothing, and the memory keeps the segments in order. An LSQ would have to
/// serve both segments, which it cannot. An effect on another resource is
/// tied to the value it names (a port): two values are two things, one value
/// is one.
static bool memoryIndependent(const Segment &a, const Segment &b,
                              NameAnalysis &names, bool trustMC) {
  if (a.opaque || b.opaque)
    return false;
  for (const Access &x : a.accesses) {
    for (const Access &y : b.accesses) {
      if (x.resource != y.resource)
        continue;
      if (dependsOn(x.op, y.op, names) || dependsOn(y.op, x.op, names))
        return false;
      if (!x.isStore && !y.isStore)
        continue;
      if (x.resource != SideEffects::DefaultResource::get()) {
        if (x.memref != y.memref)
          continue;
        return false;
      }
      Value rx = rootOf(x.memref), ry = rootOf(y.memref);
      if (rx && ry && rx != ry)
        continue;
      if (trustMC && rx && rx == ry && connectsToMC(x.op) && connectsToMC(y.op))
        continue;
      return false;
    }
  }
  return true;
}

/// Records what an operation touches: memref loads and stores, then every
/// effect it declares on a value. An allocation makes a memory nobody else
/// has yet and counts as nothing. An effect on nothing in particular makes
/// the segment opaque.
static void collectAccesses(Operation &op, Segment &seg) {
  SideEffects::Resource *memory = SideEffects::DefaultResource::get();
  if (auto load = dyn_cast<memref::LoadOp>(op)) {
    seg.accesses.push_back({&op, load.getMemRef(), false, memory});
    return;
  }
  if (auto store = dyn_cast<memref::StoreOp>(op)) {
    seg.accesses.push_back({&op, store.getMemRef(), true, memory});
    return;
  }
  if (op.hasTrait<OpTrait::IsTerminator>() || isMemoryEffectFree(&op) ||
      isa<memref::AllocOp, memref::AllocaOp>(op))
    return;
  auto iface = dyn_cast<MemoryEffectOpInterface>(op);
  if (!iface) {
    seg.opaque = true;
    return;
  }
  SmallVector<MemoryEffects::EffectInstance> effects;
  iface.getEffects(effects);
  for (MemoryEffects::EffectInstance &effect : effects) {
    Value value = effect.getValue();
    if (!value) {
      seg.opaque = true;
      return;
    }
    bool isWrite = isa<MemoryEffects::Write>(effect.getEffect());
    seg.accesses.push_back({&op, value, isWrite, effect.getResource()});
  }
}

/// Groups one chain. First the straight-line blocks join the loop that
/// follows them (they are its preamble more often than not: the next loop's
/// constants, a lookahead's first reads), or the loop before them when they
/// end the chain, so that every unit holds a loop. Then regions are made
/// within a RANGE of consecutive units: everything before the range is done
/// when it starts, so only dependences inside the range order anything.
/// Within a range, units that must stay in order merge into one region with
/// everything between them, and what is left is a run of regions no two of
/// which share a dependence. A unit whose value is read after the range (by
/// a later unit, the chain's successor or any block after it) merges with
/// everything up to the range's end: the lowering threads the value through
/// the units after it, and only the last region may hand one on. A unit that
/// depends only on the last region joins it. One that depends on an earlier
/// region ends the range (through memory: a value it reads has merged its
/// unit into the last region already): the range so far becomes a group when
/// it holds two regions or more; when it holds one, a new range starts right
/// after the last unit the newcomer depends on, so that the tail can still
/// pair with it.
static void groupChain(func::FuncOp funcOp, BlockIndex &index,
                       NameAnalysis &names, bool trustMC, Block *entry,
                       SmallVectorImpl<Segment> &segments, Block *successor,
                       SmallVectorImpl<Attribute> &groups) {
  SmallVector<Segment> units;
  SmallVector<Segment> pending;
  auto absorb = [](Segment &into, Segment &block, bool before) {
    if (before)
      into.blocks.insert(into.blocks.begin(), block.blocks.begin(),
                         block.blocks.end());
    else
      into.blocks.append(block.blocks.begin(), block.blocks.end());
    into.accesses.append(block.accesses.begin(), block.accesses.end());
    into.opaque |= block.opaque;
  };
  for (Segment &seg : segments) {
    if (!seg.loop) {
      pending.push_back(std::move(seg));
      continue;
    }
    for (Segment &block : llvm::reverse(pending))
      absorb(seg, block, /*before=*/true);
    pending.clear();
    units.push_back(std::move(seg));
  }
  if (units.empty())
    return;
  for (Segment &block : pending)
    absorb(units.back(), block, /*before=*/false);
  unsigned n = units.size();
  if (n < 2)
    return;

  // Who reads what each unit computes: a later unit (liveOut), or, as
  // `lastReader`, the furthest one, n for a block in no unit (the chain's
  // successor, anything after it).
  llvm::DenseMap<Block *, unsigned> unitOf;
  for (auto [u, unit] : llvm::enumerate(units))
    for (Block *block : unit.blocks)
      unitOf[block] = u;
  SmallVector<SmallVector<bool>> liveOut(n, SmallVector<bool>(n, false));
  SmallVector<unsigned> lastReader(n, 0);
  for (unsigned i = 0; i < n; ++i) {
    SmallPtrSet<Block *, 8> readers;
    collectReaders(units[i], funcOp.getBody(), readers);
    for (Block *block : readers) {
      auto it = unitOf.find(block);
      // A reader in no unit, or (which a chain should not have) in an earlier
      // one, is after the chain as far as the grouping goes.
      unsigned u = it == unitOf.end() || it->second < i ? n : it->second;
      if (u < n)
        liveOut[i][u] = true;
      lastReader[i] = std::max(lastReader[i], u);
    }
  }

  // Dependences, once.
  SmallVector<SmallVector<bool>> dep(n, SmallVector<bool>(n, false));
  for (unsigned i = 0; i < n; ++i) {
    for (unsigned j = i + 1; j < n; ++j) {
      bool memory = memoryIndependent(units[i], units[j], names, trustMC);
      LLVM_DEBUG(llvm::dbgs()
                 << "units at blocks " << index[units[i].blocks.front()]
                 << " and " << index[units[j].blocks.front()] << ": "
                 << (liveOut[i][j] ? "a live-out" : "no live-out") << ", "
                 << (memory ? "memory independent" : "memory dependent")
                 << "\n");
      dep[i][j] = liveOut[i][j] || !memory;
    }
  }

  // The regions of [from, to]: every dependent pair's span merges, and so
  // does the span from a unit whose value is read after `to` to the end: the
  // lowering threads that value through the units after it, and only the
  // last region may hand one to the successor and beyond. Fills regionOf and
  // returns how many regions remain.
  SmallVector<unsigned> regionOf(n);
  auto computeRegions = [&](unsigned from, unsigned to) {
    for (unsigned k = from; k <= to; ++k)
      regionOf[k] = k;
    for (unsigned i = from; i <= to; ++i)
      for (unsigned j = i + 1; j <= to; ++j)
        if (dep[i][j] || (j == to && lastReader[i] > to))
          for (unsigned k = i; k <= j; ++k)
            regionOf[k] = regionOf[i];
    unsigned count = 0;
    for (unsigned k = from; k <= to; ++k)
      count += (k == from || regionOf[k] != regionOf[k - 1]);
    return count;
  };

  OpBuilder builder(funcOp.getContext());
  auto closeRange = [&](unsigned from, unsigned to) {
    if (computeRegions(from, to) < 2)
      return;
    SmallVector<Attribute> regions;
    std::string blocksText;
    for (unsigned i = from; i <= to;) {
      SmallVector<int64_t> ids;
      unsigned j = i;
      while (j <= to && regionOf[j] == regionOf[i]) {
        for (Block *block : units[j].blocks)
          ids.push_back(index[block]);
        ++j;
      }
      llvm::sort(ids);
      regions.push_back(builder.getI64ArrayAttr(ids));
      blocksText += (blocksText.empty() ? "[" : " [");
      for (auto [k, id] : llvm::enumerate(ids))
        blocksText += (k ? ", " : "") + std::to_string(id);
      blocksText += "]";
      i = j;
    }
    // The block whose control enters the first region: the chain's entry, or
    // the block the previous unit leaves from. The block the regions lead
    // to: the next unit's first block, or where the chain ended.
    Block *entryBlock = from > 0 ? units[from - 1].last() : entry;
    Block *successorBlock =
        to + 1 < n ? units[to + 1].blocks.front() : successor;
    unsigned entryId = index[entryBlock], successorId = index[successorBlock];
    groups.push_back(builder.getDictionaryAttr(
        {builder.getNamedAttr("entry", builder.getUI32IntegerAttr(entryId)),
         builder.getNamedAttr("regions", builder.getArrayAttr(regions)),
         builder.getNamedAttr("successor",
                              builder.getUI32IntegerAttr(successorId))}));
    mlir::emitRemark(funcOp.getLoc())
        << "parallel regions " << blocksText << " between blocks " << entryId
        << " and " << successorId;
  };

  unsigned rangeStart = 0;
  for (unsigned j = 1; j < n; ++j) {
    std::optional<unsigned> firstDep, lastDep;
    for (unsigned i = rangeStart; i < j; ++i) {
      if (!dep[i][j])
        continue;
      if (!firstDep)
        firstDep = i;
      lastDep = i;
    }
    if (!lastDep)
      continue;
    unsigned regions = computeRegions(rangeStart, j - 1);
    if (regions >= 2) {
      // The last region's first unit.
      unsigned lastRegion = j - 1;
      while (lastRegion > rangeStart &&
             regionOf[lastRegion - 1] == regionOf[j - 1])
        --lastRegion;
      if (*firstDep >= lastRegion)
        continue;
      closeRange(rangeStart, j - 1);
      rangeStart = j;
    } else if (*lastDep + 1 < j) {
      rangeStart = *lastDep + 1;
    }
  }
  closeRange(rangeStart, n - 1);
}

void CfDetectParallelRegionsPass::analyzeFunction(func::FuncOp funcOp) {
  // A function of one block has no loops, and dominance has nothing to say
  // about it (and asserts if asked).
  if (funcOp.getBody().hasOneBlock()) {
    funcOp->removeAttr(REGIONS_ATTR);
    return;
  }
  NameAnalysis &names = getAnalysis<NameAnalysis>();
  // A controller is evidence of independence only when
  // `mark-memory-interfaces` chose it from the recorded dependences; one that
  // `force-memory-interface` put there is not.
  bool trustMC = funcOp->hasAttr(MEM_INTERFACES_FROM_DEPS_ATTR);
  BlockIndex index;
  for (auto [i, block] : llvm::enumerate(funcOp.getBlocks()))
    index[&block] = i;

  DominanceInfo domInfo(funcOp);
  CFGLoopInfo loopInfo(domInfo.getDomTree(&funcOp.getBody()));

  // A chain starts at a top-level loop with one entry, one exiting block and
  // one exit, and continues at its exit: another such loop, or a block
  // outside every loop with one successor, is the next segment; anything
  // else ends the chain, and is the block its regions all lead to. The
  // block that enters the first loop is where they start. A function may
  // hold several chains, one after the other.
  SmallVector<CFGLoop *> loops(loopInfo.begin(), loopInfo.end());
  llvm::sort(loops, [&](CFGLoop *a, CFGLoop *b) {
    return index[a->getHeader()] < index[b->getHeader()];
  });
  auto wellFormed = [](CFGLoop *loop) {
    return loop->getLoopPredecessor() && loop->getExitingBlock() &&
           loop->getExitBlock();
  };
  llvm::SmallPtrSet<Block *, 16> seen;
  SmallVector<Attribute> groups;
  for (CFGLoop *first : loops) {
    if (seen.contains(first->getHeader()) || !wellFormed(first))
      continue;
    Block *entry = first->getLoopPredecessor();
    SmallVector<Segment> segments;
    Block *cur = first->getHeader();
    while (cur && seen.insert(cur).second) {
      Segment seg;
      if (CFGLoop *loop = loopInfo.getLoopFor(cur)) {
        if (loop->getParentLoop() || loop->getHeader() != cur ||
            !wellFormed(loop))
          break;
        seg.loop = loop;
        for (Block *block : loop->getBlocks()) {
          seg.blocks.push_back(block);
          seen.insert(block);
        }
        llvm::sort(seg.blocks,
                   [&](Block *a, Block *b) { return index[a] < index[b]; });
        seg.next = loop->getExitBlock();
      } else {
        if (cur->getNumSuccessors() != 1)
          break;
        seg.blocks.push_back(cur);
        seg.next = cur->getSuccessor(0);
      }
      for (Block *block : seg.blocks)
        for (Operation &op : *block)
          collectAccesses(op, seg);
      LLVM_DEBUG(llvm::dbgs()
                 << (seg.loop ? "loop" : "block") << " at block "
                 << index[seg.blocks.front()] << ": " << seg.accesses.size()
                 << " accesses" << (seg.opaque ? ", opaque" : "") << "\n");
      cur = seg.next;
      segments.push_back(std::move(seg));
    }
    // The chain must end somewhere its regions can all lead to: a block the
    // walk stopped at, not one it had absorbed.
    Block *successor = cur;
    if (!successor || segments.size() < 2 ||
        llvm::any_of(segments, [&](const Segment &seg) {
          return seg.contains(successor);
        }))
      continue;
    groupChain(funcOp, index, names, trustMC, entry, segments, successor,
               groups);
  }

  OpBuilder builder(funcOp.getContext());
  if (groups.empty())
    funcOp->removeAttr(REGIONS_ATTR);
  else
    funcOp->setAttr(REGIONS_ATTR, builder.getArrayAttr(groups));
}

void CfDetectParallelRegionsPass::runDynamaticPass() {
  // Functions may sit inside another operation (a streamblocks actor holds
  // its actions' functions), so walk rather than list the module's own.
  SmallVector<func::FuncOp> funcOps;
  getOperation().walk([&](func::FuncOp funcOp) {
    if (!funcOp.isExternal())
      funcOps.push_back(funcOp);
  });
  for (func::FuncOp funcOp : funcOps)
    analyzeFunction(funcOp);
}
