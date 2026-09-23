// RUN: %export-vhdl
// RUN: ls %t | FileCheck %s

// A sequential divider does not pull in the Vitis HLS cores. The four
// divider entries carried "dependencies": ["vitis_hls_cores"] whatever the
// implementation, so an export whose dividers are all sequential shipped
// vitis_hls_cores.vhd although nothing instantiated it. The pipelined unit
// still gets it (divui-impl.mlir, divsi-remui-remsi-impl.mlir).

// CHECK: handshake_divsi_0.vhd
// CHECK: handshake_divui_0.vhd
// CHECK: handshake_remsi_0.vhd
// CHECK: handshake_remui_0.vhd
// CHECK-NOT: vitis_hls_cores.vhd
module {
  hw.module @test(in %a : !handshake.channel<i32>, in %b : !handshake.channel<i32>, in %c : !handshake.channel<i32>, in %d : !handshake.channel<i32>, in %e : !handshake.channel<i32>, in %f : !handshake.channel<i32>, in %g : !handshake.channel<i32>, in %h : !handshake.channel<i32>, in %clk : i1, in %rst : i1, out out0 : !handshake.channel<i32>, out out1 : !handshake.channel<i32>, out out2 : !handshake.channel<i32>, out out3 : !handshake.channel<i32>) {
    %0 = hw.instance "div0" @handshake_divui_0(lhs: %a: !handshake.channel<i32>, rhs: %b: !handshake.channel<i32>, clk: %clk: i1, rst: %rst: i1) -> (result: !handshake.channel<i32>)
    %1 = hw.instance "div1" @handshake_divsi_0(lhs: %c: !handshake.channel<i32>, rhs: %d: !handshake.channel<i32>, clk: %clk: i1, rst: %rst: i1) -> (result: !handshake.channel<i32>)
    %2 = hw.instance "rem0" @handshake_remui_0(lhs: %e: !handshake.channel<i32>, rhs: %f: !handshake.channel<i32>, clk: %clk: i1, rst: %rst: i1) -> (result: !handshake.channel<i32>)
    %3 = hw.instance "rem1" @handshake_remsi_0(lhs: %g: !handshake.channel<i32>, rhs: %h: !handshake.channel<i32>, clk: %clk: i1, rst: %rst: i1) -> (result: !handshake.channel<i32>)
    hw.output %0, %1, %2, %3 : !handshake.channel<i32>, !handshake.channel<i32>, !handshake.channel<i32>, !handshake.channel<i32>
  }
  hw.module.extern @handshake_divui_0(in %lhs : !handshake.channel<i32>, in %rhs : !handshake.channel<i32>, in %clk : i1, in %rst : i1, out result : !handshake.channel<i32>) attributes {hw.name = "handshake.divui", hw.parameters = {DATA_TYPE = !handshake.channel<i32>, IMPL = "sequential", LATENCY = 33 : ui32}}
  hw.module.extern @handshake_divsi_0(in %lhs : !handshake.channel<i32>, in %rhs : !handshake.channel<i32>, in %clk : i1, in %rst : i1, out result : !handshake.channel<i32>) attributes {hw.name = "handshake.divsi", hw.parameters = {DATA_TYPE = !handshake.channel<i32>, IMPL = "sequential", LATENCY = 33 : ui32}}
  hw.module.extern @handshake_remui_0(in %lhs : !handshake.channel<i32>, in %rhs : !handshake.channel<i32>, in %clk : i1, in %rst : i1, out result : !handshake.channel<i32>) attributes {hw.name = "handshake.remui", hw.parameters = {DATA_TYPE = !handshake.channel<i32>, IMPL = "sequential", LATENCY = 33 : ui32}}
  hw.module.extern @handshake_remsi_0(in %lhs : !handshake.channel<i32>, in %rhs : !handshake.channel<i32>, in %clk : i1, in %rst : i1, out result : !handshake.channel<i32>) attributes {hw.name = "handshake.remsi", hw.parameters = {DATA_TYPE = !handshake.channel<i32>, IMPL = "sequential", LATENCY = 33 : ui32}}
}
