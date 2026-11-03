//===- GSAAnalysis.cpp - GSA analyis utilities ------------------*- C++ -*-===//
//
// Dynamatic is under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// Implements some utility functions useful towards converting the static single
// assignment (SSA) representation into gated single assignment representation
// (GSA).
//
//===----------------------------------------------------------------------===//

#include "experimental/Analysis/GSAAnalysis.h"
#include "experimental/Support/BooleanLogic/BDD.h"
#include "experimental/Support/FtdSupport.h"
#include "mlir/Analysis/CFGLoopInfo.h"
#include "mlir/Dialect/ControlFlow/IR/ControlFlowOps.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/Dominance.h"
#include "mlir/Transforms/DialectConversion.h"
#include "vector"
#include "llvm/Support/Debug.h"
#include <algorithm>

#define DEBUG_TYPE "gsa"

using namespace mlir;
using namespace dynamatic;
using namespace dynamatic::experimental::ftd;
using namespace dynamatic::experimental::boolean;

experimental::gsa::GSAAnalysis::GSAAnalysis(handshake::MergeOp &merge,
                                            Region &region) {
  inputOp = &region;
  convertSSAToGSAMerges(merge, region);
}

void experimental::gsa::GSAAnalysis::convertSSAToGSAMerges(
    handshake::MergeOp &mergeOp, Region &region) {

  // Associate an index to each basic block in "funcOp" so that if Bi
  // dominates Bj than i < j
  BlockIndexing bi(region);

  // Initialize the index of the class
  uniqueGateIndex = 0;

  Block *block = mergeOp.getResult().getParentBlock();

  // Create an empty list for the phi functions corresponding to the block
  gatesPerBlock.insert({block, llvm::SmallVector<Gate *>()});

  // Create a set for the operands of the corresponding phi function
  SmallVector<GateInput *> operands;

  auto isAlreadyPresent = [&](Value c) -> bool {
    return std::any_of(operands.begin(), operands.end(), [c](GateInput *in) {
      return in->isTypeValue() && in->getValue() == c;
    });
  };

  // Add to the list of operands of the new gate all the values which were not
  // already used.
  // Since in STQ one block can't be producer of more than one phi operand,
  // sender logic is not needed.

  // Handle self-dependent merges: if the merge uses its own result as an input,
  // record that operand so it can be reconnected to the generated phi later.
  SmallVector<GateInput *> selfInputs;

  for (Value v : mergeOp.getOperands()) {
    if (!isAlreadyPresent(v)) {
      GateInput *gateInput = new GateInput(v);
      if (v == mergeOp.getResult())
        selfInputs.push_back(gateInput);
      gateInputList.push_back(gateInput);
      operands.push_back(gateInput);
    }
  }

  // If the list of operands is not empty (i.e. the phi has at least
  // one input), add it to the phis associated to that block
  Gate *newPhi = nullptr;
  if (!operands.empty()) {
    newPhi = new Gate(mergeOp.getResult(), operands, GateType::PhiGate,
                      ++uniqueGateIndex);
    gatesPerBlock[block].push_back(newPhi);
  }

  // Reconnect self-dependent operands to the newly created Phi
  for (GateInput *gi : selfInputs)
    gi->input = newPhi;

  convertPhiToMu(region, bi);
  convertPhiToGamma(region, bi);

  // A failed conversion leaves phis which gammas still refer to: the gates are
  // not to be used, and are only deleted
  if (analysisFailed)
    return;

  // After the conversion is done, `gatesPerBlock` will contain some phis, some
  // MUs and some GAMMAs. Since we are only interested in the last two, we can
  // remove all the phis.
  removePhiGates(region);
  printAllGates(region);
}

experimental::gsa::GSAAnalysis::GSAAnalysis(Operation *operation) {

  // Only one function should be present in the module, excluding external
  // functions
  unsigned functionsCovered = 0;

  // TODO: Extend to support multiple functions

  // The analysis can be instantiated either over a module containing one
  // function only or over a function
  if (ModuleOp modOp = dyn_cast<ModuleOp>(operation); modOp) {
    for (func::FuncOp funcOp : modOp.getOps<func::FuncOp>()) {

      // Skip if external
      if (funcOp.isExternal())
        continue;

      // Analyze the function
      if (!functionsCovered) {
        inputOp = &funcOp.getRegion();
        convertSSAToGSA(*inputOp);
        functionsCovered++;
      } else {
        llvm::errs() << "[GSA] Too many functions to handle in the module";
      }
    }
  } else if (func::FuncOp fOp = dyn_cast<func::FuncOp>(operation); fOp) {
    convertSSAToGSA(fOp.getRegion());
    functionsCovered = 1;
  }

  // report an error indicating that the analysis is instantiated over
  // an inappropriate operation
  if (functionsCovered != 1)
    llvm::errs() << "[GSA] GSAAnalysis failed due to a wrong input type\n";
}

void experimental::gsa::GSAAnalysis::emitGammaTreeError(Gate *phi,
                                                        StringRef reason) {
  mlir::emitError(phi->result.getLoc())
      << "fast token delivery cannot build the gamma tree of this block "
         "argument: "
      << reason
      << " (the analysis supports cf.cond_br branches with two distinct "
         "successors, in reducible control flow)";
  analysisFailed = true;
}

experimental::gsa::Gate *experimental::gsa::GSAAnalysis::expandGammaTree(
    ListExpressionsPerGate &expressions, std::queue<unsigned> conditions,
    Gate *originalPhi, const BlockIndexing &bi) {

  // At each iteration, we want to use a cofactor that is present in all the
  // expressions in `expressions`. This holds in a reducible CFG whose
  // conditional branches are cf.cond_br with two distinct successors (the pass
  // splits a branch reaching one block on both edges with two values). The
  // cofactors are ordered according to the block indexing, a topological order
  // of the CFG without its back edges, and the expression of an input is the
  // sum of the paths reaching the phi through one of its senders, which take no
  // back edge. Restricted on the cofactors already expanded:
  // - every execution which remains traverses the block of the first cofactor
  //   some expression uses: an execution avoiding it, completed after that
  //   block as one which the cofactor changes, would leave every expression
  //   unchanged when the cofactor flips;
  // - an expression not using that cofactor would select its input from both
  //   successors of the block under the same conditions; the executions from
  //   either successor would then all traverse the first block that selection
  //   depends on, and from there on reach the same input, so that no
  //   expression would use the cofactor.
  // A cf.switch (whose edges carry no condition) or an irreducible cycle
  // breaks this, and the analysis fails with an error.
  unsigned indexToUse;
  std::string conditionToUse;
  while (true) {
    if (conditions.empty()) {
      emitGammaTreeError(originalPhi,
                         "no branch condition tells its inputs apart");
      return nullptr;
    }
    indexToUse = conditions.front();
    conditionToUse = "c" + std::to_string(indexToUse);
    conditions.pop();
    unsigned cofactorUsage =
        std::count_if(expressions.begin(), expressions.end(),
                      [&](std::pair<BoolExpression *, GateInput *> g) {
                        return g.first->containsMintern(conditionToUse);
                      });

    // None is using that cofactor, go to the next one
    if (cofactorUsage == 0)
      continue;

    // All are using the cofactor, expand the expressions over it
    if (cofactorUsage == expressions.size())
      break;

    emitGammaTreeError(
        originalPhi, "a branch condition tells only some of its inputs apart");
    return nullptr;
  }

  ListExpressionsPerGate conditionsFalseExpressions;
  ListExpressionsPerGate conditionsTrueExpressions;

  // For each expression
  for (const auto &expression : expressions) {

    // Restrict an expression according to a condition ans an input boolean
    // value and return it
    auto getRestrictedExpression = [&](bool value) -> BoolExpression * {
      BoolExpression *expr = expression.first->deepCopy();
      restrict(expr, conditionToUse, value);
      return expr->boolMinimize();
    };

    // Substitute a condition in the expression both with value true and false
    BoolExpression *exprTrue = getRestrictedExpression(true);
    BoolExpression *exprFalse = getRestrictedExpression(false);

    // One of the two expressions above will be zero: add the input to the
    // corresponding list
    if (exprTrue->type != ExpressionType::Zero)
      conditionsTrueExpressions.emplace_back(exprTrue, expression.second);
    if (exprFalse->type != ExpressionType::Zero)
      conditionsFalseExpressions.emplace_back(exprFalse, expression.second);
  }

  SmallVector<GateInput *> operandsGamma(2);

  // If the number of non-null expressions obtained with cofactor = X is greater
  // than 1, then the expansions must be done again over those inputs with a new
  // cofactor. The resulting gamma is going to be used as X input of this
  // gamma.
  //
  // If only one element is present, that same element is used as input of the
  // gamma.
  //
  // If no elements are present, then that input will never be used, and it is
  // considered as empty.
  auto setGammaOperand = [&](int input, ListExpressionsPerGate &list) -> bool {
    if (list.size() > 1) {
      Gate *gamma = expandGammaTree(list, conditions, originalPhi, bi);
      if (!gamma)
        return false;
      operandsGamma[input] = new GateInput(gamma);
      gateInputList.push_back(operandsGamma[input]);
    } else if (list.size() == 1) {
      operandsGamma[input] = list[0].second;
    } else {
      operandsGamma[input] = new GateInput();
      gateInputList.push_back(operandsGamma[input]);
    }
    return true;
  };

  if (!setGammaOperand(1, conditionsTrueExpressions) ||
      !setGammaOperand(0, conditionsFalseExpressions))
    return nullptr;

  // Create a new gamma and add it to the list of phis for the original basic
  // block.

  // Get the index of the condition (it is associated to a basic block in
  // "indexPerBlock" mapping)
  Gate *newGate = new Gate(
      originalPhi->result, operandsGamma, GateType::GammaGate,
      ++uniqueGateIndex, bi.getBlockFromIndex(indexToUse).value(),
      BoolExpression::boolVar(conditionToUse),
      {conditionToUse}); // since condition is one block boolvar is enough
  gatesPerBlock[originalPhi->getBlock()].push_back(newGate);

  return newGate;
}

void experimental::gsa::GSAAnalysis::convertSSAToGSA(Region &region) {

  if (region.getBlocks().size() == 1)
    return;

  // Associate an index to each basic block in "funcOp" so that if Bi
  // dominates Bj than i < j
  BlockIndexing bi(region);

  // This function works in two steps. First, all the block arguments in the
  // IR are converted into PHIs, taking care or properly extracting the
  // information about the producers of the operands. Then, the phis are
  // converted either to GAMMAs or MUs.

  // The input of a phi might be another gate. This is the case when the
  // input of a phi is a block argument from a block with index different
  // from 0. In this situation, we mark the phi input as "missing", and we
  // store the necessary information (block argument) to later reconstruct
  // the relationship.
  struct MissingPhi {

    // Which input is missing
    GateInput *pi;

    // Related block argument
    BlockArgument blockArg;

    MissingPhi(GateInput *pi, BlockArgument blockArg)
        : pi(pi), blockArg(blockArg) {}
  };

  // Initialize the index of the class
  uniqueGateIndex = 0;

  // Vector to store all the missing phi
  SmallVector<MissingPhi> phisToConnect;

  mlir::DominanceInfo domInfo;

  // For each block in the function
  for (Block &block : region.getBlocks()) {

    // Create an empty list for the phi functions corresponding to the block
    gatesPerBlock.insert({&block, llvm::SmallVector<Gate *>()});

    // For each block argument
    for (BlockArgument &arg : block.getArguments()) {
      unsigned argNumber = arg.getArgNumber();
      // Create a set for the operands of the corresponding phi function
      SmallVector<GateInput *> operands;
      // Track block-argument operands to avoid recording duplicates
      SmallVector<MissingPhi> operandsMissPhi;
      DenseSet<Block *> coveredPredecessors;
      // For each predecessor of the block, which is in charge of
      // providing the inputs of the phi functions
      for (Block *pred : block.getPredecessors()) {

        // An unreachable predecessor sends nothing
        if (!domInfo.isReachableFromEntry(pred))
          continue;

        // Make sure that a predecessor is covered only once
        if (coveredPredecessors.contains(pred))
          continue;
        coveredPredecessors.insert(pred);

        // Get the branch terminator
        auto branchOp = dyn_cast<BranchOpInterface>(pred->getTerminator());
        assert(branchOp && "Expected terminator operation in a predecessor "
                           "block feeding a block argument!");

        // Check if a block-argument operand is already present among missing
        // phis. Two missing-phi operands are considered equal if they
        // originated from and target the same argument of the same block.
        // The value is not compared, which might be problematic.
        auto isBlockArgAlreadyPresent = [&](BlockArgument blockArg) -> bool {
          for (MissingPhi &mPhi : operandsMissPhi) {
            if (mPhi.blockArg.getParentBlock() == blockArg.getParentBlock() &&
                mPhi.blockArg.getArgNumber() == blockArg.getArgNumber()) {
              mPhi.pi->senders.insert(pred);
              return true;
            }
          }
          return false;
        };

        // Check if value is already among the operands of the phi.
        // If found, record preds as a sender of that operand.
        auto isValueAlreadyPresent = [&](Value v) -> bool {
          for (GateInput *in : operands) {
            if (in->isTypeValue() && in->getValue() == v) {
              in->senders.insert(pred);
              return true;
            }
          }
          return false;
        };

        // For each alternative in the branch terminator
        for (auto [successorId, successorBlock] :
             llvm::enumerate(branchOp->getSuccessors())) {

          // Skip the successor if it is not the block under analysis
          if (successorBlock != &block)
            continue;

          // Get the values used for that branch
          auto successorOperands = branchOp.getSuccessorOperands(successorId);
          // Get the value used as input of the gate
          Value producer = successorOperands[argNumber];
          GateInput *gateInput = nullptr;

          /// If it is a block argument whose parent block has some predecessor,
          /// then the value is the output of a phi, and we add it to the list
          /// of missing phis. Otherwise, the input is a value, and it can be
          /// safely added directly.
          if (BlockArgument blockArg = dyn_cast<BlockArgument>(producer);
              blockArg && !producer.getParentBlock()->hasNoPredecessors()) {
            if (!isBlockArgAlreadyPresent(blockArg)) {
              gateInput = new GateInput((Gate *)nullptr);
              MissingPhi missingPhi = MissingPhi(gateInput, blockArg);
              missingPhi.pi->senders.insert(pred);
              phisToConnect.push_back(missingPhi);
              gateInputList.push_back(gateInput);
              operandsMissPhi.push_back(missingPhi);
            }
          } else {
            if (!isValueAlreadyPresent(dyn_cast<Value>(producer))) {
              gateInput = new GateInput(producer);
              gateInput->senders.insert(pred);
              gateInputList.push_back(gateInput);
            }
          }

          // Insert the value among the inputs of the phi
          if (gateInput)
            operands.push_back(gateInput);

          break;
        }
      }

      // If the list of operands is not empty (i.e. the phi has at least
      // one input), add it to the phis associated to that block
      if (!operands.empty()) {
        Gate *newPhi =
            new Gate(arg, operands, GateType::PhiGate, ++uniqueGateIndex);
        gatesPerBlock[&block].push_back(newPhi);
      }
    }
  }

  // Find the missing phi and correct the pointers
  for (MissingPhi &missing : phisToConnect) {
    auto list = gatesPerBlock[missing.blockArg.getParentBlock()];
    Gate **foundGate = std::find_if(list.begin(), list.end(),
                                    [&](Gate *&t) {
                                      return t->getArgumentNumber() ==
                                             missing.blockArg.getArgNumber();
                                    }

    );
    assert(foundGate != list.end() && "[GSA] Not found phi to reconnect");
    missing.pi->input = *foundGate;
  }

  convertPhiToMu(region, bi);
  convertPhiToGamma(region, bi);

  // A failed conversion leaves phis which gammas still refer to: the gates are
  // not to be used, and are only deleted
  if (analysisFailed)
    return;

  // After the conversion is done, `gatesPerBlock` will contain some phis, some
  // MUs and some GAMMAs. Since we are only interested in the last two, we can
  // remove all the phis.
  removePhiGates(region);
  printAllGates(region);
}

void experimental::gsa::GSAAnalysis::replaceGateInput(
    Gate *gate, std::variant<Value, Gate *> input) {
  for (auto &[bb, gates] : gatesPerBlock) {
    for (Gate *g : gates) {
      for (GateInput *op : g->operands) {
        if (op->isTypeGate() && op->getGate() == gate)
          op->input = input;
      }
    }
  }
}

experimental::gsa::ListExpressionsPerGate
experimental::gsa::GSAAnalysis::getExpressionsFromSenders(
    Gate *phi, DenseSet<unsigned> &conditions, const BlockIndexing &bi,
    mlir::DominanceInfo &domInfo) {

  // The phi takes an operand exactly when it is reached from one of the
  // operand's senders, wherever the operand is produced: a value may be
  // produced in a block dominating the blocks of the other operands (a
  // function argument, or a value passed unchanged through some blocks), or
  // on their paths. The paths are thus taken from the nearest common dominator
  // of the senders, which every execution reaching the phi through them
  // traverses, to the phi, and each path belongs to the operand having the
  // last block before the phi among its senders. In a reducible CFG, no such
  // path takes a back edge (a path into a loop through its header would have
  // to come back through the common dominator), except the edge into the phi
  // from a latch when the phi gathers the loop inputs of a MU.
  Block *commonDominator = nullptr;
  bool firstSender = true;
  for (GateInput *operand : phi->operands) {
    for (Block *sender : operand->senders) {
      commonDominator =
          firstSender
              ? sender
              : domInfo.findNearestCommonDominator(commonDominator, sender);
      firstSender = false;
    }
  }
  assert(commonDominator && "The senders of a phi have a common dominator");

  ListExpressionsPerGate expressions;
  for (GateInput *operand : phi->operands)
    expressions.emplace_back(BoolExpression::boolZero(), operand);

  for (std::vector<Block *> &path :
       findAllPaths(commonDominator, phi->getBlock(), bi)) {

    // A path reaching the phi from a block which sends none of the operands
    // (a phi gathering the inputs of a MU from one side of its loop) does not
    // count
    Block *sender = path[path.size() - 2];
    auto expression = llvm::find_if(expressions, [&](auto &e) {
      return e.second->senders.count(sender) != 0;
    });
    if (expression == expressions.end())
      continue;

    // Sum the condition of the path to the expression of its operand
    BoolExpression *pathCondition = getPathExpression(path, conditions, bi);
    expression->first = BoolExpression::boolOr(pathCondition, expression->first)
                            ->boolMinimize();
  }

  return expressions;
}

experimental::gsa::ListExpressionsPerGate
experimental::gsa::GSAAnalysis::getExpressionsFromProducers(
    Gate *phi, DenseSet<unsigned> &conditions, const BlockIndexing &bi,
    mlir::DominanceInfo &domInfo) {

  // Sort the operands of the phi so that Bi comes before Bj if Bi dominates
  // Bj. The block indexing is such an order; dominance itself is not a strict
  // weak ordering, and cannot be the comparator of a sort.
  SmallVector<GateInput *> phiOperands = phi->operands;
  llvm::stable_sort(phiOperands, [&](GateInput *a, GateInput *b) {
    return bi.isLess(a->getBlock(), b->getBlock());
  });

  // Find the nearest common dominator among all the blocks involved
  // in the phi inputs. Also add all the blocks to the list of 'blocks to
  // avoid'
  std::vector<Block *> blocksToAvoid = {phiOperands[0]->getBlock()};
  Block *commonDominator = phiOperands[0]->getBlock();
  for (GateInput *operand : llvm::drop_begin(phiOperands)) {
    Block *bb = operand->getBlock();
    commonDominator = domInfo.findNearestCommonDominator(bb, commonDominator);
    blocksToAvoid.push_back(bb);
  }

  // Vector associating each input of the Phi to a boolean expression
  ListExpressionsPerGate expressions;

  // For each input of the phi, compute the boolean expression which defines
  // its usage
  for (GateInput *operand : phiOperands) {

    // Remove the current operand from the list of blocks to avoid
    blocksToAvoid.erase(blocksToAvoid.begin());

    // Find all the paths from "commonDominator" to "phiBlock" which pass
    // through operand's block but not through any of the "blocksToAvoid"
    auto paths = findAllPaths(commonDominator, phi->getBlock(), bi,
                              operand->getBlock(), blocksToAvoid);

    BoolExpression *phiInputCondition = BoolExpression::boolZero();

    // Sum all the conditions for each path
    for (std::vector<Block *> &path : paths) {
      boolean::BoolExpression *condition =
          getPathExpression(path, conditions, bi);
      phiInputCondition = BoolExpression::boolOr(condition, phiInputCondition);
      phiInputCondition = phiInputCondition->boolMinimize();
    }

    // Associate the expression to the phi operand
    expressions.emplace_back(phiInputCondition, operand);
  }

  return expressions;
}

void experimental::gsa::GSAAnalysis::convertPhiToGamma(
    Region &region, const BlockIndexing &bi) {

  mlir::DominanceInfo domInfo;

  // For each block, in the order of the region: the order of `gatesPerBlock`,
  // keyed by pointers, changes from one run to the next, and so would the
  // indices of the gates
  auto gatesSnapshot = gatesPerBlock;
  for (Block &block : region) {
    Block *phiBlock = &block;

    // For each phi
    for (Gate *phi : gatesSnapshot.lookup(phiBlock)) {

      // Skip if the phi is not of type `Phi`
      if (phi->gsaGateFunction != PhiGate)
        continue;

      // A phi with a single operand is its operand: the gates which take the
      // phi as input take the operand instead
      if (phi->operands.size() == 1) {
        replaceGateInput(phi, phi->operands.front()->input);
        continue;
      }

      // When traversing a path, some blocks have a condition which steers the
      // control flow execution. This set stores the list of the blocks
      // accordingly. They will become boolean conditions afterwards
      DenseSet<unsigned> blocksWithConditionInPath;

      // Associate each input of the phi to the boolean expression of the
      // condition under which the phi takes it. The inputs of a phi obtained
      // from block arguments have their senders; the ones of a phi obtained
      // from a merge have none, and their producer blocks are used instead.
      bool fromSenders = !phi->operands.front()->senders.empty();
      assert(llvm::all_of(phi->operands,
                          [&](GateInput *operand) {
                            return operand->senders.empty() != fromSenders;
                          }) &&
             "Either all or none of the inputs of a phi have senders");
      ListExpressionsPerGate expressionsList =
          fromSenders
              ? getExpressionsFromSenders(phi, blocksWithConditionInPath, bi,
                                          domInfo)
              : getExpressionsFromProducers(phi, blocksWithConditionInPath, bi,
                                            domInfo);
      assert(llvm::none_of(expressionsList,
                           [](auto &e) {
                             return e.first->type == ExpressionType::Zero;
                           }) &&
             "A phi input is taken under no condition");

      // Get a queue with all the necessary conditions, ordered according to
      // their basic block index
      std::vector<unsigned> conditionsToOrder;
      for (unsigned &index : blocksWithConditionInPath)
        conditionsToOrder.push_back(index);
      std::sort(conditionsToOrder.begin(), conditionsToOrder.end());
      std::queue<unsigned> conditionsOrdered;
      for (unsigned &index : conditionsToOrder)
        conditionsOrdered.push(index);

      // Expand the expressions to get the tree of gammas
      Gate *gammaRoot =
          expandGammaTree(expressionsList, conditionsOrdered, phi, bi);
      if (!gammaRoot)
        return;
      gammaRoot->isRoot = true;

      // Once that a phi has been converted into a tree of gammas, all the
      // gates which used the original phi as input must be connected to the
      // root of the gamma tree
      replaceGateInput(phi, gammaRoot);
    }
  }
}

static bool IsBlockInLoop(Block *block, CFGLoop *loop, mlir::CFGLoopInfo &li) {
  for (CFGLoop *blockLoop = li.getLoopFor(block); blockLoop;
       blockLoop = blockLoop->getParentLoop()) {
    if (blockLoop == loop)
      return true;
  }
  return false;
}

// TODO: reuse functions from FtdImplementation
BoolExpression *getBlockLoopExitCondition(Block *loopExit, CFGLoop *loop,
                                          CFGLoopInfo &li,
                                          const BlockIndexing &bi) {

  // Get the boolean expression associated to the block exit
  BoolExpression *blockCond =
      BoolExpression::parseSop(bi.getBlockCondition(loopExit));

  // Since we are in a loop, the terminator is a conditional branch.
  auto *terminatorOperation = loopExit->getTerminator();
  auto condBranch = dyn_cast<cf::CondBranchOp>(terminatorOperation);
  assert(condBranch && "Terminator of a loop must be `cf::CondBranchOp`");

  // If the destination of the false outcome is not the block, then the
  // condition must be negated
  if (li.getLoopFor(condBranch.getFalseDest()) != loop)
    blockCond->boolNegate();

  return blockCond;
}

static BoolExpression *
getLoopExitCondition(CFGLoop *loop, std::vector<std::string> *cofactorList,
                     mlir::CFGLoopInfo &li, const BlockIndexing &bi) {

  SmallVector<Block *> exitBlocks;
  loop->getExitingBlocks(exitBlocks);

  BoolExpression *fLoopExit = BoolExpression::boolZero();

  // Get the list of all the cofactors related to possible exit conditions
  for (Block *exitBlock : exitBlocks) {
    BoolExpression *blockCond =
        getBlockLoopExitCondition(exitBlock, loop, li, bi);
    fLoopExit = BoolExpression::boolOr(fLoopExit, blockCond);
    cofactorList->push_back(bi.getBlockCondition(exitBlock));
    fLoopExit = fLoopExit->boolMinimize();
  }
  // Sort the cofactors alphabetically
  std::sort(cofactorList->begin(), cofactorList->end());
  return fLoopExit;
}

void experimental::gsa::GSAAnalysis::convertPhiToMu(Region &region,
                                                    const BlockIndexing &bi) {
  mlir::DominanceInfo domInfo;
  mlir::CFGLoopInfo loopInfo(domInfo.getDomTree(&region));

  // For each phi, in the order of the region (see `convertPhiToGamma`)
  for (Block &block : region) {
    Block *phiBlock = &block;
    SmallVector<Gate *> phis = gatesPerBlock.lookup(phiBlock);
    for (Gate *phi : phis) {

      // A phi can be a MU only if it is inside a loop and has at least two
      // operands
      if (!loopInfo.getLoopFor(phiBlock) || phi->operands.size() < 2)
        continue;

      // Checks whether the block of the merge is a loop header
      if (loopInfo.getLoopFor(phiBlock)->getHeader() != phiBlock)
        continue;

      // MU gate has two groups of operands: from inside and from outside the
      // loop
      SmallVector<GateInput *> initialInputs, loopInputs;

      // Separate inputs from outside the loop (initialInputs) and inside the
      // loop (loopInputs). An input is from inside the loop when it is sent
      // from inside the loop, through a back edge, wherever it is produced: a
      // latch may send a value produced before the loop. An input sent both
      // from outside and from inside the loop is split in two, one input for
      // each side. The inputs of a phi obtained from a merge have no senders,
      // and their producer blocks are used instead.
      CFGLoop *loop = loopInfo.getLoopFor(phiBlock);
      for (GateInput *input : phi->operands) {
        if (input->senders.empty()) {
          if (IsBlockInLoop(input->getBlock(), loop, loopInfo))
            loopInputs.push_back(input);
          else
            initialInputs.push_back(input);
          continue;
        }

        std::unordered_set<Block *> loopSenders;
        for (Block *sender : input->senders) {
          if (IsBlockInLoop(sender, loop, loopInfo))
            loopSenders.insert(sender);
        }

        if (loopSenders.empty()) {
          initialInputs.push_back(input);
        } else if (loopSenders.size() == input->senders.size()) {
          loopInputs.push_back(input);
        } else {
          GateInput *loopInput = new GateInput(*input);
          gateInputList.push_back(loopInput);
          loopInput->senders = loopSenders;
          for (Block *sender : loopSenders)
            input->senders.erase(sender);
          initialInputs.push_back(input);
          loopInputs.push_back(loopInput);
        }
      }

      // If both initialInputs and loopInputs have at least one member, we have
      // a MU gate
      if (initialInputs.size() < 1 || loopInputs.size() < 1)
        continue;

      // MU gate has exactly one operand from inside and one from outside the
      // loop. If more than one exists, a phi gate is added to select the output
      GateInput *operandInit = nullptr, *operandLoop = nullptr;

      // Handle initail input
      if (initialInputs.size() == 1)
        operandInit = initialInputs[0];
      else {
        Gate *initialPhi = new Gate(phi->result, initialInputs,
                                    GateType::PhiGate, ++uniqueGateIndex);
        gatesPerBlock[phiBlock].push_back(initialPhi);
        operandInit = new GateInput(initialPhi);
        gateInputList.push_back(operandInit);
      }

      // Handle loop input
      if (loopInputs.size() == 1)
        operandLoop = loopInputs[0];
      else {
        // Create a Phi gate to merge multiple loop inputs before creating the
        // Mu gate.
        Gate *loopPhi = new Gate(phi->result, loopInputs, GateType::PhiGate,
                                 ++uniqueGateIndex, nullptr,
                                 BoolExpression::boolZero(), {});
        gatesPerBlock[phiBlock].push_back(loopPhi);
        operandLoop = new GateInput(loopPhi);
        gateInputList.push_back(operandLoop);
      }

      phi->gsaGateFunction = GateType::MuGate;
      phi->operands = {operandInit, operandLoop};

      // The block determining the MU condition is the exiting block of the
      // innermost loop the MU is in
      phi->conditionBlock =
          loopInfo.getLoopFor(phi->getBlock())->getExitingBlock();

      // Mu condition is the negation of loop exit-> if loop exit == false ? use
      // loop input : use initial input
      phi->condition = getLoopExitCondition(loopInfo.getLoopFor(phiBlock),
                                            &phi->cofactorList, loopInfo, bi)
                           ->boolNegate();
      phi->isRoot = true;
    }
  }
}

void experimental::gsa::GSAAnalysis::removePhiGates(Region &region) {
  // In the order of the region, as `singleOperandPhis` is replayed by
  // `addGsaGates`
  for (Block &bb : region) {
    Block *block = &bb;
    auto it = gatesPerBlock.find(block);
    if (it == gatesPerBlock.end())
      continue;

    // New vector of gates, which will contain only gamms and mus
    SmallVector<Gate *> gatesWithoutPhis;
    for (Gate *g : it->second) {
      // Delete the gate in case of a phi, otherwise keep it and insert it in
      // the new list. A phi with a single operand is kept aside: the value it
      // defines is to be replaced by the one of its operand.
      if (g->gsaGateFunction != GateType::PhiGate)
        gatesWithoutPhis.push_back(g);
      else if (g->operands.size() == 1)
        singleOperandPhis.push_back(g);
      else
        delete g;
    }
    // Modify the list
    gatesPerBlock[block] = gatesWithoutPhis;
  }
}

ArrayRef<experimental::gsa::Gate *>
experimental::gsa::GSAAnalysis::getGatesPerBlock(Block *bb) const {
  auto it = gatesPerBlock.find(bb);
  return it == gatesPerBlock.end() ? ArrayRef<Gate *>() : it->getSecond();
}

void experimental::gsa::GSAAnalysis::printAllGates(Region &region) {
  for (Block &block : region) {
    for (Gate *g : getGatesPerBlock(&block))
      g->print();
  }
  for (Gate *g : singleOperandPhis)
    g->print();
}

experimental::gsa::GSAAnalysis::~GSAAnalysis() {
  for (GateInput *gi : gateInputList)
    delete gi;
  for (auto const &[_, gates] : gatesPerBlock) {
    for (Gate *g : gates)
      delete g;
  }
  for (Gate *g : singleOperandPhis)
    delete g;
}

void experimental::gsa::Gate::print() {

  LLVM_DEBUG(
      auto getPhiName = [](Gate *p) -> std::string {
        switch (p->gsaGateFunction) {
        case GammaGate:
          return "GAMMA";
        case MuGate:
          return "MU";
        default:
          return "PHI";
        }
      };

      llvm::dbgs() << "[GSA] Block "; getBlock()->printAsOperand(llvm::dbgs());
      llvm::dbgs() << " arg " << getArgumentNumber() << " type "
                   << getPhiName(this) << "_" << index;

      if (gsaGateFunction == GammaGate || gsaGateFunction == MuGate) {
        llvm::dbgs() << " condition ";
        conditionBlock->printAsOperand(llvm::dbgs());
      }

      llvm::dbgs()
      << "\n";

      for (GateInput *&op : operands) {
        if (op->isTypeValue()) {
          llvm::dbgs() << "[GSA]\t VALUE\t: ";
          op->getValue().print(llvm::dbgs());
        } else if (op->isTypeEmpty()) {
          llvm::dbgs() << "[GSA]\t EMPTY";
        } else {
          llvm::dbgs() << "[GSA]\t GATE\t: " << getPhiName(op->getGate()) << "_"
                       << op->getGate()->index;
        }

        if (!op->isTypeEmpty()) {
          llvm::dbgs() << "\t(";
          op->getBlock()->printAsOperand(llvm::dbgs());
          llvm::dbgs() << ")";
        }

        if (!op->senders.empty()) {
          llvm::dbgs() << "\t[senders: ";
          bool first = true;
          for (auto *sender : op->senders) {
            if (!first)
              llvm::dbgs() << ", ";
            sender->printAsOperand(llvm::dbgs());
            first = false;
          }
          llvm::dbgs() << "]";
        }
        llvm::dbgs() << "\n";
      });
}

Block *experimental::gsa::GateInput::getBlock() {
  if (isTypeEmpty())
    return nullptr;
  return isTypeGate() ? getGate()->getBlock() : getValue().getParentBlock();
}
