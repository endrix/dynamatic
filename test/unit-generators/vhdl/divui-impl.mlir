// RUN: %export-vhdl
// RUN: FileCheck %s -input-file %t/handshake_divui_0.vhd --check-prefix=SEQ
// RUN: FileCheck %s -input-file %t/handshake_divui_1.vhd --check-prefix=PIPE

// The two dividers. IMPL=sequential is one register set stepped BITWIDTH
// times, the quotient held until taken; IMPL=pipelined is the Vitis IP
// behind a valid buffer of the unit's latency.

// SEQ: entity handshake_divui_0_join is
// SEQ: entity handshake_divui_0 is
// SEQ: signal busy, done : std_logic;
// SEQ: cal  <= ('0' & comb) - ('0' & divisor);
// SEQ-NOT: divui_vitis_hls_wrapper
// SEQ: result_valid <= done;

// PIPE: entity handshake_divui_1_valid_buffer is
// PIPE: entity handshake_divui_1 is
// PIPE: divui_vitis_hls_wrapper_U1 : entity work.divui_vitis_hls_wrapper
module {
  hw.module @test(in %a : !handshake.channel<i32>, in %b : !handshake.channel<i32>, in %c : !handshake.channel<i32>, in %d : !handshake.channel<i32>, in %clk : i1, in %rst : i1, out out0 : !handshake.channel<i32>, out out1 : !handshake.channel<i32>) {
    %div0.result = hw.instance "div0" @handshake_divui_0(lhs: %a: !handshake.channel<i32>, rhs: %b: !handshake.channel<i32>, clk: %clk: i1, rst: %rst: i1) -> (result: !handshake.channel<i32>)
    %div1.result = hw.instance "div1" @handshake_divui_1(lhs: %c: !handshake.channel<i32>, rhs: %d: !handshake.channel<i32>, clk: %clk: i1, rst: %rst: i1) -> (result: !handshake.channel<i32>)
    hw.output %div0.result, %div1.result : !handshake.channel<i32>, !handshake.channel<i32>
  }
  hw.module.extern @handshake_divui_0(in %lhs : !handshake.channel<i32>, in %rhs : !handshake.channel<i32>, in %clk : i1, in %rst : i1, out result : !handshake.channel<i32>) attributes {hw.name = "handshake.divui", hw.parameters = {DATA_TYPE = !handshake.channel<i32>, IMPL = "sequential", LATENCY = 35 : ui32}}
  hw.module.extern @handshake_divui_1(in %lhs : !handshake.channel<i32>, in %rhs : !handshake.channel<i32>, in %clk : i1, in %rst : i1, out result : !handshake.channel<i32>) attributes {hw.name = "handshake.divui", hw.parameters = {DATA_TYPE = !handshake.channel<i32>, IMPL = "pipelined", LATENCY = 35 : ui32}}
}
