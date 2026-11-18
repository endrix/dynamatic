// REQUIRES: ghdl
// RUN: rm -rf %t && mkdir -p %t && cd %t && d=%dynamatic_src_root/data/vhdl/handshake && \
// RUN: ghdl -a --std=08 $d/generic/handshake_bundle.vhd $d/generic/handshake_unbundle.vhd $d/generic/handshake_init_dataless.vhd $d/generic/handshake_init.vhd $d/dataless/oehb.vhd $d/oehb.vhd $d/generic/handshake_init_state.vhd $d/generic/handshake_buffer_state.vhd %S/Inputs/state-loop-units-tb.vhd && \
// RUN: for p in 1:0 1:1 5:19 8:255 33:4294967296 64:18446744073709551615; do \
// RUN:   ghdl --elab-run --std=08 tb -gW=${p%%%%:*} -gINIT=${p#*:} --ieee-asserts=disable 2>&1; done | FileCheck %s

// The two units of a state register's loop (handshake_init_state and
// handshake_buffer_state: state-loop.mlir says what the loop is and when the
// lowering names its units) against the units they stand for, handshake_init
// and the oehb, each pair closed into the loop with the bundle and the
// unbundle. At six widths and reset values the two loops are run in lockstep
// under a next value that changes at every cycle and resets that fall
// anywhere, and agree at every wire of the loop in every cycle: the value
// read, the init's output, and the eight valids and readies, which nothing
// outside a loop reads and a whole design therefore cannot show
// (state-loop-ghdl.mlir runs one).

// CHECK:      W=1 INIT=0: 20000 cycles agree, {{[0-9]+}} resets
// CHECK-NEXT: simulation stopped
// CHECK-NEXT: W=1 INIT=1: 20000 cycles agree, {{[0-9]+}} resets
// CHECK-NEXT: simulation stopped
// CHECK-NEXT: W=5 INIT=19: 20000 cycles agree, {{[0-9]+}} resets
// CHECK-NEXT: simulation stopped
// CHECK-NEXT: W=8 INIT=255: 20000 cycles agree, {{[0-9]+}} resets
// CHECK-NEXT: simulation stopped
// CHECK-NEXT: W=33 INIT=4294967296: 20000 cycles agree, {{[0-9]+}} resets
// CHECK-NEXT: simulation stopped
// CHECK-NEXT: W=64 INIT=18446744073709551615: 20000 cycles agree, {{[0-9]+}} resets
// CHECK-NEXT: simulation stopped
