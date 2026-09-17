// An operation whose implementation was chosen before placement is timed by
// the entry that names it: a sequential multiplier is
// `handshake.muli.sequential.<STEP>` and a sequential divider
// `handshake.divui.sequential`, the way a floating-point unit is
// `handshake.addf.flopoco`. The model in Inputs gives the sequential units a
// 1.5 ns data path and the pipelined ones 0.001 ns, so at a 2.0 ns period two
// units in a row need a buffer between them only when the variant's entry is
// the one read.
//
// REQUIRES: cbc
// RUN: dynamatic-opt %s --handshake-place-buffers="algorithm=fpga20 solver=cbc timeout=30 target-period=2.0 timing-models=%S/Inputs/impl-timing-models.json spec-timing-models=%dynamatic_src_root/data/spec-timing.json" --remove-operation-names 2>/dev/null | FileCheck %s
// RUN: dynamatic-opt %s --handshake-place-buffers="algorithm=fpga20 solver=cbc timeout=30 target-period=2.0 timing-models=%S/Inputs/impl-timing-models.json spec-timing-models=%dynamatic_src_root/data/spec-timing.json" -o /dev/null 2>&1 | FileCheck %s --check-prefix=REMARK

// Two sequential multipliers in a row: 1.5 + 1.5 ns does not fit in 2.0 ns, so
// the placer cuts between them.
// CHECK-LABEL: handshake.func @sequential_multiplier
// CHECK:       muli
// CHECK:       buffer
// CHECK:       muli
handshake.func @sequential_multiplier(%arg0: !handshake.channel<i32>, %arg1: !handshake.channel<i32>, %start: !handshake.control<>, ...) -> (!handshake.channel<i32>, !handshake.control<>) attributes {argNames = ["a", "b", "start"], resNames = ["out", "end"], handshake.frequencies = []} {
  %b:2 = fork [2] %arg1 {handshake.bb = 0 : ui32} : <i32>
  %m0 = muli %arg0, %b#0 {handshake.bb = 0 : ui32, hw.parameters = {IMPL = "sequential", STEP = 8 : i64}} : <i32>
  %m1 = muli %m0, %b#1 {handshake.bb = 0 : ui32, hw.parameters = {IMPL = "sequential", STEP = 8 : i64}} : <i32>
  end %m1, %start : <i32>, <>
}

// The same shape with a sequential divider, whose entry carries no step.
// CHECK-LABEL: handshake.func @sequential_divider
// CHECK:       divui
// CHECK:       buffer
// CHECK:       divui
handshake.func @sequential_divider(%arg0: !handshake.channel<i32>, %arg1: !handshake.channel<i32>, %start: !handshake.control<>, ...) -> (!handshake.channel<i32>, !handshake.control<>) attributes {argNames = ["a", "b", "start"], resNames = ["out", "end"], handshake.frequencies = []} {
  %b:2 = fork [2] %arg1 {handshake.bb = 0 : ui32} : <i32>
  %d0 = divui %arg0, %b#0 {handshake.bb = 0 : ui32, hw.parameters = {IMPL = "sequential"}} : <i32>
  %d1 = divui %d0, %b#1 {handshake.bb = 0 : ui32, hw.parameters = {IMPL = "sequential"}} : <i32>
  end %d1, %start : <i32>, <>
}

// The same shape again, with no implementation named: the base entry's
// 0.001 ns fits twice over in the period and nothing is placed.
// CHECK-LABEL: handshake.func @pipelined_multiplier
// CHECK-NOT:   buffer
// CHECK:       end
handshake.func @pipelined_multiplier(%arg0: !handshake.channel<i32>, %arg1: !handshake.channel<i32>, %start: !handshake.control<>, ...) -> (!handshake.channel<i32>, !handshake.control<>) attributes {argNames = ["a", "b", "start"], resNames = ["out", "end"], handshake.frequencies = []} {
  %b:2 = fork [2] %arg1 {handshake.bb = 0 : ui32} : <i32>
  %m0 = muli %arg0, %b#0 {handshake.bb = 0 : ui32} : <i32>
  %m1 = muli %m0, %b#1 {handshake.bb = 0 : ui32} : <i32>
  end %m1, %start : <i32>, <>
}

// A step the model does not hold: the base entry is used, and the remark says
// which entry was wanted. It is emitted once, however often the model is
// asked, so the multiplier is timed as the pipelined one and nothing is
// placed.
// REMARK: no timing model for "handshake.muli.sequential.2"; the entry for "handshake.muli" is used instead
// CHECK-LABEL: handshake.func @step_with_no_entry
// CHECK-NOT:   buffer
// CHECK:       end
handshake.func @step_with_no_entry(%arg0: !handshake.channel<i32>, %arg1: !handshake.channel<i32>, %start: !handshake.control<>, ...) -> (!handshake.channel<i32>, !handshake.control<>) attributes {argNames = ["a", "b", "start"], resNames = ["out", "end"], handshake.frequencies = []} {
  %b:2 = fork [2] %arg1 {handshake.bb = 0 : ui32} : <i32>
  %m0 = muli %arg0, %b#0 {handshake.bb = 0 : ui32, hw.parameters = {IMPL = "sequential", STEP = 2 : i64}} : <i32>
  %m1 = muli %m0, %b#1 {handshake.bb = 0 : ui32, hw.parameters = {IMPL = "sequential", STEP = 2 : i64}} : <i32>
  end %m1, %start : <i32>, <>
}
