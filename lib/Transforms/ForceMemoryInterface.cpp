//===- ForceMemoryInterface.cpp - Force interface in Handshake --*- C++ -*-===//
//
// Dynamatic is under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// Implements the --force-memory-interface pass, internally adding/modifying the
// `handshake::MemInterfaceAttr` to/on all memory operations to force placement
// of a specific type of memory interface.
//
//===----------------------------------------------------------------------===//

#include "dynamatic/Dialect/Handshake/HandshakeAttributes.h"
#include "dynamatic/Support/Attribute.h"
#include "mlir/Dialect/Affine/IR/AffineOps.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"

// [START Boilerplate code for the MLIR pass]
#include "dynamatic/Transforms/Passes.h" // IWYU pragma: keep
namespace dynamatic {
#define GEN_PASS_DEF_FORCEMEMORYINTERFACE
#include "dynamatic/Transforms/Passes.h.inc"
} // namespace dynamatic
// [END Boilerplate code for the MLIR pass]

using namespace mlir;
using namespace dynamatic;

namespace {

/// Simple driver for memory interface forcing pass.
struct ForceMemoryInterfacePass
    : public dynamatic::impl::ForceMemoryInterfaceBase<
          ForceMemoryInterfacePass> {

  using ForceMemoryInterfaceBase::ForceMemoryInterfaceBase;

  void runDynamaticPass() override {
    // Exactly one of the two pass options need to have been set
    if (forceLSQ && forceMC)
      llvm::errs() << "Both " << forceLSQ.ArgStr << " and " << forceMC.ArgStr
                   << " flags were provided. However, only one can be set at "
                      "the same time.";
    if (!forceLSQ && !forceMC)
      llvm::errs()
          << "Neither " << forceLSQ.ArgStr << " and " << forceMC.ArgStr
          << " flags were provided. However, exactly one needs to be set.";

    MLIRContext *ctx = &getContext();
    DenseMap<Block *, unsigned> lsqGroups;
    unsigned nextGroupID = 0;

    // A memory nothing STORES to gets a controller even under force-lsq.
    //
    // An LSQ exists to order stores against loads, so on a read-only memory it
    // has nothing to do -- and the backend cannot build one anyway: the
    // generator sizes its port-index vectors from the store count and asserts
    // `size > 0`, so a constant lookup table forced through an LSQ fails at
    // `export-rtl` with a Python AssertionError naming neither the memory nor
    // the reason.
    //
    // Read-only is also the one case where the choice is free: the trap that
    // makes force-mc wrong -- a store whose data is a load, read back later --
    // needs a store to happen at all.
    //
    // "Nothing stores" is judged conservatively: a memory is read-only only if
    // EVERY use of it is a load. A store is the obvious writer, but so is a
    // `memref.copy` into it, a call it is passed to, or a block transfer that
    // has not been expanded into stores yet -- and mistaking any of those for
    // read-only would hand a written memory to a controller, which is the
    // store-then-load value trap under another name.
    DenseSet<Value> written;
    getOperation()->walk([&](Operation *op) {
      for (Value operand : op->getOperands()) {
        if (!isa<MemRefType>(operand.getType()))
          continue;
        if (isa<memref::LoadOp, affine::AffineLoadOp>(op))
          continue;
        written.insert(operand);
      }
    });
    auto readOnly = [&](Operation *op) {
      if (auto load = dyn_cast<memref::LoadOp>(op))
        return !written.contains(load.getMemRef());
      if (auto load = dyn_cast<affine::AffineLoadOp>(op))
        return !written.contains(load.getMemRef());
      return false;
    };

    // A forced interface says nothing about dependences: whatever
    // `mark-memory-interfaces` vouched for no longer holds.
    getOperation()->walk([&](func::FuncOp funcOp) {
      funcOp->removeAttr(handshake::MEM_INTERFACES_FROM_DEPS_ATTR);
    });

    // Find all memory operations and adds/modifies the
    // handshake::MemInterfaceAttr on them depending on the pass parameters
    getOperation()->walk([&](Operation *op) {
      // This only makes sense on load/store-like operations
      if (!isa<memref::LoadOp, memref::StoreOp, affine::AffineLoadOp,
               affine::AffineStoreOp>(op))
        return;

      if (forceMC || readOnly(op)) {
        setDialectAttr<handshake::MemInterfaceAttr>(op, ctx);
        return;
      }

      // Make every block its own LSQ group
      Block *block = op->getBlock();
      unsigned groupID;

      // Try to find the block's group ID. Failing that, assign a new group ID
      // to the block
      if (auto groupIt = lsqGroups.find(block); groupIt != lsqGroups.end())
        groupID = groupIt->second;
      else
        lsqGroups[block] = groupID = nextGroupID++;

      setDialectAttr<handshake::MemInterfaceAttr>(op, ctx, groupID);
    });
  }
};
} // namespace
