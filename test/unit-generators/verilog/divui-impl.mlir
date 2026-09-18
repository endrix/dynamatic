// RUN: %export-verilog
// RUN: FileCheck %s -input-file %t/test.v --check-prefix=INST
// RUN: FileCheck %s -input-file %t/divui_sequential.v --check-prefix=SEQ
// RUN: FileCheck %s -input-file %t/divui.v --check-prefix=PIPE

// The two dividers in the Verilog configuration. IMPL=sequential is the
// restoring divider that runs one quotient bit a cycle on one register set;
// IMPL=pipelined is the Vitis IP, one stage a bit, the unit the
// configuration has always emitted.

// INST: divui_sequential #(.DATA_TYPE(32)) div0(
// INST: divui #(.DATA_TYPE(32)) div1(

// SEQ: module divui_sequential #(
// SEQ: assign idle = (~busy) & ((~done) | result_ready);
// SEQ: assign cal  = {1'b0, comb} - {1'b0, divisor};
// SEQ: assign result_valid = done;

// PIPE: module divui #(
// PIPE: module divui_vitis_hls_wrapper #(
module {
  hw.module @test(in %a : !handshake.channel<i32>, in %b : !handshake.channel<i32>, in %c : !handshake.channel<i32>, in %d : !handshake.channel<i32>, in %clk : i1, in %rst : i1, out out0 : !handshake.channel<i32>, out out1 : !handshake.channel<i32>) {
    %div0.result = hw.instance "div0" @handshake_divui_0(lhs: %a: !handshake.channel<i32>, rhs: %b: !handshake.channel<i32>, clk: %clk: i1, rst: %rst: i1) -> (result: !handshake.channel<i32>)
    %div1.result = hw.instance "div1" @handshake_divui_1(lhs: %c: !handshake.channel<i32>, rhs: %d: !handshake.channel<i32>, clk: %clk: i1, rst: %rst: i1) -> (result: !handshake.channel<i32>)
    hw.output %div0.result, %div1.result : !handshake.channel<i32>, !handshake.channel<i32>
  }
  hw.module.extern @handshake_divui_0(in %lhs : !handshake.channel<i32>, in %rhs : !handshake.channel<i32>, in %clk : i1, in %rst : i1, out result : !handshake.channel<i32>) attributes {hw.name = "handshake.divui", hw.parameters = {DATA_TYPE = !handshake.channel<i32>, IMPL = "sequential", LATENCY = 33 : ui32}}
  hw.module.extern @handshake_divui_1(in %lhs : !handshake.channel<i32>, in %rhs : !handshake.channel<i32>, in %clk : i1, in %rst : i1, out result : !handshake.channel<i32>) attributes {hw.name = "handshake.divui", hw.parameters = {DATA_TYPE = !handshake.channel<i32>, IMPL = "pipelined", LATENCY = 35 : ui32}}
}
