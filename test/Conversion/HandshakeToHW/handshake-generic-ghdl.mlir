// REQUIRES: ghdl
// RUN: rm -rf %t && mkdir -p %t
// RUN: cd %t && ghdl -a --std=08 %dynamatic_src_root/data/vhdl/support/logic.vhd %dynamatic_src_root/data/vhdl/support/join.vhd %dynamatic_src_root/data/vhdl/handshake/generic/handshake_*.vhd %S/Inputs/handshake-generic-tb.vhd
// RUN: cd %t && ghdl --elab-run --std=08 tb -gW=1 2>&1 | FileCheck %s
// RUN: cd %t && ghdl --elab-run --std=08 tb -gW=2 2>&1 | FileCheck %s
// RUN: cd %t && ghdl --elab-run --std=08 tb -gW=8 2>&1 | FileCheck %s
// RUN: cd %t && ghdl --elab-run --std=08 tb -gW=32 2>&1 | FileCheck %s
// RUN: cd %t && ghdl --elab-run --std=08 tb -gW=33 2>&1 | FileCheck %s
// RUN: cd %t && ghdl --elab-run --std=08 tb -gW=60 2>&1 | FileCheck %s

// The generic handshake units written from their generator's logic
// (data/vhdl/handshake/generic), simulated: one entity per unit kind has to
// be right at every width, a width of one and one above 32 bits included.

// A wrong result stops the run before this line.
// CHECK: checks as expected
