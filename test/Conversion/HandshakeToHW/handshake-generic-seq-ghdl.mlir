// REQUIRES: ghdl
// RUN: rm -rf %t && mkdir -p %t
// RUN: cd %t && ghdl -a --std=08 %dynamatic_src_root/data/vhdl/support/logic.vhd %dynamatic_src_root/data/vhdl/support/join.vhd %dynamatic_src_root/data/vhdl/handshake/generic/handshake_init_dataless.vhd %dynamatic_src_root/data/vhdl/handshake/generic/handshake_init.vhd %dynamatic_src_root/data/vhdl/handshake/generic/handshake_muli_sequential.vhd %S/Inputs/handshake-generic-seq-tb.vhd
// RUN: cd %t && ghdl --elab-run --std=08 tb -gW=1 -gS=1 -gV=1 -gBITS=1 2>&1 | FileCheck %s
// RUN: cd %t && ghdl --elab-run --std=08 tb -gW=8 -gS=3 -gV=5 -gBITS=00000101 2>&1 | FileCheck %s
// RUN: cd %t && ghdl --elab-run --std=08 tb -gW=8 -gS=8 -gV=255 -gBITS=11111111 2>&1 | FileCheck %s
// RUN: cd %t && ghdl --elab-run --std=08 tb -gW=32 -gS=16 -gV=4294967295 -gBITS=11111111111111111111111111111111 2>&1 | FileCheck %s
// RUN: cd %t && ghdl --elab-run --std=08 tb -gW=33 -gS=4 -gV=4294967296 -gBITS=100000000000000000000000000000000 2>&1 | FileCheck %s
// RUN: cd %t && ghdl --elab-run --std=08 tb -gW=70 -gS=16 -gV=590295810358705651712 -gBITS=1000000000000000000000000000000000000000000000000000000000000000000000 2>&1 | FileCheck %s
// RUN: cd %t && not ghdl --elab-run --std=08 tb -gW=8 -gS=3 -gV=256 -gBITS=00000000 2>&1 | FileCheck %s --check-prefix=WIDE
// RUN: cd %t && not ghdl --elab-run --std=08 tb -gW=8 -gS=9 -gV=5 -gBITS=00000101 2>&1 | FileCheck %s --check-prefix=STEP

// The generic init and sequential multiplier (data/vhdl/handshake/generic),
// simulated: the init's value from its decimal string at widths below and
// above 32 and 64 bits, the multiplier's product, latency and handshake at
// several steps. A wrong result stops the run before the summary line.

// CHECK: checks as expected
// WIDE: handshake_init: INITIAL_VALUE 256 does not fit the width
// STEP: handshake_muli_sequential: a step of 9 for a width of 8
