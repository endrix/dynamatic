// RUN: %export-smv
// RUN: FileCheck %s -input-file %t/handshake_divui_0.smv --check-prefix=SEQ
// RUN: FileCheck %s -input-file %t/handshake_divui_1.smv --check-prefix=PIPE

// The SMV model follows the op's own latency, and IMPL=sequential gets the
// model of a unit that runs one division at a time: a 32-bit sequential
// divider takes a pair every 33 cycles, where the pipelined Vitis IP takes
// one every cycle.

// SEQ: latency=33
// SEQ: impl="sequential"
// SEQ: VAR busy : boolean;
// SEQ: VAR step : 0..31;
// SEQ: DEFINE accept := lhs_valid & rhs_valid & idle;
// SEQ: DEFINE outs_valid := done;

// PIPE: latency=35
// PIPE: impl="pipelined"
// PIPE: VAR inner_delay_buffer :
module {
  hw.module @test(in %a : !handshake.channel<i32>, in %b : !handshake.channel<i32>, in %c : !handshake.channel<i32>, in %d : !handshake.channel<i32>, in %clk : i1, in %rst : i1, out out0 : !handshake.channel<i32>, out out1 : !handshake.channel<i32>) {
    %div0.result = hw.instance "div0" @handshake_divui_0(lhs: %a: !handshake.channel<i32>, rhs: %b: !handshake.channel<i32>, clk: %clk: i1, rst: %rst: i1) -> (result: !handshake.channel<i32>)
    %div1.result = hw.instance "div1" @handshake_divui_1(lhs: %c: !handshake.channel<i32>, rhs: %d: !handshake.channel<i32>, clk: %clk: i1, rst: %rst: i1) -> (result: !handshake.channel<i32>)
    hw.output %div0.result, %div1.result : !handshake.channel<i32>, !handshake.channel<i32>
  }
  hw.module.extern @handshake_divui_0(in %lhs : !handshake.channel<i32>, in %rhs : !handshake.channel<i32>, in %clk : i1, in %rst : i1, out result : !handshake.channel<i32>) attributes {hw.name = "handshake.divui", hw.parameters = {DATA_TYPE = !handshake.channel<i32>, IMPL = "sequential", LATENCY = 33 : ui32}}
  hw.module.extern @handshake_divui_1(in %lhs : !handshake.channel<i32>, in %rhs : !handshake.channel<i32>, in %clk : i1, in %rst : i1, out result : !handshake.channel<i32>) attributes {hw.name = "handshake.divui", hw.parameters = {DATA_TYPE = !handshake.channel<i32>, IMPL = "pipelined", LATENCY = 35 : ui32}}
}
