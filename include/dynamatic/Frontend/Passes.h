//===- Passes.h - C frontend passes registration ----------------*- C++ -*-===//
//
// Dynamatic is under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// This file contains declarations to register the C frontend's passes, the
// ones that link libclang (see Passes.td).
//
//===----------------------------------------------------------------------===//

#ifndef DYNAMATIC_FRONTEND_PASSES_H
#define DYNAMATIC_FRONTEND_PASSES_H

#include "dynamatic/Support/DynamaticPass.h"
#include "dynamatic/Support/LLVM.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/Pass/Pass.h"

namespace dynamatic {

/// Generate the code for registering passes.
#define GEN_PASS_DECL
#define GEN_PASS_REGISTRATION
#include "dynamatic/Frontend/Passes.h.inc"

} // namespace dynamatic

#endif // DYNAMATIC_FRONTEND_PASSES_H
