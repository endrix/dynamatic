//===- PushConstants.cpp - Push constants in using blocks -------*- C++ -*-===//
//
// Dynamatic is under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// This file contains the implementation of the constant pushing pass.
//
//===----------------------------------------------------------------------===//

#include "dynamatic/Support/LLVM.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/ControlFlow/IR/ControlFlowOps.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/OperationSupport.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "mlir/Support/IndentedOstream.h"

using namespace mlir;
using namespace dynamatic;

// [START Boilerplate code for the MLIR pass]
#include "dynamatic/Transforms/Passes.h" // IWYU pragma: keep
namespace dynamatic {
#define GEN_PASS_DEF_PUSHCONSTANTS
#include "dynamatic/Transforms/Passes.h.inc"
} // namespace dynamatic
// [END Boilerplate code for the MLIR pass]

/// Gives every edge of a multi-successor branch that forwards a constant a
/// block of its own: the edge block defines the constant and branches to the
/// successor with the edge's operands. A constant bound to a block argument
/// through a `cf.cond_br` is otherwise routed by that branch, which is a data
/// `cond_br` on the constant once the function is handshake; the edge block's
/// control token is the branch's control `cond_br`, which exists anyway.
static void splitConstantEdges(func::FuncOp funcOp, OpBuilder &builder) {
  SmallVector<std::pair<BranchOpInterface, unsigned>> edges;
  for (Block &block : funcOp.getBody()) {
    auto branch = dyn_cast<BranchOpInterface>(block.getTerminator());
    if (!branch || block.getNumSuccessors() < 2)
      continue;
    for (unsigned i = 0, e = block.getNumSuccessors(); i < e; ++i) {
      SuccessorOperands operands = branch.getSuccessorOperands(i);
      // An operand the terminator produces cannot be forwarded by a plain
      // branch from the edge block.
      if (operands.getProducedOperandCount() != 0)
        continue;
      if (llvm::any_of(
              operands.getForwardedOperands(),
              [](Value v) { return v.getDefiningOp<arith::ConstantOp>(); }))
        edges.emplace_back(branch, i);
    }
  }

  for (auto [branch, i] : edges) {
    Block *succ = branch->getSuccessor(i);
    SuccessorOperands operands = branch.getSuccessorOperands(i);
    SmallVector<Value> forwarded(operands.getForwardedOperands());
    // The edge block goes right after the branch's block, not before the
    // successor: an edge is a back edge in Dynamatic when it goes to a lower
    // block, so a constant on a loop's back edge must leave the edge from
    // the latch forward and the one into the header backward, as it was.
    Block *source = branch->getBlock();
    Block *edge = builder.createBlock(source->getParent(),
                                      std::next(source->getIterator()));
    for (Value &v : forwarded)
      if (auto cst = v.getDefiningOp<arith::ConstantOp>())
        v = arith::ConstantOp::create(builder, cst->getLoc(), cst.getValue());
    cf::BranchOp::create(builder, branch->getLoc(), succ, forwarded);
    operands.erase(0, operands.getForwardedOperands().size());
    branch->setSuccessor(edge, i);
  }
}

/// Pushes all of a function's constants in blocks using them.
static LogicalResult pushConstants(func::FuncOp funcOp, MLIRContext *ctx,
                                   bool throughBranches) {
  OpBuilder builder(ctx);
  if (throughBranches)
    splitConstantEdges(funcOp, builder);

  for (auto constantOp :
       llvm::make_early_inc_range(funcOp.getOps<arith::ConstantOp>())) {
    Block *defBlock = constantOp->getBlock();
    bool usedByDefiningBlock = false;

    // Determine blocks where the constant is used
    DenseMap<Block *, SmallVector<Operation *, 4>> usingBlocks;
    for (auto *user : constantOp.getResult().getUsers())
      if (auto *block = user->getBlock(); block != defBlock)
        usingBlocks[block].push_back(user);
      else
        usedByDefiningBlock = true;

    // Create a new constant operation in every block where the constant is used
    for (auto &[block, users] : usingBlocks) {
      builder.setInsertionPointToStart(block);
      auto newCstOp = arith::ConstantOp::create(builder, constantOp->getLoc(),
                                                constantOp.getValue());
      for (auto *user : users)
        user->replaceUsesOfWith(constantOp.getResult(), newCstOp.getResult());
    }

    // Delete the original constant operation if it isn't used
    if (!usedByDefiningBlock)
      constantOp->erase();
  }

  return success();
}

namespace {

/// Simple driver for constant pushing pass. Runs the pass on every function in
/// the module independently and succeeds whenever the transformation succeeded
/// for every function.
struct PushConstantsPass
    : public dynamatic::impl::PushConstantsBase<PushConstantsPass> {

  using PushConstantsBase::PushConstantsBase;
  void runDynamaticPass() override {
    ModuleOp m = getOperation();
    // Process every function individually, at any depth: a function nested in
    // another operation's region (an actor's actions, say) is a function all
    // the same, and a constant it leaves in its entry block becomes a value
    // threaded through every loop between the entry and its user.
    WalkResult result = m.walk([&](func::FuncOp funcOp) {
      return failed(pushConstants(funcOp, &getContext(), throughBranches))
                 ? WalkResult::interrupt()
                 : WalkResult::advance();
    });
    if (result.wasInterrupted())
      return signalPassFailure();
  };
};
} // namespace
