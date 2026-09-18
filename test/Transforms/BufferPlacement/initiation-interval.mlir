// A unit whose implementation is chosen before placement and runs one
// operation at a time carries its initiation interval next to its latency,
// and the MILP reads it. The loop below multiplies once an iteration with a
// sequential multiplier: 9 cycles an operand pair, so the loop cannot run
// faster than a token every 9 cycles. Without the interval the placer
// models the same unit as pipelined and gives the loop a token a cycle; the
// slots it places are the same either way here (the loop's other cycles
// bound them), only the throughput it reports changes. Under fpga24 the
// interval is the CFDFC's II, and the paper's equality on every cycle's
// latency pads the two back edges to it: a counter buffer of dvLatency 9
// on each.
//
// REQUIRES: cbc
// RUN: dynamatic-opt %s --handshake-place-buffers="algorithm=fpga24 solver=cbc timeout=30 timing-models=%dynamatic_src_root/data/components.json spec-timing-models=%dynamatic_src_root/data/spec-timing.json" 2>/dev/null | FileCheck %s --check-prefix=FPGA24
// RUN: dynamatic-opt %s --handshake-place-buffers="algorithm=fpga20 solver=cbc timeout=30 timing-models=%dynamatic_src_root/data/components.json spec-timing-models=%dynamatic_src_root/data/spec-timing.json" 2>/dev/null | FileCheck %s
// RUN: dynamatic-opt %s --handshake-place-buffers="algorithm=fpga20 solver=cbc timeout=30 timing-models=%dynamatic_src_root/data/components.json spec-timing-models=%dynamatic_src_root/data/spec-timing.json" -o /dev/null 2>&1 | FileCheck %s --check-prefix=REMARK
// RUN: sed 's/initiation_interval = 9 : i64, //' %s | dynamatic-opt --handshake-place-buffers="algorithm=fpga20 solver=cbc timeout=30 timing-models=%dynamatic_src_root/data/components.json spec-timing-models=%dynamatic_src_root/data/spec-timing.json" 2>/dev/null | FileCheck %s --check-prefix=NOII

// The MILP's own answer, on the function: a ninth of a token a cycle with the
// interval, a whole one without it.
// CHECK-LABEL: handshake.func @loop
// CHECK-SAME:   cfdfcThroughput {"0" = 0.11111111
// NOII-LABEL:   handshake.func @loop
// NOII-SAME:    cfdfcThroughput {"0" = 1.000000e+00
// REMARK: remark: buffer placement: mul_seq takes a token every 9 cycles, not every cycle
// FPGA24-LABEL: handshake.func @loop
// FPGA24:       buffer {{.*}} bufferType = COUNTER_BUFFER, numSlots = 1, dvLatency = 9
// FPGA24:       buffer {{.*}} bufferType = COUNTER_BUFFER, numSlots = 1, dvLatency = 9

handshake.func @loop(%arg0: !handshake.channel<i32>, %arg1: !handshake.control<>, ...) -> (!handshake.channel<i32>, !handshake.control<>) attributes {argNames = ["i0", "start"], resNames = ["out", "end"], handshake.frequencies = [[0, 1, 1, 0], [1, 1, 63, 1], [1, 2, 1, 0]]} {
  %i0 = br %arg0 {handshake.bb = 0 : ui32} : <i32>
  %c0 = br %arg1 {handshake.bb = 0 : ui32} : <>
  %i = mux %index [%i0, %ti] {handshake.bb = 1 : ui32} : <i1>, [<i32>, <i32>] to <i32>
  %ctrl, %index = control_merge [%c0, %tc] {handshake.bb = 1 : ui32} : [<>, <>] to <>, <i1>
  %i2:4 = fork [4] %i {handshake.bb = 1 : ui32} : <i32>
  %s = source {handshake.bb = 1 : ui32} : <>
  %n = constant %s {handshake.bb = 1 : ui32, value = 64 : i32} : <>, <i32>
  %cond = cmpi slt, %i2#0, %n {handshake.bb = 1 : ui32} : <i32>
  %cond2:2 = fork [2] %cond {handshake.bb = 1 : ui32} : <i1>
  %s2 = source {handshake.bb = 1 : ui32} : <>
  %one = constant %s2 {handshake.bb = 1 : ui32, value = 1 : i32} : <>, <i32>
  %next = addi %i2#1, %one {handshake.bb = 1 : ui32} : <i32>
  %ti, %fi = cond_br %cond2#0, %next {handshake.bb = 1 : ui32} : <i1>, <i32>
  %tc, %fc = cond_br %cond2#1, %ctrl {handshake.bb = 1 : ui32} : <i1>, <>
  // 32 bits at 4 multiplier bits a cycle: a product every ceil(32 / 4) + 1
  // cycles, and one multiplication at a time
  %prod = muli %i2#2, %i2#3 {handshake.bb = 1 : ui32, handshake.name = "mul_seq", hw.parameters = {IMPL = "sequential", STEP = 4 : i64}, initiation_interval = 9 : i64, latency = 9 : i64} : <i32>
  sink %prod {handshake.bb = 1 : ui32} : <i32>
  %out = br %fi {handshake.bb = 2 : ui32} : <i32>
  %done = br %fc {handshake.bb = 2 : ui32} : <>
  end %out, %done : <i32>, <>
}
