// RUN: dynamatic-opt --handshake-optimize-bitwidths --remove-operation-names %s | FileCheck %s

// A zero-extended value shifted right by at least its own width is all zeros:
// the shift becomes a constant, in the shift's basic block. ArithShrUIFW read
// the shift's block after replaceOpWithNewOp had erased it (a use-after-free,
// a segfault on macOS arm64).

// CHECK-LABEL:   handshake.func @shruiShiftedAway(
// CHECK-NOT:       shrui
// CHECK:           constant %{{.*}} {handshake.bb = 1 : ui32, value = 0 : i32} : <>, <i32>
// CHECK-NOT:       shrui
handshake.func @shruiShiftedAway(%arg0: !handshake.channel<i8>, %start: !handshake.control<>) -> !handshake.channel<i32> {
  %ext = extui %arg0 {handshake.bb = 1 : ui32} : <i8> to <i32>
  %cst = handshake.constant %start {handshake.bb = 1 : ui32, value = 8 : i32} : <>, <i32>
  %res = shrui %ext, %cst {handshake.bb = 1 : ui32} : <i32>
  end %res : <i32>
}
