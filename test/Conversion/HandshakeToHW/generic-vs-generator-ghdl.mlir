// REQUIRES: ghdl
// RUN: rm -rf %t && mkdir -p %t && cd %t && for p in 1:1:1 2:2:3 8:3:5 9:4:511 32:16:4294967295 33:1:4294967296 64:16:9223372036854775808 100:7:1180591620717411303424; do \
// RUN:   w=${p%%%%:*}; r=${p#*:}; s=${r%%%%:*}; v=${r#*:}; mkdir c$w && cd c$w || exit 1; \
// RUN:   g="python3 %dynamatic_src_root/tools/unit-generators/vhdl/vhdl-unit-generator.py"; \
// RUN:   $g -n gen_init -o gen_init.vhd -t init -p bitwidth=$w 'extra_signals={}' initial_value=$v || exit 1; \
// RUN:   $g -n gen_init_control -o gen_init_control.vhd -t init -p bitwidth=0 'extra_signals={}' initial_value=0 || exit 1; \
// RUN:   $g -n gen_muli -o gen_muli.vhd -t muli -p bitwidth=$w latency=0 "impl='sequential'" step=$s 'extra_signals={}' || exit 1; \
// RUN:   ghdl -a --std=08 %dynamatic_src_root/data/vhdl/support/logic.vhd %dynamatic_src_root/data/vhdl/support/join.vhd %dynamatic_src_root/data/vhdl/handshake/generic/handshake_init_dataless.vhd %dynamatic_src_root/data/vhdl/handshake/generic/handshake_init.vhd %dynamatic_src_root/data/vhdl/handshake/generic/handshake_muli_sequential.vhd gen_init.vhd gen_init_control.vhd gen_muli.vhd %S/Inputs/generic-vs-generator-tb.vhd || exit 1; \
// RUN:   echo "width $w step $s value $v"; ghdl --elab-run --std=08 tb -gW=$w -gS=$s -gV=$v --ieee-asserts=disable 2>&1; cd ..; done | FileCheck %s

// The generic init and sequential multiplier are their generator's logic:
// each in lockstep with the unit the generator writes at the same
// parameters, at eight widths, steps and values. The generator is still what
// the timing characterization measures and what a unit with extra signals
// is built from, so the two must not drift apart.

// CHECK:      width 1 step 1 value 1
// CHECK-NEXT: equal to the generator's over
// CHECK-NEXT: width 2 step 2 value 3
// CHECK-NEXT: equal to the generator's over
// CHECK-NEXT: width 8 step 3 value 5
// CHECK-NEXT: equal to the generator's over
// CHECK-NEXT: width 9 step 4 value 511
// CHECK-NEXT: equal to the generator's over
// CHECK-NEXT: width 32 step 16 value 4294967295
// CHECK-NEXT: equal to the generator's over
// CHECK-NEXT: width 33 step 1 value 4294967296
// CHECK-NEXT: equal to the generator's over
// CHECK-NEXT: width 64 step 16 value 9223372036854775808
// CHECK-NEXT: equal to the generator's over
// CHECK-NEXT: width 100 step 7 value 1180591620717411303424
// CHECK-NEXT: equal to the generator's over
