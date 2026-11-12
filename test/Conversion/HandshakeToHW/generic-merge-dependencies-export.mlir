// REQUIRES: ghdl
// RUN: rm -rf %t && mkdir -p %t
// RUN: dynamatic-opt %s --lower-handshake-to-hw > %t/mergedeps.hw
// RUN: export-rtl %t/mergedeps.hw %t/vhdl %dynamatic_src_root/data/rtl-config-vhdl.json --dynamatic-path %dynamatic_src_root --hdl vhdl
// RUN: ls %t/vhdl | FileCheck %s
// RUN: cd %t/vhdl && ghdl -i --std=08 *.vhd && ghdl -m --std=08 mergedeps

// A generic merge brings what it is built from: its arbiter and the slot
// behind it, with or without data, in a design that has no other user of
// them.

// CHECK:      handshake_merge.vhd
// CHECK-NEXT: handshake_merge_dataless.vhd
// CHECK-NEXT: handshake_merge_notehb.vhd
// CHECK-NEXT: handshake_merge_notehb_dataless.vhd
// CHECK:      tehb.vhd
// CHECK-NEXT: tehb_dataless.vhd
// CHECK-NEXT: types.vhd

handshake.func @mergedeps(%a: !handshake.channel<i12>, %b: !handshake.channel<i12>, %x: !handshake.control<>, %y: !handshake.control<>) -> (!handshake.channel<i12>, !handshake.control<>) attributes {argNames = ["a", "b", "x", "y"], resNames = ["om", "end"]} {
  %m0 = merge %a, %b {handshake.name = "merge0"} : <i12>
  %m1 = merge %x, %y {handshake.name = "merge1"} : <>
  end {handshake.name = "end0"} %m0, %m1 : <i12>, <>
}
