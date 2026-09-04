// RUN: %export-vhdl
// RUN: FileCheck %s -input-file %t/handshake_remui_0.vhd

// The unsigned remainder unit wraps the urem core from vitis_hls_cores.vhd
// under its own wrapper name, at the channel's width, and its valid travels
// through the same latency buffer the divisions use (bitwidth + 3 cycles).
module {
  hw.module @test(in %k : !handshake.channel<i32>, in %n : !handshake.channel<i32>, in %start : !handshake.control<>, in %clk : i1, in %rst : i1, out out0 : !handshake.channel<i32>, out end : !handshake.control<>) {
    %remui0.result = hw.instance "remui0" @handshake_remui_0(lhs: %k: !handshake.channel<i32>, rhs: %n: !handshake.channel<i32>, clk: %clk: i1, rst: %rst: i1) -> (result: !handshake.channel<i32>)
    hw.output %remui0.result, %start : !handshake.channel<i32>, !handshake.control<>
  }

  // CHECK-LABEL: architecture arch of handshake_remui_0
  // CHECK: valid_buffer : entity work.handshake_remui_0_valid_buffer(arch)
  // CHECK: remui_vitis_hls_wrapper_U1 : entity work.remui_vitis_hls_wrapper
  // CHECK-NEXT: generic map(32, 32, 32)
  hw.module.extern @handshake_remui_0(in %lhs : !handshake.channel<i32>, in %rhs : !handshake.channel<i32>, in %clk : i1, in %rst : i1, out result : !handshake.channel<i32>) attributes {hw.name = "handshake.remui", hw.parameters = {DATA_TYPE = !handshake.channel<i32>, LATENCY = 35 : ui32}}
}
