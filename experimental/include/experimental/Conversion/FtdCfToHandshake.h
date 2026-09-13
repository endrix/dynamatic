//===- FtdCfToHandhsake.h - Convert func/cf to handhsake dialect -*- C++
//-*-===//
//
// Dynamatic is under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// This file declares the --ftd-lower-cf-to-handshake conversion pass
// along with a helper class for performing the lowering.
//
//===----------------------------------------------------------------------===//

#ifndef DYNAMATIC_CONVERSION_FTD_CF_TO_HANDSHAKE_H
#define DYNAMATIC_CONVERSION_FTD_CF_TO_HANDSHAKE_H

#include "dynamatic/Analysis/ControlDependenceAnalysis.h"
#include "dynamatic/Conversion/CfToHandshake.h"
#include "dynamatic/Support/DynamaticPass.h"
#include "dynamatic/Support/LLVM.h"
#include "experimental/Analysis/GSAAnalysis.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/BuiltinOps.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/SmallVector.h"

namespace dynamatic {
namespace experimental {
namespace ftd {

/// Convert a func-level function into an handshake-level function. A custom
/// behavior is defined so that the functionalities of the `fast delivery token`
/// methodology can be implemented.
/// The GSA analysis the gates come from is built per function inside
/// `matchAndRewrite`, so a module may hold any number of functions (the
/// module-level analysis accepts exactly one).
class FtdLowerFuncToHandshake : public LowerFuncToHandshake {
public:
  using LowerFuncToHandshake::LowerFuncToHandshake;

  LogicalResult
  matchAndRewrite(mlir::func::FuncOp funcOp, OpAdaptor adaptor,
                  ConversionPatternRewriter &rewriter) const override;
};

template <typename SrcOp, typename DstOp>
struct FtdOneToOneConversion : public OneToOneConversion<SrcOp, DstOp> {
public:
  using OpAdaptor = typename SrcOp::Adaptor;

  FtdOneToOneConversion(NameAnalysis &namer, const TypeConverter &typeConverter,
                        MLIRContext *ctx)
      : dynamatic::OneToOneConversion<SrcOp, DstOp>(namer, typeConverter, ctx) {
  }

  LogicalResult
  matchAndRewrite(SrcOp srcOp, OpAdaptor adaptor,
                  ConversionPatternRewriter &rewriter) const override;
};

template <typename CastOp, typename ExtOp>
struct FtdConvertIndexCast : public ConvertIndexCast<CastOp, ExtOp> {
public:
  using OpAdaptor = typename CastOp::Adaptor;

  FtdConvertIndexCast(NameAnalysis &namer, const TypeConverter &typeConverter,
                      MLIRContext *ctx)
      : dynamatic::ConvertIndexCast<CastOp, ExtOp>(namer, typeConverter, ctx) {}

  LogicalResult
  matchAndRewrite(CastOp castOp, OpAdaptor adaptor,
                  ConversionPatternRewriter &rewriter) const override;
};

/// Per-block edge information captured from CF-level IR before conversion.
struct BlockEdgeInfo {
  bool isConditional = false;
  bool hasSuccessors = false;
  unsigned trueSuccIdx = 0;
  unsigned falseSuccIdx = 0;
  unsigned uncondSuccIdx = 0;
};

/// Complete CFG topology of one function, captured before conversion.
struct OriginalCFGInfo {
  unsigned numBlocks = 0;
  llvm::SmallVector<BlockEdgeInfo> blockEdges;
};

/// The CFG topology of one function, read before the conversion erases its
/// blocks.
OriginalCFGInfo captureCFGTopology(mlir::func::FuncOp funcOp);

/// The topology of every non-external function of the module (the `__init`
/// placeholders aside), by symbol name. Call it BEFORE applyFullConversion.
llvm::DenseMap<llvm::StringRef, OriginalCFGInfo>
captureAllCFGTopologies(mlir::ModuleOp moduleOp);

/// The steps that complete fast token delivery on a function the
/// `FtdLowerFuncToHandshake` pattern has lowered: the shadow CFG rebuilt from
/// `info`, every conditional branch's select routed through its block's
/// condition placeholder, the placeholders resolved, regeneration and
/// suppression added, the placeholders finalized. A function of one block
/// needs none of it and is left as it is. Exposed so that another lowering
/// built on the pattern finishes the same way.
void completeFastTokenDelivery(handshake::FuncOp funcOp,
                               const OriginalCFGInfo &info);

} // namespace ftd
} // namespace experimental
} // namespace dynamatic

#endif // DYNAMATIC_CONVERSION_FTD_CF_TO_HANDSHAKE_H
