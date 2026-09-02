// The MILP placers read a function's transition frequencies from its own
// `handshake.frequencies` attribute when it has one, so a module of several
// functions with different CFGs is placed in one run without a CSV file; and
// a function with no basic-block annotations at all is left alone with a
// remark rather than modeled.
//
// REQUIRES: cbc
// RUN: dynamatic-opt %s --handshake-place-buffers="algorithm=fpga20 solver=cbc timeout=30 timing-models=%dynamatic_src_root/data/components.json spec-timing-models=%dynamatic_src_root/data/spec-timing.json" 2>/dev/null | FileCheck %s
// RUN: dynamatic-opt %s --handshake-place-buffers="algorithm=fpga20 solver=cbc timeout=30 timing-models=%dynamatic_src_root/data/components.json spec-timing-models=%dynamatic_src_root/data/spec-timing.json" -o /dev/null 2>&1 | FileCheck %s --check-prefix=REMARK

// A single-block loop: 64 iterations, so the back edge is taken 63 times.
// The placer has to break the cycle with at least one opaque slot.
// CHECK-LABEL: handshake.func @loop
// CHECK:       ONE_SLOT_BREAK_DV
handshake.func @loop(%arg0: !handshake.channel<i32>, %arg1: !handshake.control<>, ...) -> (!handshake.channel<i32>, !handshake.control<>) attributes {argNames = ["i0", "start"], resNames = ["out", "end"], handshake.frequencies = [[0, 1, 1, 0], [1, 1, 63, 1], [1, 2, 1, 0]]} {
  %i0 = br %arg0 {handshake.bb = 0 : ui32} : <i32>
  %c0 = br %arg1 {handshake.bb = 0 : ui32} : <>
  %i = mux %index [%i0, %next] {handshake.bb = 1 : ui32} : <i1>, [<i32>, <i32>] to <i32>
  %ctrl, %index = control_merge [%c0, %back] {handshake.bb = 1 : ui32} : [<>, <>] to <>, <i1>
  %i2:2 = fork [2] %i {handshake.bb = 1 : ui32} : <i32>
  %s = source {handshake.bb = 1 : ui32} : <>
  %n = constant %s {handshake.bb = 1 : ui32, value = 64 : i32} : <>, <i32>
  %cond = cmpi slt, %i2#0, %n {handshake.bb = 1 : ui32} : <i32>
  %cond2:2 = fork [2] %cond {handshake.bb = 1 : ui32} : <i1>
  %ti, %fi = cond_br %cond2#0, %i2#1 {handshake.bb = 1 : ui32} : <i1>, <i32>
  %tc, %fc = cond_br %cond2#1, %ctrl {handshake.bb = 1 : ui32} : <i1>, <>
  %s2 = source {handshake.bb = 1 : ui32} : <>
  %one = constant %s2 {handshake.bb = 1 : ui32, value = 1 : i32} : <>, <i32>
  %next = addi %ti, %one {handshake.bb = 1 : ui32} : <i32>
  %back = br %tc {handshake.bb = 1 : ui32} : <>
  %out = br %fi {handshake.bb = 2 : ui32} : <i32>
  %done = br %fc {handshake.bb = 2 : ui32} : <>
  end %out, %done : <i32>, <>
}

// No basic blocks: nothing for the MILP, nothing placed, a remark.
// CHECK-LABEL: handshake.func @nobb
// CHECK-NOT:   buffer
// REMARK:      remark: function has no basic-block annotations
handshake.func @nobb(%arg0: !handshake.channel<i32>, %arg1: !handshake.control<>, ...) -> (!handshake.channel<i32>, !handshake.control<>) attributes {argNames = ["a", "start"], resNames = ["out", "end"]} {
  %m = merge %arg0 : <i32>
  end %m, %arg1 : <i32>, <>
}
