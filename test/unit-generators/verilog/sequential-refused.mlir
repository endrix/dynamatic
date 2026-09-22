// RUN: %export-verilog > %t.log 2>&1 || true
// RUN: FileCheck %s < %t.log
// RUN: %export-smv > %t.smv.log 2>&1 || true
// RUN: FileCheck %s < %t.smv.log

// THE OTHER BACKENDS REFUSE A UNIT THEY DO NOT HAVE. `esa-unit-impl` names
// the sequential divider on a cell-library target, and only the VHDL
// configuration can build one. The Verilog configuration's entries are
// constrained to the pipelined implementation, so an operation that asks for
// the sequential one finds no component instead of quietly getting the Vitis
// unit back at another latency.

// CHECK: Failed to find matching RTL component
module {
  hw.module @test(in %a : !handshake.channel<i32>, in %b : !handshake.channel<i32>, in %clk : i1, in %rst : i1, out out0 : !handshake.channel<i32>) {
    %d.result = hw.instance "d" @handshake_divsi_0(lhs: %a: !handshake.channel<i32>, rhs: %b: !handshake.channel<i32>, clk: %clk: i1, rst: %rst: i1) -> (result: !handshake.channel<i32>)
    hw.output %d.result : !handshake.channel<i32>
  }
  hw.module.extern @handshake_divsi_0(in %lhs : !handshake.channel<i32>, in %rhs : !handshake.channel<i32>, in %clk : i1, in %rst : i1, out result : !handshake.channel<i32>) attributes {hw.name = "handshake.divsi", hw.parameters = {DATA_TYPE = !handshake.channel<i32>, IMPL = "sequential", LATENCY = 33 : ui32}}
}
