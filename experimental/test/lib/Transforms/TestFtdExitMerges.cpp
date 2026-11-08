//===- TestFtdExitMerges.cpp - FTD exit merges of several returns - C++ -*-===//
//
// Dynamatic is under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// Test pass for ftd::branchExitMergeOperands. Run with
// --exp-test-ftd-exit-merges. The lowering always builds the exit merges it
// later branches, so its refusal of any other shape cannot be reached from a
// cf function; this pass runs the helper on a handshake function written by
// hand. A function is processed when it carries `test.ftd_num_results` (the
// results of the original function) and `test.ftd_return_blocks` (the
// returning blocks, in the order of the merges' operands).
//
//===----------------------------------------------------------------------===//

#include "dynamatic/Dialect/Handshake/HandshakeOps.h"
#include "dynamatic/Support/LLVM.h"
#include "experimental/Conversion/FtdCfToHandshake.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/Pass/Pass.h"

using namespace mlir;
using namespace dynamatic;

namespace {

struct TestFtdExitMerges
    : public PassWrapper<TestFtdExitMerges, OperationPass<mlir::ModuleOp>> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(TestFtdExitMerges)

  StringRef getArgument() const final { return "exp-test-ftd-exit-merges"; }

  StringRef getDescription() const final {
    return "Branch the exit merges of a handshake function of several returns "
           "as fast token delivery does";
  }

  void runOnOperation() override {
    OpBuilder builder(&getContext());
    bool anyFailed = false;
    for (handshake::FuncOp funcOp :
         getOperation().getOps<handshake::FuncOp>()) {
      auto numResults =
          funcOp->getAttrOfType<IntegerAttr>("test.ftd_num_results");
      auto returnBlocks =
          funcOp->getAttrOfType<DenseI32ArrayAttr>("test.ftd_return_blocks");
      if (!numResults || !returnBlocks)
        continue;
      SmallVector<unsigned> blocks(returnBlocks.asArrayRef());
      if (failed(experimental::ftd::branchExitMergeOperands(
              funcOp, builder, numResults.getValue().getZExtValue(), blocks)))
        anyFailed = true;
    }
    if (anyFailed)
      signalPassFailure();
  }
};
} // namespace

namespace dynamatic {
namespace experimental {
namespace test {
void registerTestFtdExitMerges() { PassRegistration<TestFtdExitMerges>(); }
} // namespace test
} // namespace experimental
} // namespace dynamatic
