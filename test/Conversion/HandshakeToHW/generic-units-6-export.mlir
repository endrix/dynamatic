// REQUIRES: ghdl
// RUN: rm -rf %t && mkdir -p %t
// RUN: dynamatic-opt %s --lower-handshake-to-hw > %t/genunits6.hw
// RUN: export-rtl %t/genunits6.hw %t/vhdl %dynamatic_src_root/data/rtl-config-vhdl.json --dynamatic-path %dynamatic_src_root --hdl vhdl
// RUN: FileCheck %s --input-file=%t/vhdl/genunits6.vhd
// RUN: ls %t/vhdl | FileCheck %s --check-prefix=FILES
// RUN: cd %t/vhdl && ghdl -i --std=08 *.vhd && ghdl -m --std=08 genunits6

// The sequential integer dividers: one generic entity for the four units
// (data/vhdl/handshake/generic/handshake_divider_sequential.vhd), with an
// architecture per unit. The pipelined dividers, which instantiate the Vitis
// cores, are generated.

// CHECK-DAG: div0 : entity work.handshake_divider_sequential(divui) generic map(17)
// CHECK-DAG: div1 : entity work.handshake_divider_sequential(divui) generic map(16)
// CHECK-DAG: div2 : entity work.handshake_divider_sequential(divsi) generic map(12)
// CHECK-DAG: rem0 : entity work.handshake_divider_sequential(remui) generic map(12)
// CHECK-DAG: rem1 : entity work.handshake_divider_sequential(remsi) generic map(1)
// CHECK-DAG: div3 : entity work.handshake_divui_{{[0-9]+}}(arch)
// CHECK-DAG: rem2 : entity work.handshake_remsi_{{[0-9]+}}(arch)

// FILES:      handshake_divider_sequential.vhd
// FILES-NEXT: handshake_divui_{{[0-9]+}}.vhd
// FILES-NOT:  handshake_div
// FILES:      handshake_remsi_{{[0-9]+}}.vhd
// FILES-NOT:  handshake_rem
// FILES:      join.vhd

handshake.func @genunits6(%a: !handshake.channel<i17>, %b: !handshake.channel<i17>, %c: !handshake.channel<i16>, %d: !handshake.channel<i16>, %e: !handshake.channel<i12>, %f: !handshake.channel<i12>, %g: !handshake.channel<i1>, %h: !handshake.channel<i1>, %x: !handshake.channel<i32>, %y: !handshake.channel<i32>, %start: !handshake.control<>) -> (!handshake.channel<i17>, !handshake.channel<i16>, !handshake.channel<i12>, !handshake.channel<i12>, !handshake.channel<i1>, !handshake.channel<i32>, !handshake.channel<i32>, !handshake.control<>) attributes {argNames = ["a", "b", "c", "d", "e", "f", "g", "h", "x", "y", "start"], resNames = ["q0", "q1", "q2", "r0", "r1", "q3", "r2", "end"]} {
  %q0 = divui %a, %b {handshake.name = "div0", latency = 18, hw.parameters = {IMPL = "sequential"}} : <i17>
  %q1 = divui %c, %d {handshake.name = "div1", latency = 17, hw.parameters = {IMPL = "sequential"}} : <i16>
  %e0, %e1 = fork [2] %e {handshake.name = "fork0"} : <i12>
  %f0, %f1 = fork [2] %f {handshake.name = "fork1"} : <i12>
  %q2 = divsi %e0, %f0 {handshake.name = "div2", latency = 13, hw.parameters = {IMPL = "sequential"}} : <i12>
  %r0 = remui %e1, %f1 {handshake.name = "rem0", latency = 13, hw.parameters = {IMPL = "sequential"}} : <i12>
  %r1 = remsi %g, %h {handshake.name = "rem1", latency = 2, hw.parameters = {IMPL = "sequential"}} : <i1>
  %x0, %x1 = fork [2] %x {handshake.name = "fork2"} : <i32>
  %y0, %y1 = fork [2] %y {handshake.name = "fork3"} : <i32>
  %q3 = divui %x0, %y0 {handshake.name = "div3", latency = 35} : <i32>
  %r2 = remsi %x1, %y1 {handshake.name = "rem2", latency = 35} : <i32>
  end {handshake.name = "end0"} %q0, %q1, %q2, %r0, %r1, %q3, %r2, %start : <i17>, <i16>, <i12>, <i12>, <i1>, <i32>, <i32>, <>
}
