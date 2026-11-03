//===- FtdImplementation.cpp --- Main FTD Algorithm -------------*- C++ -*-===//
//
// Dynamatic is under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// Implements the top-level FTD algorithm orchestration: GSA conversion,
// regeneration, suppression dispatch, and phi networks. The suppression
// circuit construction infrastructure lives in FtdSuppression.cpp.
//
//===----------------------------------------------------------------------===//

#include "experimental/Support/FtdImplementation.h"
#include "dynamatic/Analysis/ControlDependenceAnalysis.h"
#include "dynamatic/Support/Backedge.h"
#include "experimental/Support/BooleanLogic/BDD.h"
#include "experimental/Support/BooleanLogic/BoolExpression.h"
#include "experimental/Support/FtdSupport.h"
#include "experimental/Support/FtdSuppression.h"
#include "mlir/Analysis/CFGLoopInfo.h"
#include "mlir/Dialect/ControlFlow/IR/ControlFlowOps.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/Transforms/DialectConversion.h"
#include <functional>
#include <optional>
#include <tuple>

using namespace mlir;
using namespace dynamatic;
using namespace dynamatic::experimental;
using namespace dynamatic::experimental::ftd;
using namespace dynamatic::experimental::boolean;

// ===--------------------------------------------------------------------=== //
// Condition placeholder management
// ===--------------------------------------------------------------------=== //

void ftd::createAllCondPlaceholders(Region &region, OpBuilder &builder) {
  for (Block &block : region) {
    if (isa<cf::CondBranchOp>(block.getTerminator()))
      getOrCreateCondPlaceholder(&block, builder);
  }
}

/// Resolves all SourceOp condition placeholders into NotIOp pass-throughs
/// connected to the real handshake condition values from ShadowCFG.
void ftd::resolveCondPlaceholders(handshake::FuncOp funcOp, OpBuilder &builder,
                                  ftd::ShadowCFG &shadow) {
  Block &entryBlock = funcOp.getBody().front();

  // Collect the condition placeholders (the tagged constants) in the entry.
  SmallVector<Operation *> placeholders;
  for (Operation &op : entryBlock) {
    if (isa<handshake::ConstantOp>(&op) && op.hasAttr(FTD_COND_VAR))
      placeholders.push_back(&op);
  }

  for (Operation *ph : placeholders) {
    auto bbAttr = ph->getAttrOfType<IntegerAttr>("handshake.bb");
    if (!bbAttr)
      continue;
    unsigned bbIdx = bbAttr.getUInt();

    // The real handshake condition this placeholder stands for.
    Value realCond = shadow.getCondition(bbIdx);
    if (!realCond)
      continue;

    if (auto *defOp = realCond.getDefiningOp())
      builder.setInsertionPointAfter(defOp);
    else
      builder.setInsertionPointToStart(&entryBlock);

    Location loc = ph->getLoc();
    Type chanI1 = ftd::channelifyType(builder.getI1Type());

    // Forward the real condition through a NotIOp that keeps the placeholder
    // tag, so finalizeCondPlaceholders can later short-circuit and remove it.
    auto notOp = handshake::NotIOp::create(builder, loc, chanI1, realCond);
    notOp->setAttr(FTD_COND_VAR, builder.getUnitAttr());
    notOp->setAttr("handshake.bb", bbAttr);

    // Kill the old ConstantOp placeholder and its SourceOp
    Operation *phSourceOp = ph->getOperand(0).getDefiningOp();
    ph->getResult(0).replaceAllUsesWith(notOp.getResult());
    ph->erase();
    if (phSourceOp && phSourceOp->use_empty())
      phSourceOp->erase();
  }
}

/// Short-circuits all NotIOp condition placeholders and erases them.
void ftd::finalizeCondPlaceholders(handshake::FuncOp funcOp) {
  SmallVector<handshake::NotIOp> notOps;
  for (auto notOp : funcOp.getOps<handshake::NotIOp>()) {
    if (notOp->hasAttr(FTD_COND_VAR))
      notOps.push_back(notOp);
  }
  for (auto notOp : notOps) {
    notOp.getResult().replaceAllUsesWith(notOp.getOperand());

    notOp->erase();
  }
}

// ===--------------------------------------------------------------------=== //
// Static CFG helpers (used only by phi network functions)
// ===--------------------------------------------------------------------=== //

/// Given a block, get its immediate dominator if exists
static Block *getImmediateDominator(Region &region, Block *bb) {

  // Avoid a situation with no blocks in the region
  if (region.getBlocks().empty())
    return nullptr;

  // The first block in the CFG has both no predecessors and no dominators
  if (bb->hasNoPredecessors())
    return nullptr;

  DominanceInfo domInfo;
  llvm::DominatorTreeBase<Block, false> &domTree = domInfo.getDomTree(&region);
  return domTree.getNode(bb)->getIDom()->getBlock();
}

/// Get the dominance frontier of each block in the region
static DenseMap<Block *, DenseSet<Block *>>
getDominanceFrontier(Region &region) {

  // This algorithm comes from the following paper:
  // Cooper, Keith D., Timothy J. Harvey and Ken Kennedy. “A Simple, Fast
  // Dominance Algorithm.” (1999).

  DenseMap<Block *, DenseSet<Block *>> result;

  // Create an empty dominance-frontier set for each block
  for (Block &bb : region.getBlocks())
    result.insert({&bb, DenseSet<Block *>()});

  for (Block &bb : region.getBlocks()) {

    // Get the predecessors of the block
    auto predecessors = bb.getPredecessors();

    // Count the number of predecessors
    int numberOfPredecessors = 0;
    for (auto *pred : predecessors)
      if (pred)
        numberOfPredecessors++;

    // Skip if the node has none or only one predecessors
    if (numberOfPredecessors < 2)
      continue;

    // For each predecessor, walk up the dominator tree, adding bb to the
    // frontier of every block until bb's immediate dominator is reached.
    for (auto *pred : predecessors) {
      Block *runner = pred;
      // Runner performs a bottom up traversal of the dominator tree
      while (runner != getImmediateDominator(region, &bb)) {
        result[runner].insert(&bb);
        runner = getImmediateDominator(region, runner);
      }
    }
  }

  return result;
}

/// Get a list of all the loops in which the consumer is but the producer is
/// not, starting from the innermost.
static SmallVector<CFGLoop *> getLoopsConsNotInProd(Block *consBlock,
                                                    Block *prodBlock,
                                                    CFGLoopInfo &loopInfo) {

  SmallVector<CFGLoop *> result;

  CFGLoop *consLoop = loopInfo.getLoopFor(consBlock);
  if (!consLoop)
    return result;

  // Walk outward from the consumer's innermost loop.
  // Collect every loop that does NOT contain the producer.
  for (CFGLoop *loop = consLoop; loop; loop = loop->getParentLoop()) {
    if (!loop->contains(prodBlock))
      result.push_back(loop);
  }

  // Reverse to ensure the loops from outermost to innermost
  std::reverse(result.begin(), result.end());

  return result;
}

/// Run the Cytron algorithm to determine, give a set of values, in which blocks
/// should we add a merge in order for those values to be merged
static DenseSet<Block *>
runCrytonAlgorithm(Region &funcRegion, DenseMap<Block *, Value> &inputBlocks) {
  // Get dominance frontier
  auto dominanceFrontier = getDominanceFrontier(funcRegion);

  // Temporary data structures to run the Cytron algorithm for phi positioning
  DenseMap<Block *, bool> work;
  DenseMap<Block *, bool> hasAlready;
  SmallVector<Block *> w;

  DenseSet<Block *> result;

  // Initialize data structures to run the Cytron algorithm
  for (auto &bb : funcRegion.getBlocks()) {
    work.insert({&bb, false});
    hasAlready.insert({&bb, false});
  }

  for (auto &[bb, val] : inputBlocks)
    w.push_back(bb), work[bb] = true;

  // Until there are no more elements in `w`
  while (w.size() != 0) {

    // Pop the top of `w`
    auto *x = w.back();
    w.pop_back();

    // Get the dominance frontier of `w`
    auto xFrontier = dominanceFrontier[x];

    // For each of its elements
    for (auto &y : xFrontier) {

      // Add the block in the dominance frontier to the list of blocks which
      // require a new phi. If it was not analyzed yet, also add it to `w`
      if (!hasAlready[y]) {
        result.insert(y);
        hasAlready[y] = true;
        if (!work[y])
          work[y] = true, w.push_back(y);
      }
    }
  }

  return result;
}

// ===--------------------------------------------------------------------=== //
// Phi Network
// ===--------------------------------------------------------------------=== //

LogicalResult experimental::ftd::createPhiNetwork(
    Region &funcRegion, PatternRewriter &rewriter, SmallVector<Value> &vals,
    SmallVector<OpOperand *> &toSubstitue) {

  if (vals.empty()) {
    llvm::errs() << "Input of \"createPhiNetwork\" is empty";
    return failure();
  }

  auto *ctx = funcRegion.getContext();
  OpBuilder builder(ctx);

  mlir::DominanceInfo domInfo;
  // Type of the inputs
  Type valueType = vals[0].getType();
  // All the input values associated to one block
  DenseMap<Block *, SmallVector<Value>> valuesPerBlock;
  // Associate for each block the value that is dominated by all the others in
  // the same block
  DenseMap<Block *, Value> inputBlocks;
  // Backedge builder to insert new merges
  BackedgeBuilder edgeBuilder(builder, funcRegion.getLoc());
  // Backedge corresponding to each phi
  DenseMap<Block *, Backedge> resultPerPhi;
  // Operands of each merge
  DenseMap<Block *, SmallVector<Value>> operandsPerPhi;
  // Which value should be the input of each input value
  DenseMap<Block *, Value> inputPerBlock;

  // Check that all the values have the same type, then collet them according to
  // their input blocks
  for (auto &val : vals) {
    if (val.getType() != valueType) {
      llvm::errs() << "All values must have the same type\n";
      return failure();
    }
    auto *bb = val.getParentBlock();
    valuesPerBlock[bb].push_back(val);
  }

  // Sort the vectors of values in each block according to their dominance and
  // get only the last input value for each block. This is necessary in case in
  // the input sets there is more than one value per blocks
  for (auto &[bb, vals] : valuesPerBlock) {
    std::sort(vals.begin(), vals.end(), [&](Value a, Value b) -> bool {
      if (!a.getDefiningOp())
        return false;
      if (!b.getDefiningOp())
        return true;
      return domInfo.dominates(b.getDefiningOp(), a.getDefiningOp());
    });
    inputBlocks.insert({bb, vals[0]});
  }

  // In which block a new phi is necessary
  DenseSet<Block *> blocksToAddPhi =
      runCrytonAlgorithm(funcRegion, inputBlocks);

  // A backedge is created for each block in `blocksToAddPhi`, and it will
  // contain the value used as placeholder for the phi
  for (auto &bb : blocksToAddPhi) {
    Backedge mergeResult = edgeBuilder.get(valueType, bb->front().getLoc());
    operandsPerPhi.insert({bb, SmallVector<Value>()});
    resultPerPhi.insert({bb, mergeResult});
  }

  // For each phi, we need one input for every predecessor of the block
  for (auto &bb : blocksToAddPhi) {

    // Avoid to cover a predecessor twice
    llvm::DenseSet<Block *> coveredPred;
    auto predecessors = bb->getPredecessors();

    for (Block *pred : predecessors) {
      if (coveredPred.contains(pred))
        continue;
      coveredPred.insert(pred);

      // If the predecessor does not contains a definition of the value, we move
      // to its immediate dominator, until we have found a definition.
      Block *predecessorOrDominator = nullptr;
      Value valueToUse = nullptr;

      do {
        predecessorOrDominator =
            !predecessorOrDominator
                ? pred
                : getImmediateDominator(funcRegion, predecessorOrDominator);

        if (inputBlocks.contains(predecessorOrDominator))
          valueToUse = inputBlocks[predecessorOrDominator];
        else if (resultPerPhi.contains(predecessorOrDominator))
          valueToUse = resultPerPhi.find(predecessorOrDominator)->getSecond();

      } while (!valueToUse);

      operandsPerPhi[bb].push_back(valueToUse);
    }
  }

  // Create the merge and then replace the values
  DenseMap<Block *, handshake::MergeOp> newMergePerPhi;

  for (auto *bb : blocksToAddPhi) {
    rewriter.setInsertionPointToStart(bb);
    auto mergeOp = handshake::MergeOp::create(rewriter, bb->front().getLoc(),
                                              operandsPerPhi[bb]);
    mergeOp->setAttr(NEW_PHI, rewriter.getUnitAttr());
    newMergePerPhi.insert({bb, mergeOp});
  }

  for (auto *bb : blocksToAddPhi)
    resultPerPhi.find(bb)->getSecond().setValue(newMergePerPhi[bb].getResult());

  // For each block, find the incoming value of the network
  for (Block &bb : funcRegion.getBlocks()) {

    Value foundValue = nullptr;
    Block *blockOrDominator = &bb;

    if (blocksToAddPhi.contains(&bb)) {
      inputPerBlock[&bb] = newMergePerPhi[&bb].getResult();
      continue;
    }

    do {
      if (!blockOrDominator->hasNoPredecessors())
        blockOrDominator = getImmediateDominator(funcRegion, blockOrDominator);

      if (inputBlocks.contains(blockOrDominator)) {
        foundValue = inputBlocks[blockOrDominator];
      } else if (blocksToAddPhi.contains(blockOrDominator)) {
        foundValue = newMergePerPhi[blockOrDominator].getResult();
      }

    } while (!foundValue);

    inputPerBlock[&bb] = foundValue;
  }

  for (auto &op : toSubstitue)
    op->set(inputPerBlock[op->getOwner()->getBlock()]);

  return success();
}

LogicalResult ftd::createPhiNetworkDeps(
    Region &funcRegion, PatternRewriter &rewriter,
    const DenseMap<OpOperand *, SmallVector<Value>> &dependenciesMap) {

  mlir::DominanceInfo domInfo;

  // For each pair of operand and its dependencies
  for (auto &[operand, dependencies] : dependenciesMap) {

    Operation *operandOwner = operand->getOwner();
    auto startValue = (Value)funcRegion.getArguments().back();

    /// Lambda to run the SSA analysis over the pair of values {dep, startValue}
    /// and properly connect the operand `op` to the correct value in the
    /// network.
    auto connect = [&](OpOperand *op, Value dep) -> LogicalResult {
      Operation *depOwner = dep.getDefiningOp();

      // If the producer and the consumer are in the same basic block, and the
      // producer properly dominates the consumer (i.e. comes before in a linear
      // sense) then the consumer is directly connected to the producer without
      // further mechanism.
      if (dep.getParentBlock() == operandOwner->getBlock() &&
          domInfo.properlyDominates(depOwner, operandOwner)) {
        op->set(dep);
        return success();
      }

      // Otherwise, we run the SSA insertion
      SmallVector<mlir::OpOperand *> operandsToChange = {op};
      SmallVector<Value> inputValues = {startValue, dep};

      if (failed(ftd::createPhiNetwork(funcRegion, rewriter, inputValues,
                                       operandsToChange))) {
        return failure();
      }

      return success();
    };

    // If the operand has not dependencies, then it can be connected to start
    // directly.
    if (dependencies.size() == 0) {
      operand->set(startValue);
      continue;
    }

    // If the operand has one dependency only, there is no need for a join.
    if (dependencies.size() == 1) {
      if (failed(connect(operand, dependencies[0])))
        return failure();
      continue;
    }

    // If the operand has many dependencies, then each of them is singularly
    // connected with an SSA network, and then everything is joined.
    ValueRange operands = dependencies;
    rewriter.setInsertionPointToStart(operand->getOwner()->getBlock());
    auto joinOp = handshake::JoinOp::create(
        rewriter, operand->getOwner()->getLoc(), operands);
    joinOp->moveBefore(operandOwner);

    for (unsigned i = 0; i < dependencies.size(); i++) {
      if (failed(connect(&joinOp->getOpOperand(i), dependencies[i])))
        return failure();
    }

    operand->set(joinOp.getResult());
  }

  return success();
}

// ===--------------------------------------------------------------------=== //
// Regeneration
// ===--------------------------------------------------------------------=== //

/// Returns true if `operand` is taken by the gate `consumerOp` once per entry
/// of the loop whose header holds it, rather than once per iteration: the
/// initial input of a MU, and any input of a gamma of the tree which builds a
/// MU's initial input in the MU's own block (the tree of the phi of the inputs
/// from outside the loop, placed in the header with the MU). A gamma in
/// another block, a preheader or the exit of a previous loop, runs once per
/// iteration of its own loop, even when its value is a MU's initial input.
static bool isTakenOncePerLoopEntry(Operation *consumerOp, Value operand) {
  auto isInitOfMu = [](Operation *user, Value v) -> bool {
    return llvm::isa<handshake::MuxOp>(user) &&
           user->hasAttr(FTD_EXPLICIT_MU) && user->getOperand(1) == v;
  };
  if (consumerOp->hasAttr(FTD_EXPLICIT_MU))
    return isInitOfMu(consumerOp, operand);
  if (!consumerOp->hasAttr(FTD_EXPLICIT_GAMMA))
    return false;

  // Follow the gamma tree to its root, and check what the root feeds
  SmallVector<Operation *> worklist = {consumerOp};
  DenseSet<Operation *> visited;
  while (!worklist.empty()) {
    Operation *gamma = worklist.pop_back_val();
    if (!visited.insert(gamma).second)
      continue;
    for (Operation *user : gamma->getResult(0).getUsers()) {
      if (isInitOfMu(user, gamma->getResult(0)) &&
          user->getAttr("handshake.bb") == gamma->getAttr("handshake.bb"))
        return true;
      if (llvm::isa<handshake::MuxOp>(user) &&
          user->hasAttr(FTD_EXPLICIT_GAMMA) &&
          user->getAttr("handshake.bb") == gamma->getAttr("handshake.bb"))
        worklist.push_back(user);
    }
  }
  return false;
}

void ftd::addRegenOperandConsumer(mlir::OpBuilder &builder,
                                  handshake::FuncOp &funcOp,
                                  Operation *consumerOp, Value operand,
                                  ftd::ShadowCFG &shadow) {

  // All analysis runs on the shadow Region (multi-block, real CF terminators)
  Region &shadowRegion = shadow.getRegion();
  BlockIndexing bi(shadowRegion);
  DominanceInfo domInfo(shadow.shadowFunc);
  CFGLoopInfo loopInfo(domInfo.getDomTree(&shadowRegion));

  // Skip if the consumer was added by this function, if it is an init merge or
  // if it is a generic operation to skip
  if (consumerOp->hasAttr(FTD_REGEN) || consumerOp->hasAttr(FTD_INIT_MERGE) ||
      consumerOp->hasAttr(FTD_OP_TO_SKIP))
    return;

  // The gates of the GSA analysis are consumers like the others: a gamma or a
  // MU inside a loop takes a value produced outside the loop at each iteration
  // which selects it, so the value is regenerated. The select of a MU is the
  // init merge of its own loop, and is left alone. A value taken once per entry
  // of a loop (the initial input of a MU, and the inputs of the gammas building
  // it) is regenerated for the loops around that loop only, like the inputs of
  // a loop merge.
  if (consumerOp->hasAttr(FTD_EXPLICIT_MU) &&
      consumerOp->getOperand(0) == operand)
    return;
  bool oncePerLoopEntry = consumerOp->hasAttr(NEW_PHI) ||
                          isTakenOncePerLoopEntry(consumerOp, operand);

  // Skip if the consumer has to do with memory operations, cmerge networks or
  // if it is a conditional branch.
  if (llvm::isa_and_nonnull<handshake::MemoryOpInterface>(consumerOp) ||
      llvm::isa_and_nonnull<handshake::ControlMergeOp>(consumerOp) ||
      llvm::isa_and_nonnull<handshake::ConditionalBranchOp>(consumerOp))
    return;

  mlir::Operation *producerOp = operand.getDefiningOp();

  uint32_t prodId = 0, consId = 0;
  if (operand.getDefiningOp())
    if (auto intAttr =
            producerOp->getAttrOfType<mlir::IntegerAttr>("handshake.bb")) {
      prodId = intAttr.getUInt();
    }
  if (auto intAttr =
          consumerOp->getAttrOfType<mlir::IntegerAttr>("handshake.bb")) {
    consId = intAttr.getUInt();
  }

  // Skip if the producer was added by this function or if it is an op to skip
  if (producerOp &&
      (producerOp->hasAttr(FTD_REGEN) || producerOp->hasAttr(FTD_OP_TO_SKIP)))
    return;

  // Skip if the producer has to do with memory operations
  if (llvm::isa_and_nonnull<handshake::MemoryOpInterface>(producerOp) ||
      llvm::isa_and_nonnull<MemRefType>(operand.getType()))
    return;

  // Map BB indices to shadow blocks for loop analysis
  Block *prodBlock = shadow.getBlock(prodId);
  Block *consBlock = shadow.getBlock(consId);

  // Get all the loops for which we need to regenerate the
  // corresponding value
  SmallVector<CFGLoop *> loops =
      getLoopsConsNotInProd(consBlock, prodBlock, loopInfo);
  unsigned numberOfLoops = loops.size();

  if (numberOfLoops == 0)
    return;

  Value regeneratedValue = operand;

  // The real (flattened) block where new ops are inserted
  Block *realBlock = &funcOp.getBody().front();

  auto createRegenMux = [&](CFGLoop *loop) -> handshake::MuxOp {
    builder.setInsertionPointToStart(realBlock);

    // BB index of the loop header (for handshake.bb tagging)
    unsigned headerBBIdx = shadow.getBlockIndex(loop->getHeader());
    auto headerBBAttr = ftd::getBBIndexAttr(builder.getContext(), headerBBIdx);

    // Determine the loop exit condition:
    Value conditionValue;
    Block *loopHeader = loop->getHeader();

    conditionValue = computeLoopBackedgeCondition(
        builder, loopHeader, realBlock, bi, nullptr, &shadow);

    Operation *initOp;
    initOp = handshake::InitOp::create(builder, consumerOp->getLoc(),
                                       conditionValue);

    initOp->setAttr(FTD_INIT_MERGE, builder.getUnitAttr());
    initOp->setAttr("handshake.bb", headerBBAttr);

    // The multiplexer is to be fed by the init block, and takes as inputs the
    // regenerated value and the result itself (to be set after) it was created.
    auto selectSignal = initOp->getResult(0);
    selectSignal.setType(channelifyType(selectSignal.getType()));

    SmallVector<Value> muxOperands = {regeneratedValue, regeneratedValue};
    auto muxOp = handshake::MuxOp::create(builder, regeneratedValue.getLoc(),
                                          regeneratedValue.getType(),
                                          selectSignal, muxOperands);

    muxOp->setOperand(2, muxOp->getResult(0));
    muxOp->setAttr(FTD_REGEN, builder.getUnitAttr());
    muxOp->setAttr("handshake.bb", headerBBAttr);

    return muxOp;
  };

  // For each of the loop, from the outermost to the innermost
  for (unsigned i = 0; i < numberOfLoops; i++) {

    // If we are in the innermost loop (thus the iterator is at its end)
    // and the consumer takes the value once per entry of that loop, stop
    if (i == numberOfLoops - 1 && oncePerLoopEntry)
      break;

    auto muxOp = createRegenMux(loops[i]);
    regeneratedValue = muxOp.getResult();
  }

  // Final replace the usage of the operand in the consumer with the output of
  // the last regen multiplexer created.
  consumerOp->replaceUsesOfWith(operand, regeneratedValue);
}

// ===--------------------------------------------------------------------=== //
// Suppression dispatch
// ===--------------------------------------------------------------------=== //

void ftd::addSuppOperandConsumer(mlir::OpBuilder &builder,
                                 handshake::FuncOp &funcOp,
                                 Operation *consumerOp, Value operand,
                                 ShadowCFG &shadow) {

  // Skip the prod-cons if the consumer is part of the operations related to
  // the BDD expansion or INIT merges
  if (consumerOp->hasAttr(FTD_OP_TO_SKIP) ||
      consumerOp->hasAttr(FTD_INIT_MERGE))
    return;

  // Do not take into account conditional branch
  if (llvm::isa<handshake::ConditionalBranchOp>(consumerOp) &&
      consumerOp->getOperand(0) != operand)
    return;

  // Read BB indices from handshake.bb attributes
  unsigned consBBIdx = 0;
  if (auto attr = consumerOp->getAttrOfType<IntegerAttr>("handshake.bb"))
    consBBIdx = attr.getUInt();

  unsigned prodBBIdx = 0;
  if (Operation *producerOp = operand.getDefiningOp())
    if (auto attr = producerOp->getAttrOfType<IntegerAttr>("handshake.bb"))
      prodBBIdx = attr.getUInt();

  // Map to shadow blocks for analysis
  Block *consumerBlock = shadow.getBlock(consBBIdx);
  Block *producerBlock = shadow.getBlock(prodBBIdx);

  // If the consumer and the producer are in the same block without the
  // consumer being a multiplexer skip because no delivery is needed
  if (consumerBlock == producerBlock &&
      (!llvm::isa<handshake::MuxOp>(consumerOp) ||
       (operand.getDefiningOp() &&
        operand.getDefiningOp()->hasAttr(FTD_EXPLICIT_GAMMA)))) {
    return;
  }

  // A function argument has no producer operation: it is produced in the
  // entry block, every time the function runs, and a consumer in a block the
  // entry does not always reach needs the token suppressed like any other.
  // (Before, everything below sat under `if (producerOp)`, and an argument
  // read inside a conditional block waited for ever at a join with a value
  // that was suppressed.)
  Operation *producerOp = operand.getDefiningOp();
  if (producerOp) {
    // A conditional branch already performs suppression on the value.
    // Do not insert another suppression unit after it.
    if (llvm::isa<handshake::ConditionalBranchOp>(producerOp))
      return;

    // Skip the prod-cons if the producer is part of the operations
    // related to the BDD expansion or INIT merges
    if (producerOp->hasAttr(FTD_OP_TO_SKIP) ||
        producerOp->hasAttr(FTD_INIT_MERGE))
      return;

    if (llvm::isa<handshake::MemoryControllerOp, handshake::LSQOp,
                  handshake::ControlMergeOp>(producerOp))
      return;
  }

  // Skip if the consumer is related to memory operations, is a conditional
  // branch, or the value is a memory reference
  if (llvm::isa_and_nonnull<handshake::MemoryControllerOp>(consumerOp) ||
      llvm::isa_and_nonnull<handshake::LSQOp>(consumerOp) ||
      llvm::isa_and_nonnull<handshake::ControlMergeOp>(consumerOp) ||
      llvm::isa_and_nonnull<handshake::ConditionalBranchOp>(consumerOp) ||
      llvm::isa_and_nonnull<cf::BranchOp>(consumerOp) ||
      (llvm::isa<memref::LoadOp>(consumerOp) &&
       !llvm::isa<handshake::LoadOp>(consumerOp)) ||
      (llvm::isa<memref::StoreOp>(consumerOp) &&
       !llvm::isa<handshake::StoreOp>(consumerOp)) ||
      llvm::isa<mlir::MemRefType>(operand.getType()))
    return;

  // Skip cf::CondBranchOp consumers unless this operand is the condition
  // input (operand 0) of the block's terminator.
  if (llvm::isa_and_nonnull<cf::CondBranchOp>(consumerOp) &&
      (consumerOp != consumerBlock->getTerminator() ||
       operand != consumerOp->getOperand(0)))
    return;

  // Handle the suppression in all the other cases, the operand being a
  // function argument included
  insertDirectSuppression(builder, funcOp, consumerOp, operand, shadow);
}

void ftd::addSupp(handshake::FuncOp &funcOp, mlir::OpBuilder &builder,
                  ShadowCFG &shadow) {

  // Set of original operations in the IR
  std::vector<Operation *> consumersToCover;
  for (Operation &consumerOp : funcOp.getOps())
    consumersToCover.push_back(&consumerOp);

  for (auto *consumerOp : consumersToCover) {
    for (auto operand : consumerOp->getOperands())
      addSuppOperandConsumer(builder, funcOp, consumerOp, operand, shadow);
  }
}

void ftd::addRegen(handshake::FuncOp &funcOp, mlir::OpBuilder &builder,
                   ShadowCFG &shadow) {

  // Set of original operations in the IR
  std::vector<Operation *> consumersToCover;
  for (Operation &consumerOp : funcOp.getOps())
    consumersToCover.push_back(&consumerOp);

  // For each producer/consumer relationship
  for (Operation *consumerOp : consumersToCover) {
    for (Value operand : consumerOp->getOperands())
      addRegenOperandConsumer(builder, funcOp, consumerOp, operand, shadow);
  }
}

// ===--------------------------------------------------------------------=== //
// GSA Gates
// ===--------------------------------------------------------------------=== //

LogicalResult experimental::ftd::addGsaGates(
    Region &region, PatternRewriter &rewriter, const gsa::GSAAnalysis &gsa,
    DenseMap<Value, SmallVector<Backedge, 2>> *pendingMuxOperands,
    bool removeTerminators) {

  using namespace experimental::gsa;
  BlockIndexing bi(region);

  // The function instantiates the GAMMA and MU gates as provided by the GSA
  // analysis pass. A GAMMA function is translated into a multiplexer driven by
  // single control signal and fed by two operands; a MU function is
  // translated into a multiplexer driven by an init. The input of one of these
  // functions might be another GSA function, and it's possible that the
  // function was not instantiated yet. For this reason, we keep track of the
  // missing operands, and reconnect them later on.
  //
  // To simplify the way GSA functions are handled, each of them has an unique
  // index.

  // This function operates in two modes:
  // (1) Called from handshake transformation passes where all values are
  // already handshake channels.
  // (2) Called early in CF-to-handshake conversion
  // when some CF values are still present.
  // The last two parameters distinguish the modes: for (1) they are
  // nullptr/false, for (2) they are non-null/true.
  //
  // In mode (1), no special management is needed: Muxes are inserted with all
  // connections finalized immediately.
  //
  // In mode (2), Mux operands are created as backedge placeholders. We maintain
  // a side structure mapping these placeholders to their corresponding
  // handshake values, which allows us to replace the backedges later, once the
  // handshake values are fully finalized. In case of Mux fed from a Mux tree,
  // the pendingMuxOperands is propoagated to the Mux decomposition tree to
  // store all cf values involved. In case the Mux is fed from a Merge only the
  // cf values feeding the Merge will be pushed to the pendingMuxOperands

  struct MissingGsa {
    // Index of the GSA function to modify
    unsigned phiIndex;
    // Index of the GSA function providing the result
    unsigned edgeIndex;
    // Index of the operand to modify
    unsigned operandInput;

    MissingGsa(unsigned pi, unsigned ei, unsigned oi)
        : phiIndex(pi), edgeIndex(ei), operandInput(oi) {}
  };

  if (region.getBlocks().size() == 1)
    return success();

  // A phi with a single operand is its operand, and no gate stands for it: its
  // uses take the value of the operand. This is done before any multiplexer is
  // created, so that a use moved onto the value of another gate is rerouted to
  // that gate's multiplexer together with the gate's own uses.
  for (Gate *phi : gsa.getSingleOperandPhis()) {
    GateInput *operand = phi->operands.front();
    Value replacement = operand->isTypeGate() ? operand->getGate()->result
                                              : operand->getValue();
    for (OpOperand &use : llvm::make_early_inc_range(phi->result.getUses()))
      rewriter.modifyOpInPlace(use.getOwner(), [&]() { use.set(replacement); });
  }

  // List of missing GSA functions
  SmallVector<MissingGsa> missingGsaList;
  // List of gammas with only one input
  DenseSet<Operation *> oneInputGammaList;
  // Maps the index of each GSA function to each real operation
  DenseMap<unsigned, Operation *> gsaList;

  // For each block excluding the first one, which has no GSA
  for (Block &block : llvm::drop_begin(region)) {

    // For each GSA function
    ArrayRef<Gate *> gates = gsa.getGatesPerBlock(&block);
    for (Gate *gate : gates) {

      Location loc = block.front().getLoc();
      rewriter.setInsertionPointToStart(&block);
      SmallVector<Value> operands;

      // Maintain the index of the current operand
      unsigned operandIndex = 0;
      // Checks whether one index is empty
      int nullOperand = -1;

      // For each of its operands
      for (auto *operand : gate->operands) {
        // If the input is another GSA function, then a dummy value is used as
        // operand and the operations will be reconnected later on.
        // If the input is empty, we keep track of its index.
        // In the other cases, we already have the operand of the function.
        if (operand->isTypeGate()) {
          Gate *g = std::get<Gate *>(operand->input);
          operands.emplace_back(g->result);
          missingGsaList.emplace_back(
              MissingGsa(gate->index, g->index, operandIndex));
        } else if (operand->isTypeEmpty()) {
          nullOperand = operandIndex;
          operands.emplace_back(nullptr);
        } else {
          auto val = std::get<Value>(operand->input);
          // If there is no risk that values are not finalized yet,
          // pendingMuxOperands will be a nullptr
          if (pendingMuxOperands == nullptr)
            operands.emplace_back(val);
          else {
            // Create backedge of the same type
            BackedgeBuilder beb(rewriter, block.front().getLoc());
            Backedge be = beb.get(ftd::channelifyType(val.getType()));
            // Use backedge as mux operand
            operands.emplace_back(be);
            // Remember how to resolve it later
            (*pendingMuxOperands)[val].push_back(be);
          }
        }
        operandIndex++;
      }

      // Get the condition for the block exiting
      Value conditionValue;

      // Determine the gate exit condition
      if (gate->gsaGateFunction == MuGate) {
        // For MU gates, we generate the condition based on the
        // reaching condition from the loop header back to itself.
        Block *loopHeader = gate->getBlock();
        conditionValue = computeLoopBackedgeCondition(
            rewriter, loopHeader, loopHeader, bi, pendingMuxOperands);

      } else {
        // [Gamma Logic]
        if (size(gate->cofactorList) > 1) {
          // Apply a BDD expansion to the loop exit expression and the list of
          // cofactors
          BDD *bdd = buildBDD(gate->condition, gate->cofactorList);
          // Convert the boolean expression obtained through BDD to a circuit
          // We pass an empty registry, since this is not an expression for
          // suppression and does not require distribution.
          SignalRegistry emptyRegistry;
          conditionValue =
              bddToCircuit(rewriter, bdd, gate->getBlock(), emptyRegistry, {},
                           bi, pendingMuxOperands);
        } else {
          // Use a SourceOp placeholder for the condition value, which will be
          // replaced with the actual condition input after every suppression
          // is done.
          conditionValue =
              getOrCreateCondPlaceholder(gate->conditionBlock, rewriter);
          // Ensure type consistency (Channel vs i1)
          if (!isa<handshake::ChannelType>(conditionValue.getType()))
            conditionValue.setType(channelifyType(conditionValue.getType()));
        }
      }

      // If the function is MU, then we create a merge
      // and use its result as condition
      if (gate->gsaGateFunction == MuGate) {
        mlir::DominanceInfo domInfo;
        mlir::CFGLoopInfo loopInfo(domInfo.getDomTree(&region));

        Operation *initOp;
        initOp = handshake::InitOp::create(rewriter, loc, conditionValue);

        initOp->setAttr(FTD_INIT_MERGE, rewriter.getUnitAttr());
        setBBAttr(initOp, gate->getBlock(), rewriter);

        // Replace the new condition value
        conditionValue = initOp->getResult(0);
        conditionValue.setType(channelifyType(conditionValue.getType()));
      }

      // When a single input gamma is encountered, a mux is inserted as a
      // placeholder to perform the gamma/mu allocation flow. In the end,
      // these multiplexers are erased from the IR
      if (nullOperand >= 0) {
        operands[0] = operands[1 - nullOperand];
        operands[1] = operands[1 - nullOperand];
      }

      // Create the multiplexer
      auto mux = handshake::MuxOp::create(
          rewriter, loc, ftd::channelifyType(gate->result.getType()),
          conditionValue, operands);

      // The one input gamma is marked as an operation to skip in the IR and
      // later removed
      if (nullOperand >= 0)
        oneInputGammaList.insert(mux);

      if (gate->isRoot) {
        // Reroute the uses IN PLACE, and do NOT ask the rewriter to replace
        // the value.
        //
        // `gate->result` is a block argument, and THIS FUNCTION deletes it --
        // every non-entry block's arguments are erased at the end, with the
        // raw `Block::eraseArguments`. So its lifetime is ours, and the two
        // things `replaceAllUsesWith` does are both wrong here:
        //
        //  - it does not rewrite the IR's uses. Under the reworked conversion
        //    driver, in rollback mode (the default), it records the
        //    replacement and leaves the operands alone; only the
        //    `allowPatternRollback = false` path replaces eagerly, which is
        //    what the old driver did for everyone and what this code was
        //    written against. The argument therefore still had every use when
        //    the erase came, and `eraseArguments` asserts on that.
        //  - and the record outlives the value. The driver replays it in
        //    `ReplaceValueRewrite::commit`, calling
        //    `findOrBuildReplacementValue` on an argument that was destroyed
        //    in between -- a null type, and a segfault.
        //
        // Rerouting through `modifyOpInPlace` tells the driver about the
        // operand change without registering anything that has to survive the
        // value. Same shape as `rerouteUsesIf` in
        // `LowerFuncToHandshake::flattenAndTerminate`, and correct in either
        // driver mode.
        for (OpOperand &use :
             llvm::make_early_inc_range(gate->result.getUses()))
          rewriter.modifyOpInPlace(use.getOwner(),
                                   [&]() { use.set(mux.getResult()); });
      }

      gsaList.insert({gate->index, mux});

      if (gate->gsaGateFunction == MuGate)
        mux->setAttr(FTD_EXPLICIT_MU, rewriter.getUnitAttr());
      else
        mux->setAttr(FTD_EXPLICIT_GAMMA, rewriter.getUnitAttr());
    }
  }

  // For each of the GSA missing inputs, perform a replacement
  for (auto &missingMerge : missingGsaList) {

    auto *operandMerge = gsaList[missingMerge.phiIndex];
    auto *resultMerge = gsaList[missingMerge.edgeIndex];

    operandMerge->setOperand(missingMerge.operandInput + 1,
                             resultMerge->getResult(0));

    // In case of a one-input gamma, the other input must be replaced as well,
    // to avoid errors when the block arguments are erased later on
    if (oneInputGammaList.contains(operandMerge))
      operandMerge->setOperand(2 - missingMerge.operandInput,
                               resultMerge->getResult(0));
  }

  // Get rid of the multiplexers adopted as place-holders of one input gamma
  for (auto &op : llvm::make_early_inc_range(oneInputGammaList)) {
    int operandToUse = llvm::isa_and_nonnull<handshake::MuxOp>(
                           op->getOperand(1).getDefiningOp())
                           ? 1
                           : 2;
    op->getResult(0).replaceAllUsesWith(op->getOperand(operandToUse));

    for (auto &[idx, mappedOp] : gsaList) {
      if (mappedOp == op)
        mappedOp = nullptr;
    }
    rewriter.eraseOp(op);
  }

  // Simplify the generated GSA Mux tree by applying common subexpression
  // elimination and reduction rules from the bottom up. A reverse mapping
  // resolves temporary backedge placeholders to their original CFG values
  // ensuring equivalent inputs are correctly identified across different
  // branches.
  DenseMap<Value, Value> backedgeToOriginal;
  if (pendingMuxOperands) {
    for (auto &[orig, bes] : *pendingMuxOperands) {
      for (auto &be : bes) {
        backedgeToOriginal[Value(be)] = orig;
      }
    }
  }

  // Helper functions evaluate the structural equivalence of two values.
  // Equivalence is based on Value identity (SSA identity): two Values are
  // equivalent iff they are the same SSA wire. Backedge placeholders are
  // resolved to their original CF values first.
  auto getEffectiveValue = [&](Value v) -> Value {
    if (!v)
      return v;
    auto it = backedgeToOriginal.find(v);
    if (it != backedgeToOriginal.end())
      return it->second;
    return v;
  };

  auto areEquivalentValues = [&](Value a, Value b) {
    if (a == b)
      return true;
    if (!a || !b)
      return false;

    Value effA = getEffectiveValue(a);
    Value effB = getEffectiveValue(b);
    return effA == effB;
  };

  // Two identical gammas are merged only when they are consumed under the same
  // conditions. The gammas of a tree are in one block and take no suppression
  // from one another: the token of a gamma goes to every mux its result feeds,
  // and each of them must take it on every execution which produces it. A
  // gamma is consumed when the mux it feeds is and that mux's select takes the
  // gamma's side; a root (a gamma feeding anything but a gate of its own block)
  // and a MU are consumed on every execution of their block. Merging two gammas
  // consumed under different conditions -- the sub-gamma of a block reached on
  // two routes of the tree, below two parents, or the roots of two blocks --
  // feeds a mux which, on some execution, takes nothing: a token is left, or
  // the circuit deadlocks.
  //
  // A mux whose two inputs are the same tree is not counted: the reduction
  // below bypasses it, and the two copies below it, merged, take its place. Two
  // trees are the same when their selects and their inputs are, once these
  // muxes are bypassed. The merges and the reductions below change neither the
  // trees nor the conditions, which are therefore computed once, here.
  DenseSet<Operation *> liveGates;
  for (auto &[idx, op] : gsaList)
    if (op)
      liveGates.insert(op);

  // getTree gives two values the same number when they are the same value, or
  // the same tree of gammas of `block`. Any other value, a MU among them, is a
  // leaf. The first number stands for the selects of the MUs of a block: each
  // MU has its own, but all of them take their initial input on the first
  // iteration of an entry in the loop, and their loop input on the next ones.
  unsigned numTrees = 0;
  unsigned muSelect = numTrees++;
  DenseMap<Value, unsigned> treePerLeaf;
  DenseMap<std::tuple<unsigned, unsigned, unsigned>, unsigned> treePerShape;
  DenseMap<Operation *, unsigned> treePerGamma;
  std::function<unsigned(Value, Block *)> getTree = [&](Value v, Block *block) {
    Operation *defOp = v.getDefiningOp();
    if (defOp && defOp->getBlock() == block && liveGates.contains(defOp) &&
        defOp->hasAttr(FTD_EXPLICIT_GAMMA)) {
      if (auto it = treePerGamma.find(defOp); it != treePerGamma.end())
        return it->second;
      auto mux = cast<handshake::MuxOp>(defOp);
      unsigned select = getTree(mux.getSelectOperand(), block);
      unsigned in0 = getTree(mux.getDataOperands()[0], block);
      unsigned in1 = getTree(mux.getDataOperands()[1], block);
      unsigned tree = in0;
      if (in0 != in1) {
        auto [it, inserted] =
            treePerShape.try_emplace({select, in0, in1}, numTrees);
        if (inserted)
          ++numTrees;
        tree = it->second;
      }
      treePerGamma[defOp] = tree;
      return tree;
    }
    auto [it, inserted] =
        treePerLeaf.try_emplace(getEffectiveValue(v), numTrees);
    if (inserted)
      ++numTrees;
    return it->second;
  };

  // getConsumption returns the conditions under which a gamma is consumed: its
  // block, and the side taken at each select on the way from the root, as the
  // tree of the select and the operand index of the side. It returns none when
  // two muxes the gamma feeds would consume it under different conditions.
  using Consumption =
      std::pair<Block *, SmallVector<std::pair<unsigned, unsigned>>>;
  DenseMap<Operation *, std::optional<Consumption>> consumptionPerGamma;
  std::function<std::optional<Consumption>(Operation *)> getConsumption =
      [&](Operation *gamma) -> std::optional<Consumption> {
    if (auto it = consumptionPerGamma.find(gamma);
        it != consumptionPerGamma.end())
      return it->second;
    // A gamma met again on the way to its root has no root, and stays unknown.
    consumptionPerGamma[gamma] = std::nullopt;
    Block *block = gamma->getBlock();
    std::optional<Consumption> consumption;
    for (OpOperand &use : gamma->getResult(0).getUses()) {
      // A placeholder of a one-input gamma, erased above, keeps its operands
      // while the conversion rewriter defers the erasure, so its uses are
      // skipped.
      if (oneInputGammaList.contains(use.getOwner()))
        continue;
      std::optional<Consumption> useConsumption = Consumption{block, {}};
      auto parent = dyn_cast<handshake::MuxOp>(use.getOwner());
      if (parent && parent->getBlock() == block && liveGates.contains(parent) &&
          use.getOperandNumber() > 0) {
        if (!parent->hasAttr(FTD_EXPLICIT_MU))
          useConsumption = getConsumption(parent);
        bool testsNothing = getTree(parent.getDataOperands()[0], block) ==
                            getTree(parent.getDataOperands()[1], block);
        if (useConsumption && !testsNothing) {
          std::pair<unsigned, unsigned> side(
              parent->hasAttr(FTD_EXPLICIT_MU)
                  ? muSelect
                  : getTree(parent.getSelectOperand(), block),
              use.getOperandNumber());
          auto &sides = useConsumption->second;
          sides.insert(llvm::upper_bound(sides, side), side);
        }
      }
      if (!useConsumption || (consumption && *consumption != *useConsumption))
        return std::nullopt;
      consumption = useConsumption;
    }
    if (!consumption)
      consumption = Consumption{block, {}};
    consumptionPerGamma[gamma] = consumption;
    return consumption;
  };

  // The GSA analysis builds every gamma tree with a new gate per input, so each
  // gamma feeds one parent and its consumption is known. If the consumption of
  // one gamma cannot be read (two muxes would consume it under different
  // conditions before anything is merged, or the gammas form a cycle), every
  // merge in the function is refused, the safe ones included.
  bool canMerge = true;
  for (Operation *op : liveGates)
    if (op->hasAttr(FTD_EXPLICIT_GAMMA) && !getConsumption(op))
      canMerge = false;
  auto areConsumedAlike = [&](Operation *a, Operation *b) {
    if (!canMerge || !a->hasAttr(FTD_EXPLICIT_GAMMA) ||
        !b->hasAttr(FTD_EXPLICIT_GAMMA))
      return false;
    return *consumptionPerGamma.lookup(a) == *consumptionPerGamma.lookup(b);
  };

  // Iterate through the generated operations until the tree structure fully
  // converges. The first step performs common subexpression elimination by
  // scanning horizontally across all generated multiplexers. Whenever two
  // distinct multiplexers share identical selection conditions and data
  // inputs and are consumed under the same conditions, they are merged into a
  // single operation to eliminate structural duplication.
  bool changed = true;
  while (changed) {
    changed = false;

    for (auto it1 = gsaList.begin(); it1 != gsaList.end(); ++it1) {
      if (!it1->second)
        continue;
      auto mux1 = dyn_cast<handshake::MuxOp>(it1->second);
      if (!mux1 || mux1.getNumOperands() != 3)
        continue;

      for (auto it2 = std::next(it1); it2 != gsaList.end(); ++it2) {
        if (!it2->second)
          continue;
        auto mux2 = dyn_cast<handshake::MuxOp>(it2->second);
        if (!mux2 || mux2.getNumOperands() != 3)
          continue;

        if (areEquivalentValues(mux1.getSelectOperand(),
                                mux2.getSelectOperand()) &&
            areEquivalentValues(mux1.getDataOperands()[0],
                                mux2.getDataOperands()[0]) &&
            areEquivalentValues(mux1.getDataOperands()[1],
                                mux2.getDataOperands()[1]) &&
            areConsumedAlike(mux1, mux2)) {

          mux2.getResult().replaceAllUsesWith(mux1.getResult());
          rewriter.eraseOp(mux2);
          it2->second = nullptr;
          changed = true;
        }
      }
    }

    // The second step applies the reduction rule by scanning vertically
    // through the tree. Any multiplexer whose true and false data inputs
    // resolve to the same underlying value is fundamentally redundant and
    // is bypassed entirely by routing its data input directly to its users.
    for (auto &[idx, op] : gsaList) {
      if (!op)
        continue;
      auto mux = dyn_cast<handshake::MuxOp>(op);
      if (!mux || mux.getNumOperands() != 3)
        continue;

      if (areEquivalentValues(mux.getDataOperands()[0],
                              mux.getDataOperands()[1])) {
        mux.getResult().replaceAllUsesWith(mux.getDataOperands()[0]);
        rewriter.eraseOp(mux);
        op = nullptr;
        changed = true;
      }
    }
  }

  if (!removeTerminators)
    return success();

  // Remove all the block arguments for all the non starting blocks
  for (Block &block : llvm::drop_begin(region))
    block.eraseArguments(0, block.getArguments().size());

  // Each terminator must be replaced so that it does not provide any block
  // arguments (possibly only the final control argument)
  for (Block &block : region) {
    if (Operation *terminator = block.getTerminator(); terminator) {
      rewriter.setInsertionPointAfter(terminator);
      if (auto cbr = dyn_cast<cf::CondBranchOp>(terminator); cbr) {
        while (!cbr.getTrueOperands().empty())
          cbr.eraseTrueOperand(0);
        while (!cbr.getFalseOperands().empty())
          cbr.eraseFalseOperand(0);
      } else if (auto br = dyn_cast<cf::BranchOp>(terminator); br) {
        while (!br.getOperands().empty())
          br.eraseOperand(0);
      }
    }
  }

  return success();
}

LogicalResult ftd::replaceMergeToGSA(handshake::FuncOp &funcOp,
                                     PatternRewriter &rewriter) {

  // For each merge that was signed with the `NEW_PHI` attribute, substitute
  // it with its GSA equivalent
  for (handshake::MergeOp merge :
       llvm::make_early_inc_range(funcOp.getOps<handshake::MergeOp>())) {
    if (!merge->hasAttr(NEW_PHI))
      continue;
    gsa::GSAAnalysis gsa(merge, funcOp.getRegion());
    if (gsa.hasFailed())
      return failure();
    if (failed(ftd::addGsaGates(funcOp.getRegion(), rewriter, gsa, nullptr,
                                false)))
      return failure();

    // Get rid of the merge
    merge.erase();
  }

  return success();
}
