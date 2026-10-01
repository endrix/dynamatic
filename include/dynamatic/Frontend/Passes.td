//===- Passes.td - C frontend passes definition ------------*- tablegen -*-===//
//
// Dynamatic is under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// This file contains definitions for the passes of the C frontend that read
// the original C source. They link libclang, so they live in their own library
// (DynamaticFrontend) and are not part of registerAllPasses(): a tool that
// links Dynamatic's other passes does not depend on libclang.so.
//
//===----------------------------------------------------------------------===//

#ifndef DYNAMATIC_FRONTEND_PASSES_TD
#define DYNAMATIC_FRONTEND_PASSES_TD

include "mlir/Pass/PassBase.td"
include "dynamatic/Support/Passes.td"

def FuncSetArgNames : DynamaticPass<"func-set-arg-names"> {
  let summary = "Replace function argument names with original ones from C";
  let description = [{
    The pass uses clang's C API to parse the original source code and replaces
    the default argument names given by Polygeist to all function arguments with
    the actual ones used in the source code.
  }];
  let options =
    [Option<"source", "source", "std::string", "",
            "Path to source C file from which the IR was generated.">];
}

#endif // DYNAMATIC_FRONTEND_PASSES_TD
