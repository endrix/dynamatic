// Which operations the timing database reads an initiation interval from.
// The model has no entry for the interval, because every unit it describes
// is pipelined; a unit whose implementation was chosen before placement
// (hw.parameters IMPL = "sequential") carries the interval on the op, and
// that one is read. An interval on any other operation is not the model's
// business and is ignored, and a sequential unit that carries no interval
// takes a token every cycle like the rest.
//
// REQUIRES: cbc
// RUN: dynamatic-opt %s --handshake-place-buffers="algorithm=fpga20 solver=cbc timeout=30 timing-models=%dynamatic_src_root/data/components.json spec-timing-models=%dynamatic_src_root/data/spec-timing.json" -o /dev/null 2>&1 | FileCheck %s

// CHECK-NOT: takes a token
// CHECK:     remark: buffer placement: mul_seq takes a token every 9 cycles, not every cycle
// CHECK-NOT: takes a token

handshake.func @loop(%arg0: !handshake.channel<i32>, %arg1: !handshake.control<>, ...) -> (!handshake.channel<i32>, !handshake.control<>) attributes {argNames = ["i0", "start"], resNames = ["out", "end"], handshake.frequencies = [[0, 1, 1, 0], [1, 1, 63, 1], [1, 2, 1, 0]]} {
  %i0 = br %arg0 {handshake.bb = 0 : ui32} : <i32>
  %c0 = br %arg1 {handshake.bb = 0 : ui32} : <>
  %i = mux %index [%i0, %ti] {handshake.bb = 1 : ui32} : <i1>, [<i32>, <i32>] to <i32>
  %ctrl, %index = control_merge [%c0, %tc] {handshake.bb = 1 : ui32} : [<>, <>] to <>, <i1>
  %i2:8 = fork [8] %i {handshake.bb = 1 : ui32} : <i32>
  %s = source {handshake.bb = 1 : ui32} : <>
  %n = constant %s {handshake.bb = 1 : ui32, value = 64 : i32} : <>, <i32>
  %cond = cmpi slt, %i2#0, %n {handshake.bb = 1 : ui32} : <i32>
  %cond2:2 = fork [2] %cond {handshake.bb = 1 : ui32} : <i1>
  %s2 = source {handshake.bb = 1 : ui32} : <>
  %one = constant %s2 {handshake.bb = 1 : ui32, value = 1 : i32} : <>, <i32>
  %next = addi %i2#1, %one {handshake.bb = 1 : ui32} : <i32>
  %ti, %fi = cond_br %cond2#0, %next {handshake.bb = 1 : ui32} : <i1>, <i32>
  %tc, %fc = cond_br %cond2#1, %ctrl {handshake.bb = 1 : ui32} : <i1>, <>
  // the implementation is named and the interval is there: the placer reads it
  %prod0 = muli %i2#2, %i2#3 {handshake.bb = 1 : ui32, handshake.name = "mul_seq", hw.parameters = {IMPL = "sequential", STEP = 4 : i64}, initiation_interval = 9 : i64, latency = 9 : i64} : <i32>
  sink %prod0 {handshake.bb = 1 : ui32} : <i32>
  // an interval on a pipelined unit: the model's unit takes a token a cycle
  %prod1 = muli %i2#4, %i2#5 {handshake.bb = 1 : ui32, handshake.name = "mul_pipelined", hw.parameters = {IMPL = "pipelined"}, initiation_interval = 9 : i64} : <i32>
  sink %prod1 {handshake.bb = 1 : ui32} : <i32>
  // a sequential unit with no interval: nothing to read, so a token a cycle
  %prod2 = muli %i2#6, %i2#7 {handshake.bb = 1 : ui32, handshake.name = "mul_no_interval", hw.parameters = {IMPL = "sequential", STEP = 4 : i64}, latency = 9 : i64} : <i32>
  sink %prod2 {handshake.bb = 1 : ui32} : <i32>
  %out = br %fi {handshake.bb = 2 : ui32} : <i32>
  %done = br %fc {handshake.bb = 2 : ui32} : <>
  end %out, %done : <i32>, <>
}
