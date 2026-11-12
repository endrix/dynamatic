// REQUIRES: ghdl
// RUN: rm -rf %t && mkdir -p %t && cd %t && for w in 1 2 8 12 16 17 32 33 64; do \
// RUN:   mkdir c$w && cd c$w || exit 1; \
// RUN:   g="python3 %dynamatic_src_root/tools/unit-generators/vhdl/vhdl-unit-generator.py"; d=%dynamatic_src_root/data/vhdl; \
// RUN:   for u in divui divsi remui remsi; do $g -n gen_$u -o gen_$u.vhd -t $u -p bitwidth=$w latency=$((w + 1)) "impl='sequential'" 'extra_signals={}' || exit 1; done; \
// RUN:   ghdl -i --std=08 $d/support/logic.vhd $d/support/join.vhd $d/handshake/generic/handshake_divider_sequential.vhd gen_*.vhd %S/Inputs/generic-vs-generator-4-tb.vhd && ghdl -m --std=08 tb || exit 1; \
// RUN:   echo "width $w"; ghdl -r --std=08 tb -gW=$w --ieee-asserts=disable 2>&1; cd ..; done | FileCheck %s

// The generic sequential dividers are their generator's logic: each of the
// four units in lockstep with the one the generator writes at the same
// width, at nine widths, under operands that include a zero divisor, a
// small one, and the most negative dividend over minus one. The generator
// is still what the timing characterization measures, so the two must not
// drift apart.

// CHECK:      width 1
// CHECK-NEXT: equal to the generator's over
// CHECK-NEXT: width 2
// CHECK-NEXT: equal to the generator's over
// CHECK-NEXT: width 8
// CHECK-NEXT: equal to the generator's over
// CHECK-NEXT: width 12
// CHECK-NEXT: equal to the generator's over
// CHECK-NEXT: width 16
// CHECK-NEXT: equal to the generator's over
// CHECK-NEXT: width 17
// CHECK-NEXT: equal to the generator's over
// CHECK-NEXT: width 32
// CHECK-NEXT: equal to the generator's over
// CHECK-NEXT: width 33
// CHECK-NEXT: equal to the generator's over
// CHECK-NEXT: width 64
// CHECK-NEXT: equal to the generator's over
