// RUN: %export-verilog
// RUN: FileCheck %s -input-file %t/test.v --check-prefix=INST
// RUN: FileCheck %s -input-file %t/muli_sequential.v --check-prefix=SEQ
// RUN: FileCheck %s -input-file %t/muli.v --check-prefix=PIPE

// The two multipliers in the Verilog configuration. IMPL=sequential is the
// unit that adds STEP multiplier bits a cycle on one register set, the
// product held until taken, with DATA_TYPE and STEP as module parameters;
// IMPL=pipelined is the one-cycle product behind delay registers, the unit
// the configuration has always emitted. A sequential multiplier that names
// ITER_WIDTH (the multiplier bits it steps over) passes it as a third module
// parameter; one that does not leaves it at 0, every bit.

// INST: muli_sequential #(.DATA_TYPE(32), .STEP(4)) mul0(
// INST: muli #(.DATA_TYPE(32)) mul1(
// INST: muli_sequential #(.DATA_TYPE(32), .STEP(4), .ITER_WIDTH(16)) mul2(

// SEQ: module muli_sequential #(
// SEQ: parameter STEP = 1
// SEQ: parameter ITER_WIDTH = 0
// SEQ: localparam ITERATIONS = (BITS + STEP - 1) / STEP;
// SEQ: assign idle = (~busy) & ((~done) | result_ready);
// SEQ: assign partial = a_reg * b_reg[STEP - 1 : 0];
// SEQ: assign result_valid = done;

// PIPE: module mul_4_stage #(
// PIPE: module muli #(
module {
  hw.module @test(in %a : !handshake.channel<i32>, in %b : !handshake.channel<i32>, in %c : !handshake.channel<i32>, in %d : !handshake.channel<i32>, in %e : !handshake.channel<i32>, in %f : !handshake.channel<i32>, in %clk : i1, in %rst : i1, out out0 : !handshake.channel<i32>, out out1 : !handshake.channel<i32>, out out2 : !handshake.channel<i32>) {
    %mul0.result = hw.instance "mul0" @handshake_muli_0(lhs: %a: !handshake.channel<i32>, rhs: %b: !handshake.channel<i32>, clk: %clk: i1, rst: %rst: i1) -> (result: !handshake.channel<i32>)
    %mul1.result = hw.instance "mul1" @handshake_muli_1(lhs: %c: !handshake.channel<i32>, rhs: %d: !handshake.channel<i32>, clk: %clk: i1, rst: %rst: i1) -> (result: !handshake.channel<i32>)
    %mul2.result = hw.instance "mul2" @handshake_muli_2(lhs: %e: !handshake.channel<i32>, rhs: %f: !handshake.channel<i32>, clk: %clk: i1, rst: %rst: i1) -> (result: !handshake.channel<i32>)
    hw.output %mul0.result, %mul1.result, %mul2.result : !handshake.channel<i32>, !handshake.channel<i32>, !handshake.channel<i32>
  }
  hw.module.extern @handshake_muli_0(in %lhs : !handshake.channel<i32>, in %rhs : !handshake.channel<i32>, in %clk : i1, in %rst : i1, out result : !handshake.channel<i32>) attributes {hw.name = "handshake.muli", hw.parameters = {DATA_TYPE = !handshake.channel<i32>, IMPL = "sequential", LATENCY = 9 : ui32, STEP = 4 : ui32}}
  hw.module.extern @handshake_muli_1(in %lhs : !handshake.channel<i32>, in %rhs : !handshake.channel<i32>, in %clk : i1, in %rst : i1, out result : !handshake.channel<i32>) attributes {hw.name = "handshake.muli", hw.parameters = {DATA_TYPE = !handshake.channel<i32>, IMPL = "pipelined", LATENCY = 4 : ui32, STEP = 1 : ui32}}
  hw.module.extern @handshake_muli_2(in %lhs : !handshake.channel<i32>, in %rhs : !handshake.channel<i32>, in %clk : i1, in %rst : i1, out result : !handshake.channel<i32>) attributes {hw.name = "handshake.muli", hw.parameters = {DATA_TYPE = !handshake.channel<i32>, IMPL = "sequential", ITER_WIDTH = 16 : ui32, LATENCY = 5 : ui32, STEP = 4 : ui32}}
}
