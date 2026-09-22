// An operation whose implementation was chosen before placement is timed by
// the entry that names it: a sequential multiplier is
// `handshake.muli.sequential.<STEP>` and a sequential divider
// `handshake.divui.sequential`, the way a floating-point unit is
// `handshake.addf.flopoco`. The key is the operation's own name with the
// implementation on it, so the rule needs no list of units: a `divsi` is
// keyed the same way, and one whose variant the model does not hold falls
// back to its base entry with a remark, as a `remsi` does here. The model in Inputs gives the sequential units a
// 1.5 ns data path and the pipelined ones 0.001 ns, so at a 2.0 ns period two
// units in a row need a buffer between them only when the variant's entry is
// the one read. The entries here carry no latency, so the data delay goes
// through the combinational constraint; the shipped models give the
// sequential units a latency and a zero port-to-port delay, so there the
// key decides the latency table and the ready and valid delays.
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

// The signed division is keyed the same way, and the model holds its
// variant: the 1.5 ns entry is read and the placer cuts.
// CHECK-LABEL: handshake.func @sequential_signed_divider
// CHECK:       divsi
// CHECK:       buffer
// CHECK:       divsi
handshake.func @sequential_signed_divider(%arg0: !handshake.channel<i32>, %arg1: !handshake.channel<i32>, %start: !handshake.control<>, ...) -> (!handshake.channel<i32>, !handshake.control<>) attributes {argNames = ["a", "b", "start"], resNames = ["out", "end"], handshake.frequencies = []} {
  %b:2 = fork [2] %arg1 {handshake.bb = 0 : ui32} : <i32>
  %d0 = divsi %arg0, %b#0 {handshake.bb = 0 : ui32, hw.parameters = {IMPL = "sequential"}} : <i32>
  %d1 = divsi %d0, %b#1 {handshake.bb = 0 : ui32, hw.parameters = {IMPL = "sequential"}} : <i32>
  end %d1, %start : <i32>, <>
}

// A sequential unit the model has no variant for: the base entry is used,
// the remark says which entry was wanted, and the 0.001 ns fits twice over
// so nothing is placed. The unit's LATENCY is still its own -- getLatency
// reads the `latency` attribute the pass wrote before it asks the model --
// and only the delay comes from the wrong entry.
// REMARK: no timing model for "handshake.remsi.sequential"; the entry for "handshake.remsi" is used instead
// CHECK-LABEL: handshake.func @sequential_signed_remainder
// CHECK-NOT:   buffer
// CHECK:       end
handshake.func @sequential_signed_remainder(%arg0: !handshake.channel<i32>, %arg1: !handshake.channel<i32>, %start: !handshake.control<>, ...) -> (!handshake.channel<i32>, !handshake.control<>) attributes {argNames = ["a", "b", "start"], resNames = ["out", "end"], handshake.frequencies = []} {
  %b:2 = fork [2] %arg1 {handshake.bb = 0 : ui32} : <i32>
  %r0 = remsi %arg0, %b#0 {handshake.bb = 0 : ui32, latency = 33 : i64, hw.parameters = {IMPL = "sequential"}} : <i32>
  %r1 = remsi %r0, %b#1 {handshake.bb = 0 : ui32, latency = 33 : i64, hw.parameters = {IMPL = "sequential"}} : <i32>
  end %r1, %start : <i32>, <>
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

// A step the model does not hold with a larger one it does: the larger
// step's entry is used (a multiplier's step is clamped to its width, so a
// narrow op under step 8 asks for its own width and is the step-8 unit at
// that width), and the remark says so, once however often the model is
// asked. The 1.5 ns entry is read, so the placer cuts.
// REMARK: no timing model for "handshake.muli.sequential.2"; the entry for "handshake.muli.sequential.8", the nearest larger step, is used instead
// REMARK-NOT: "handshake.muli.sequential.2"
// CHECK-LABEL: handshake.func @step_below_the_model
// CHECK:       muli
// CHECK:       buffer
// CHECK:       muli
handshake.func @step_below_the_model(%arg0: !handshake.channel<i32>, %arg1: !handshake.channel<i32>, %start: !handshake.control<>, ...) -> (!handshake.channel<i32>, !handshake.control<>) attributes {argNames = ["a", "b", "start"], resNames = ["out", "end"], handshake.frequencies = []} {
  %b:2 = fork [2] %arg1 {handshake.bb = 0 : ui32} : <i32>
  %m0 = muli %arg0, %b#0 {handshake.bb = 0 : ui32, hw.parameters = {IMPL = "sequential", STEP = 2 : i64}} : <i32>
  %m1 = muli %m0, %b#1 {handshake.bb = 0 : ui32, hw.parameters = {IMPL = "sequential", STEP = 2 : i64}} : <i32>
  end %m1, %start : <i32>, <>
}

// A step above every one the model holds: the base entry is used, and the
// remark says which entry was wanted, so the multiplier is timed as the
// pipelined one and nothing is placed.
// REMARK: no timing model for "handshake.muli.sequential.16"; the entry for "handshake.muli" is used instead
// CHECK-LABEL: handshake.func @step_with_no_entry
// CHECK-NOT:   buffer
// CHECK:       end
handshake.func @step_with_no_entry(%arg0: !handshake.channel<i32>, %arg1: !handshake.channel<i32>, %start: !handshake.control<>, ...) -> (!handshake.channel<i32>, !handshake.control<>) attributes {argNames = ["a", "b", "start"], resNames = ["out", "end"], handshake.frequencies = []} {
  %b:2 = fork [2] %arg1 {handshake.bb = 0 : ui32} : <i32>
  %m0 = muli %arg0, %b#0 {handshake.bb = 0 : ui32, hw.parameters = {IMPL = "sequential", STEP = 16 : i64}} : <i32>
  %m1 = muli %m0, %b#1 {handshake.bb = 0 : ui32, hw.parameters = {IMPL = "sequential", STEP = 16 : i64}} : <i32>
  end %m1, %start : <i32>, <>
}

// The pipelined implementation named in so many words is the base entry, and
// draws no remark: esa-unit-impl names both units whenever either is
// sequential.
// REMARK-NOT: "handshake.muli.pipelined"
// CHECK-LABEL: handshake.func @named_pipelined
// CHECK-NOT:   buffer
// CHECK:       end
handshake.func @named_pipelined(%arg0: !handshake.channel<i32>, %arg1: !handshake.channel<i32>, %start: !handshake.control<>, ...) -> (!handshake.channel<i32>, !handshake.control<>) attributes {argNames = ["a", "b", "start"], resNames = ["out", "end"], handshake.frequencies = []} {
  %b:2 = fork [2] %arg1 {handshake.bb = 0 : ui32} : <i32>
  %m0 = muli %arg0, %b#0 {handshake.bb = 0 : ui32, hw.parameters = {IMPL = "pipelined"}} : <i32>
  %m1 = muli %m0, %b#1 {handshake.bb = 0 : ui32, hw.parameters = {IMPL = "pipelined"}} : <i32>
  end %m1, %start : <i32>, <>
}
