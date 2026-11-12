// REQUIRES: ghdl
// RUN: rm -rf %t && mkdir -p %t && cd %t && n=0 && for p in 1:1:1:1:none 2:8:2:2:none 3:5:3:2:10110,00001 4:33:4:3:none 5:64:2:2:none 8:1:1:1:1 9:100:5:3:none 17:7:8:4:0000001,1111111,1010101; do \
// RUN:   n=$((n+1)); z=${p%%%%:*}; r=${p#*:}; w=${r%%%%:*}; r=${r#*:}; s=${r%%%%:*}; r=${r#*:}; c=${r%%%%:*}; t=${r#*:}; mkdir c$n && cd c$n || exit 1; \
// RUN:   g="python3 %dynamatic_src_root/tools/unit-generators/vhdl/vhdl-unit-generator.py"; d=%dynamatic_src_root/data/vhdl; \
// RUN:   $g -n gen_merge -o gen_merge.vhd -t merge -p size=$z bitwidth=$w 'extra_signals={}' tehb=1 || exit 1; \
// RUN:   $g -n gen_merge_bare -o gen_merge_bare.vhd -t merge -p size=$z bitwidth=$w 'extra_signals={}' tehb=0 || exit 1; \
// RUN:   $g -n gen_merge_ctl -o gen_merge_ctl.vhd -t merge -p size=$z bitwidth=0 'extra_signals={}' tehb=1 || exit 1; \
// RUN:   $g -n gen_merge_ctl_bare -o gen_merge_ctl_bare.vhd -t merge -p size=$z bitwidth=0 'extra_signals={}' tehb=0 || exit 1; \
// RUN:   $g -n gen_join -o gen_join.vhd -t top_join -p size=$z || exit 1; \
// RUN:   $g -n gen_blocker -o gen_blocker.vhd -t blocker -p size=$z bitwidth=$w 'extra_signals={}' || exit 1; \
// RUN:   cp $d/handshake/dataless/tehb.vhd tehb_dataless.vhd || exit 1; \
// RUN:   $g -n gen_queue -o gen_queue.vhd -t queue -p num_slots=$s bitwidth=$w size_width=$c space_width=$c "initial_tokens='$t'" || exit 1; \
// RUN:   ghdl -i --std=08 $d/support/types.vhd $d/support/logic.vhd $d/support/join.vhd $d/handshake/tehb.vhd tehb_dataless.vhd $d/handshake/generic/handshake_merge.vhd $d/handshake/generic/handshake_merge_dataless.vhd $d/handshake/generic/handshake_merge_notehb.vhd $d/handshake/generic/handshake_merge_notehb_dataless.vhd $d/handshake/generic/handshake_join.vhd $d/handshake/generic/handshake_blocker.vhd $d/handshake/generic/handshake_queue.vhd gen_*.vhd %S/Inputs/generic-vs-generator-2-tb.vhd && ghdl -m --std=08 tb || exit 1; \
// RUN:   echo "size $z width $w slots $s counts $c tokens $t"; ghdl -r --std=08 tb -gSIZE=$z -gW=$w -gSLOTS=$s -gCW=$c -gTOKENS=$t --ieee-asserts=disable 2>&1; cd ..; done | FileCheck %s

// The generic merges, join, blocker and queue are their generator's logic:
// each in lockstep with the unit the generator writes at the same
// parameters, at eight sizes, widths, depths and sets of tokens held at
// reset. The generator is still what the timing characterization measures
// and what a unit with extra signals is built from, so the two must not
// drift apart. (The slot without data is copied under another name: both
// slots are a tehb.vhd, and a GHDL that writes object files names them after
// the source file.)

// CHECK:      size 1 width 1 slots 1 counts 1 tokens none
// CHECK-NEXT: equal to the generator's over
// CHECK-NEXT: size 2 width 8 slots 2 counts 2 tokens none
// CHECK-NEXT: equal to the generator's over
// CHECK-NEXT: size 3 width 5 slots 3 counts 2 tokens 10110,00001
// CHECK-NEXT: equal to the generator's over
// CHECK-NEXT: size 4 width 33 slots 4 counts 3 tokens none
// CHECK-NEXT: equal to the generator's over
// CHECK-NEXT: size 5 width 64 slots 2 counts 2 tokens none
// CHECK-NEXT: equal to the generator's over
// CHECK-NEXT: size 8 width 1 slots 1 counts 1 tokens 1
// CHECK-NEXT: equal to the generator's over
// CHECK-NEXT: size 9 width 100 slots 5 counts 3 tokens none
// CHECK-NEXT: equal to the generator's over
// CHECK-NEXT: size 17 width 7 slots 8 counts 4 tokens 0000001,1111111,1010101
// CHECK-NEXT: equal to the generator's over
