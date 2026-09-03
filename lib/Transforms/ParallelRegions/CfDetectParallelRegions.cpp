//===- CfDetectParallelRegions.cpp - Find regions that may run at once -*- C++ -*-===//
//
// Dynamatic is under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// Implements the --cf-detect-parallel-regions pass.
//
// At the cf level a function is a graph of blocks, and its loops are the
// natural regions: a top-level loop nest starts when its header is entered
// and is done when its exiting block leaves. Consecutive nests that share no
// value and no ordered memory access could start together; the sequential
// lowering nevertheless chains them. This pass finds such runs of nests and
// records them in the function's `handshake.parallel_regions` attribute, in
// the block ids the lowering will assign (position in the function), for
// --handshake-parallelize-regions to act on after the lowering.
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
#include "llvm/ADT/SmallVector.h"

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

/// A memory access inside a loop.
struct Access {
  Operation *op;
  Value memref;
  bool isStore;
};

/// A top-level loop that has the shape a region needs: one block enters it,
/// one block leaves it, to one place.
struct Candidate {
  CFGLoop *loop;
  Block *pred;
  Block *exiting;
  Block *exit;
  SmallVector<Access> accesses;
  /// True when the loop holds an operation whose memory behaviour is not a
  /// load or a store of a memref (a call, say); nothing runs beside it.
  bool opaque = false;
};

struct CfDetectParallelRegionsPass
    : public dynamatic::impl::CfDetectParallelRegionsBase<
          CfDetectParallelRegionsPass> {
  using CfDetectParallelRegionsBase::CfDetectParallelRegionsBase;

  void runDynamaticPass() override;

private:
  void analyzeFunction(func::FuncOp funcOp);
};

} // namespace

/// Whether the value is a block argument of, or produced inside, the loop.
static bool definedIn(Value val, CFGLoop *loop) {
  if (auto arg = dyn_cast<BlockArgument>(val))
    return loop->contains(arg.getOwner());
  return loop->contains(val.getDefiningOp()->getBlock());
}

/// Whether a value that leaves `loop` costs the next region nothing: a
/// constant, which the lowering re-makes wherever it is needed, or a block
/// argument the loop only carries around unchanged, whose origin is itself
/// free. Anything computed inside the loop is a live-out.
static bool isFreeToLeave(Value val, CFGLoop *loop,
                          SmallPtrSetImpl<Value> &visiting) {
  if (!definedIn(val, loop))
    return true;
  if (Operation *def = val.getDefiningOp())
    return isa<arith::ConstantOp>(def);
  auto arg = cast<BlockArgument>(val);
  // A cycle among block arguments means the value only ever copies itself.
  if (!visiting.insert(val).second)
    return true;
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
      if (incoming == val)
        continue;
      if (!isFreeToLeave(incoming, loop, visiting))
        return false;
    }
  }
  return true;
}

/// Whether `later` uses a value `earlier` computes, other than through the
/// forms isFreeToLeave admits.
static bool hasLiveOut(const Candidate &earlier, const Candidate &later) {
  SmallPtrSet<Value, 8> visiting;
  auto crosses = [&](Value val) {
    if (!definedIn(val, earlier.loop))
      return false;
    visiting.clear();
    return !isFreeToLeave(val, earlier.loop, visiting);
  };
  for (Block *block : later.loop->getBlocks()) {
    // Values branched into this block from the earlier loop.
    for (Block *pred : block->getPredecessors()) {
      if (!earlier.loop->contains(pred))
        continue;
      auto branch = dyn_cast<BranchOpInterface>(pred->getTerminator());
      if (!branch)
        return true;
      for (unsigned i = 0, e = pred->getTerminator()->getNumSuccessors();
           i < e; ++i) {
        if (pred->getTerminator()->getSuccessor(i) != block)
          continue;
        for (Value val : branch.getSuccessorOperands(i).getForwardedOperands())
          if (crosses(val))
            return true;
      }
    }
    // Values used directly, which dominance permits from the exiting block.
    for (Operation &op : *block)
      for (Value val : op.getOperands())
        if (crosses(val))
          return true;
  }
  return false;
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

/// Whether the two loops' memory accesses may interleave. A recorded
/// dependence orders them. Two memories are free of each other. One memory
/// both only read is free. One memory one of them writes is free only when
/// every access to it goes to a memory controller, which executes them in
/// arrival order -- the same trust in the dependence analysis that sent
/// them there; an LSQ would have to serve both loops, which it cannot.
static bool memoryIndependent(const Candidate &a, const Candidate &b,
                              NameAnalysis &names) {
  if (a.opaque || b.opaque)
    return false;
  for (const Access &x : a.accesses) {
    for (const Access &y : b.accesses) {
      if (dependsOn(x.op, y.op, names) || dependsOn(y.op, x.op, names))
        return false;
      if (!x.isStore && !y.isStore)
        continue;
      Value rx = rootOf(x.memref), ry = rootOf(y.memref);
      if (rx && ry && rx != ry)
        continue;
      if (rx && rx == ry && connectsToMC(x.op) && connectsToMC(y.op))
        continue;
      return false;
    }
  }
  return true;
}

static bool independent(const Candidate &earlier, const Candidate &later,
                        NameAnalysis &names) {
  return !hasLiveOut(earlier, later) &&
         memoryIndependent(earlier, later, names);
}

void CfDetectParallelRegionsPass::analyzeFunction(func::FuncOp funcOp) {
  // A function of one block has no loops, and dominance has nothing to say
  // about it (and asserts if asked).
  if (funcOp.getBody().hasOneBlock()) {
    funcOp->removeAttr(REGIONS_ATTR);
    return;
  }
  NameAnalysis &names = getAnalysis<NameAnalysis>();
  llvm::DenseMap<Block *, unsigned> index;
  for (auto [i, block] : llvm::enumerate(funcOp.getBlocks()))
    index[&block] = i;

  DominanceInfo domInfo(funcOp);
  CFGLoopInfo loopInfo(domInfo.getDomTree(&funcOp.getBody()));

  // Top-level loops in program order, keeping those a region can be made of.
  SmallVector<CFGLoop *> loops(loopInfo.begin(), loopInfo.end());
  llvm::sort(loops, [&](CFGLoop *a, CFGLoop *b) {
    return index[a->getHeader()] < index[b->getHeader()];
  });
  SmallVector<Candidate> candidates;
  for (CFGLoop *loop : loops) {
    Candidate cand{loop, loop->getLoopPredecessor(), loop->getExitingBlock(),
                   loop->getExitBlock()};
    if (!cand.pred || !cand.exiting || !cand.exit)
      continue;
    for (Block *block : loop->getBlocks()) {
      for (Operation &op : *block) {
        if (auto load = dyn_cast<memref::LoadOp>(op))
          cand.accesses.push_back({&op, load.getMemRef(), false});
        else if (auto store = dyn_cast<memref::StoreOp>(op))
          cand.accesses.push_back({&op, store.getMemRef(), true});
        else if (!isMemoryEffectFree(&op) && !op.hasTrait<OpTrait::IsTerminator>())
          cand.opaque = true;
      }
    }
    candidates.push_back(std::move(cand));
  }

  // Walk the candidates in order and grow a group while the next loop follows
  // the last one directly and is independent of every loop already in it.
  SmallVector<Attribute> groups;
  OpBuilder builder(funcOp.getContext());
  SmallVector<const Candidate *> current;
  auto flush = [&]() {
    if (current.size() >= 2) {
      SmallVector<Attribute> regions;
      std::string blocksText;
      for (const Candidate *cand : current) {
        SmallVector<int64_t> ids;
        for (Block *block : cand->loop->getBlocks())
          ids.push_back(index[block]);
        llvm::sort(ids);
        regions.push_back(builder.getI64ArrayAttr(ids));
        blocksText += (blocksText.empty() ? "[" : " [");
        for (auto [i, id] : llvm::enumerate(ids))
          blocksText += (i ? ", " : "") + std::to_string(id);
        blocksText += "]";
      }
      unsigned entry = index[current.front()->pred];
      unsigned successor = index[current.back()->exit];
      groups.push_back(builder.getDictionaryAttr(
          {builder.getNamedAttr("entry", builder.getUI32IntegerAttr(entry)),
           builder.getNamedAttr("regions", builder.getArrayAttr(regions)),
           builder.getNamedAttr("successor",
                                builder.getUI32IntegerAttr(successor))}));
      mlir::emitRemark(funcOp.getLoc())
          << "parallel regions " << blocksText << " between blocks " << entry
          << " and " << successor;
    }
    current.clear();
  };
  for (const Candidate &cand : candidates) {
    bool follows = !current.empty() &&
                   current.back()->exit == cand.loop->getHeader() &&
                   cand.pred == current.back()->exiting;
    if (follows && llvm::all_of(current, [&](const Candidate *prev) {
          return independent(*prev, cand, names);
        })) {
      current.push_back(&cand);
      continue;
    }
    flush();
    current.push_back(&cand);
  }
  flush();

  if (groups.empty())
    funcOp->removeAttr(REGIONS_ATTR);
  else
    funcOp->setAttr(REGIONS_ATTR, builder.getArrayAttr(groups));
}

void CfDetectParallelRegionsPass::runDynamaticPass() {
  for (func::FuncOp funcOp : getOperation().getOps<func::FuncOp>())
    if (!funcOp.isExternal())
      analyzeFunction(funcOp);
}
