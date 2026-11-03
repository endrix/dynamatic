//===- GSAAnalysis.h - GSA analyis utilities --------------------*- C++ -*-===//
//
// Dynamatic is under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// Declares some utility functions useful towards converting the static single
// assignment (SSA) representation into gated single assingment representation
// (GSA).
//
//===----------------------------------------------------------------------===//

#ifndef DYNAMATIC_ANALYSIS_GSAANALYSIS_H
#define DYNAMATIC_ANALYSIS_GSAANALYSIS_H

#include "dynamatic/Dialect/Handshake/HandshakeOps.h"
#include "dynamatic/Support/LLVM.h"
#include "experimental/Support/BooleanLogic/BoolExpression.h"
#include "experimental/Support/FtdSupport.h"
#include "mlir/IR/Dominance.h"
#include "mlir/Pass/AnalysisManager.h"
#include <queue>
#include <unordered_set>
#include <utility>
#include <variant>

namespace dynamatic {
namespace experimental {
namespace gsa {

/// In this library, the word `gate` is used both for a `PHI` in SSA
/// representation and for `GAMMA`/`MU` in GSA representation

/// Define the three possible kinds of gate:
/// - A GAMMA gate, having two inputs and a predicate;
/// - A MU gate, having one init input and a `next` input;
/// - a PHI gate, having N possible inputs chosen in a *merge* fashion.
enum GateType { GammaGate, MuGate, PhiGate };

struct Gate;

/// Single class to collect a possible gate input, among these three
/// alternatives:
/// - a value, either produced by an operation in the IR or a block argument;
/// - another gate;
/// - an empty input (this happens for gammas having only one input).
struct GateInput {

  /// Depending on the type of the input, it might be a reference to a value on
  /// the IR, another gate or empty.
  std::variant<Value, Gate *> input;

  /// Set of all blocks that forward this GateInput to the gate.
  /// A value or block argument is defined in a producer block, but may reach
  /// the PHI through one or more sender blocks. Each sender block is a
  /// predecessor of the block of the PHI, and the PHI takes this input exactly
  /// when it is reached from one of them: the condition of the input is the
  /// one of the paths reaching the PHI through its senders, wherever the value
  /// is produced. The set is empty for the inputs of a gate built from a merge,
  /// whose condition is then computed from the producer block.
  std::unordered_set<Block *> senders;

  /// Constructor a gate input being the result of an operation.
  GateInput(Value v) : input(v) {};

  /// Constructor for a gate input being the output of another gate.
  GateInput(Gate *p) : input(p) {};

  /// Constructor for a gate input being empty.
  GateInput() : input(nullptr) {};

  /// Returns the block owner of the input.
  Block *getBlock();

  /// Returns true if the input is of type `Value`.
  bool isTypeValue() { return std::holds_alternative<Value>(input); }

  /// Returns true if the input is empty.
  bool isTypeEmpty() {
    return std::holds_alternative<Gate *>(input) && !std::get<Gate *>(input);
  }

  /// Returns true if the input is a gate.
  bool isTypeGate() {
    return std::holds_alternative<Gate *>(input) && std::get<Gate *>(input);
  }

  /// Returns the input gate (raise an error if input is not a  gate).
  Gate *getGate() { return std::get<Gate *>(input); }

  /// Returns the input value (raise an error if input is not a value).
  Value getValue() { return std::get<Value>(input); }

  ~GateInput() = default;
};

using ListExpressionsPerGate =
    std::vector<std::pair<boolean::BoolExpression *, GateInput *>>;

/// The structure collects all the information related to a gate. Each gate has
/// a set of inputs, a type, a condition, an index and it might be a root.
struct Gate {

  /// Reference to the value produced by the gate
  Value result;

  /// List of operands of the gate.
  SmallVector<GateInput *> operands;

  /// Type of gate function.
  GateType gsaGateFunction;

  /// Block whose terminator is used to drive the condition of the gate.
  Block *conditionBlock;

  /// Condition of the gate.
  boolean::BoolExpression *condition;

  /// list of condition cofactors
  std::vector<std::string> cofactorList;

  /// Block in which the gate is placed
  Block *gateBlock;

  /// Index of the current gate, which uniquely identifies it.
  unsigned index;

  /// Determines whether it is a root or not (all MUs are roots, only the base
  /// of a tree of GAMMAs is the root).
  bool isRoot = false;

  /// Initialize the values of the gate.
  Gate(Value v, ArrayRef<GateInput *> pi, GateType gt, unsigned i,
       Block *c = nullptr,
       boolean::BoolExpression *cond = boolean::BoolExpression::boolZero(),
       std::vector<std::string> cof = {})
      : result(v), operands(pi), gsaGateFunction(gt), conditionBlock(c),
        condition(cond), cofactorList(cof), gateBlock(v.getParentBlock()),
        index(i) {}

  /// Print the information about the gate.
  void print();

  /// Get the block the gate refers to.
  inline Block *getBlock() { return gateBlock; }

  /// Get the argument numebr the gate refers to. If the value is not a block
  /// argument, return 0
  inline unsigned getArgumentNumber() {
    if (auto ba = llvm::dyn_cast<BlockArgument>(result); ba)
      return ba.getArgNumber();
    return 0;
  }

  ~Gate() = default;
};

/// Map from each block to to the corresponding set of gates.
using MapGatesPerBlock = DenseMap<Block *, SmallVector<Gate *>>;

/// Class in charge of performing the GSA analysis prior to the cf to handshake
/// conversion. For each block arguments, it provides the information necessary
/// for a conversion into a `Gate` structure.
class GSAAnalysis {

public:
  /// Constructor for the GSA analysis. It requires an operation consisting of a
  /// function to get the SSA information from.
  GSAAnalysis(Operation *operation);

  /// This constructor runs the gsa anlaysis over a single merge and returns its
  /// GSA conversion. This is convenient to obtain the GSA-equivalent of a
  /// single merge.
  GSAAnalysis(handshake::MergeOp &merge, Region &region);

  /// Copy constructor for the anlaysis pass, rerunning the anlaysis so that new
  /// pointers are created
  GSAAnalysis(GSAAnalysis &gsa) {
    this->inputOp = gsa.inputOp;
    this->convertSSAToGSA(*this->inputOp);
  }

  /// Invalidation hook to keep the analysis cached across passes. Returns
  /// true if the analysis should be invalidated and fully reconstructed the
  /// next time it is queried.
  bool isInvalidated(const mlir::AnalysisManager::PreservedAnalyses &pa) {
    return !pa.isPreserved<GSAAnalysis>();
  }

  /// Get a vector containing all the gates related to a basic block.
  ArrayRef<Gate *> getGatesPerBlock(Block *bb) const;

  /// Returns true if the analysis could not convert the region, in which case
  /// it emitted an error on the block argument it could not convert, and its
  /// gates are not to be used.
  bool hasFailed() const { return analysisFailed; }

  /// Get the phis having a single operand. Such a phi is its operand, there is
  /// nothing to choose: no gate stands for it, the gates which had it as input
  /// have its operand instead, and the value it defines is to be replaced by
  /// the one of its operand.
  ArrayRef<Gate *> getSingleOperandPhis() const { return singleOperandPhis; }

  /// Deallocates all the gates created.
  ~GSAAnalysis();

private:
  /// Keep track of the original operation the analysis was run on.
  Region *inputOp;

  /// Associate an index to each gate.
  unsigned uniqueGateIndex;

  /// For each block in the function, keep a list of gate functions with all
  /// their information.
  MapGatesPerBlock gatesPerBlock;

  /// List of all gate inputs which have been created (and must be thus
  /// deallocated).
  SmallVector<GateInput *> gateInputList;

  /// Phis with a single operand, which do not become gates.
  SmallVector<Gate *> singleOperandPhis;

  /// Whether the analysis failed (see `hasFailed`).
  bool analysisFailed = false;

  /// Emit an error on the block argument of `phi`, whose inputs cannot be
  /// expanded into a tree of gammas for `reason`, and mark the analysis as
  /// failed.
  void emitGammaTreeError(Gate *phi, StringRef reason);

  /// Identify the gates necessary in the function, referencing all of their
  /// inputs. In this case, the starting point are the block arguments in the
  /// blocks.
  void convertSSAToGSA(Region &region);

  /// Identify the gates necessary in the function, referencing all of their
  /// inputs. In this case, the starting point of the anlaysis is an instance of
  /// handshake::merge
  void convertSSAToGSAMerges(handshake::MergeOp &merge, Region &region);

  /// Print the list of the gate functions, in the order of the region.
  void printAllGates(Region &region);

  /// Mark as mu all the phi gates which correspond to loop variables.
  void convertPhiToMu(Region &region,
                      const experimental::ftd::BlockIndexing &bi);

  /// Convert some phi gates to trees of gamma gates.
  void convertPhiToGamma(Region &region,
                         const experimental::ftd::BlockIndexing &bi);

  /// Make every gate input which takes `gate` take `input` instead.
  void replaceGateInput(Gate *gate, std::variant<Value, Gate *> input);

  /// For each operand of `phi`, compute the boolean expression of the
  /// condition under which the phi takes it, from the senders of the operands.
  /// The conditions the expressions use are added to `conditions`.
  ListExpressionsPerGate
  getExpressionsFromSenders(Gate *phi, DenseSet<unsigned> &conditions,
                            const ftd::BlockIndexing &bi,
                            mlir::DominanceInfo &domInfo);

  /// For each operand of `phi`, compute the boolean expression of the
  /// condition under which the phi takes it, from the producer blocks of the
  /// operands, for a phi built from a merge (whose operands have no senders).
  /// The conditions the expressions use are added to `conditions`.
  ListExpressionsPerGate
  getExpressionsFromProducers(Gate *phi, DenseSet<unsigned> &conditions,
                              const ftd::BlockIndexing &bi,
                              mlir::DominanceInfo &domInfo);

  /// Given a boolean expression for each phi's inputs, expand it in a tree
  /// of gamma functions. Returns nullptr, after an error, if no order of the
  /// conditions expands it.
  Gate *expandGammaTree(ListExpressionsPerGate &expressions,
                        std::queue<unsigned> conditions, Gate *originalPhi,
                        const ftd::BlockIndexing &bi);

  /// Given the list of gates in `gatesPerBlock`, get rid of the phi after their
  /// conversion to the GSA equivalents (the phis with a single operand are
  /// moved to `singleOperandPhis`, in the order of the region).
  void removePhiGates(Region &region);
};
} // namespace gsa
} // namespace experimental
} // namespace dynamatic

#endif // DYNAMATIC_ANALYSIS_GSAANALYSIS_H
