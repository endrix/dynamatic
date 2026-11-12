// REQUIRES: ghdl
// RUN: rm -rf %t && mkdir -p %t
// RUN: dynamatic-opt %S/wrapper-roots.mlir --lower-handshake-to-hw > %t/roots.hw
// RUN: export-rtl %t/roots.hw %t/vhdl %dynamatic_src_root/data/rtl-config-vhdl.json --dynamatic-path %dynamatic_src_root --hdl vhdl
// RUN: ls %t/vhdl | FileCheck %s --implicit-check-not=leaf_wrapper --implicit-check-not=mid_wrapper --implicit-check-not=reader_wrapper
// RUN: cd %t/vhdl && ghdl -i --std=08 *.vhd && ghdl -m --std=08 top_wrapper && ghdl -m --std=08 other_wrapper

// The exported hierarchy of wrapper-roots.mlir: a file per module, and a
// wrapper for the two modules that no other one instantiates. Each wrapper
// elaborates with everything below it.

// CHECK: leaf.vhd
// CHECK: mid.vhd
// CHECK: other.vhd
// CHECK: other_wrapper.vhd
// CHECK: reader.vhd
// CHECK: top.vhd
// CHECK: top_wrapper.vhd
