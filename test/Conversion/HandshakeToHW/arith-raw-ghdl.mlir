// REQUIRES: ghdl
// RUN: rm -rf %t && mkdir -p %t
// RUN: cd %t && ghdl -a --std=08 %dynamatic_src_root/data/vhdl/arith/raw/*.vhd %S/Inputs/arith-raw-tb.vhd
// RUN: cd %t && ghdl --elab-run --std=08 tb -gW=1 2>&1 | FileCheck %s
// RUN: cd %t && ghdl --elab-run --std=08 tb -gW=2 2>&1 | FileCheck %s
// RUN: cd %t && ghdl --elab-run --std=08 tb -gW=8 2>&1 | FileCheck %s
// RUN: cd %t && ghdl --elab-run --std=08 tb -gW=31 2>&1 | FileCheck %s
// RUN: cd %t && ghdl --elab-run --std=08 tb -gW=32 2>&1 | FileCheck %s
// RUN: cd %t && ghdl --elab-run --std=08 tb -gW=40 2>&1 | FileCheck %s

// The arith units on raw wires, one generic entity per operation
// (data/vhdl/arith/raw): each of them at six widths, against results the
// testbench computes itself. A width of one is a port that is a vector of one
// element; 31 is the widest shift amount `to_integer` takes whole, 32 and 40
// the widths whose amount is read in two parts.

// CHECK: arith raw, W={{[0-9]+}}: {{[0-9]+}} checks as expected
// CHECK-NOT: failure
