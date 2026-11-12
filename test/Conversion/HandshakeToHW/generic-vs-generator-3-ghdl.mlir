// REQUIRES: ghdl
// RUN: rm -rf %t && mkdir -p %t && cd %t && n=0 && for p in 2:2:1:2 2:8:1:3 3:5:2:2 4:33:2:4 5:64:3:2 8:2:5:2 9:100:4:3 17:7:5:5; do \
// RUN:   n=$((n+1)); z=${p%%%%:*}; r=${p#*:}; w=${r%%%%:*}; r=${r#*:}; i=${r%%%%:*}; c=${r#*:}; mkdir c$n && cd c$n || exit 1; \
// RUN:   g="python3 %dynamatic_src_root/tools/unit-generators/vhdl/vhdl-unit-generator.py"; d=%dynamatic_src_root/data/vhdl; \
// RUN:   $g -n gen_mux -o gen_mux.vhd -t mux -p size=$z data_bitwidth=$w index_bitwidth=$i 'extra_signals={}' tehb=1 || exit 1; \
// RUN:   $g -n gen_mux_bare -o gen_mux_bare.vhd -t mux -p size=$z data_bitwidth=$w index_bitwidth=$i 'extra_signals={}' tehb=0 || exit 1; \
// RUN:   $g -n gen_mux_ctl -o gen_mux_ctl.vhd -t mux -p size=$z data_bitwidth=0 index_bitwidth=$i 'extra_signals={}' tehb=1 || exit 1; \
// RUN:   $g -n gen_mux_ctl_bare -o gen_mux_ctl_bare.vhd -t mux -p size=$z data_bitwidth=0 index_bitwidth=$i 'extra_signals={}' tehb=0 || exit 1; \
// RUN:   $g -n gen_cmerge -o gen_cmerge.vhd -t control_merge -p size=$z data_bitwidth=$w index_bitwidth=$i 'extra_signals={}' || exit 1; \
// RUN:   $g -n gen_cmerge_ctl -o gen_cmerge_ctl.vhd -t control_merge -p size=$z data_bitwidth=0 index_bitwidth=$i 'extra_signals={}' || exit 1; \
// RUN:   $g -n gen_bundle -o gen_bundle.vhd -t bundle -p "form='channel'" data_width=$w 'extra_down={}' 'extra_up={}' || exit 1; \
// RUN:   $g -n gen_bundle_space -o gen_bundle_space.vhd -t bundle -p "form='channel'" data_width=$w 'extra_down={}' "extra_up={'space': $c}" || exit 1; \
// RUN:   $g -n gen_bundle_control -o gen_bundle_control.vhd -t bundle -p "form='control'" data_width=0 'extra_down={}' 'extra_up={}' || exit 1; \
// RUN:   $g -n gen_unbundle -o gen_unbundle.vhd -t unbundle -p "form='channel'" data_width=$w 'extra_down={}' 'extra_up={}' || exit 1; \
// RUN:   $g -n gen_unbundle_size -o gen_unbundle_size.vhd -t unbundle -p "form='channel'" data_width=$w "extra_down={'size': $c}" 'extra_up={}' || exit 1; \
// RUN:   $g -n gen_unbundle_control -o gen_unbundle_control.vhd -t unbundle -p "form='control'" data_width=0 'extra_down={}' 'extra_up={}' || exit 1; \
// RUN:   cp $d/handshake/dataless/tehb.vhd tehb_dataless.vhd && cp $d/handshake/dataless/fork.vhd fork_dataless.vhd || exit 1; h=$d/handshake/generic; \
// RUN:   ghdl -i --std=08 $d/support/types.vhd $d/support/logic.vhd $d/support/eager_fork_register_block.vhd $d/handshake/tehb.vhd tehb_dataless.vhd fork_dataless.vhd $h/handshake_merge.vhd $h/handshake_merge_dataless.vhd $h/handshake_mux.vhd $h/handshake_mux_dataless.vhd $h/handshake_control_merge.vhd $h/handshake_control_merge_dataless.vhd $h/handshake_bundle.vhd $h/handshake_bundle_space.vhd $h/handshake_bundle_control.vhd $h/handshake_unbundle.vhd $h/handshake_unbundle_size.vhd $h/handshake_unbundle_control.vhd gen_*.vhd %S/Inputs/generic-vs-generator-3-tb.vhd && ghdl -m --std=08 tb || exit 1; \
// RUN:   echo "size $z width $w index $i count $c"; ghdl -r --std=08 tb -gSIZE=$z -gW=$w -gIW=$i -gCW=$c --ieee-asserts=disable 2>&1; cd ..; done | FileCheck %s

// The generic muxes, control merges, bundles and unbundles are their
// generator's logic: each in lockstep with the unit the generator writes at
// the same parameters, at eight sizes and widths (an index wider than the
// inputs need among them). The generator is still what the timing
// characterization measures and what a unit with extra signals is built
// from, so the two must not drift apart. (The slot and the fork without
// data are copied under another name: each shares its file name with the one
// with data, and a GHDL that writes object files names them after the
// source file.)

// CHECK:      size 2 width 2 index 1 count 2
// CHECK-NEXT: equal to the generator's over
// CHECK-NEXT: size 2 width 8 index 1 count 3
// CHECK-NEXT: equal to the generator's over
// CHECK-NEXT: size 3 width 5 index 2 count 2
// CHECK-NEXT: equal to the generator's over
// CHECK-NEXT: size 4 width 33 index 2 count 4
// CHECK-NEXT: equal to the generator's over
// CHECK-NEXT: size 5 width 64 index 3 count 2
// CHECK-NEXT: equal to the generator's over
// CHECK-NEXT: size 8 width 2 index 5 count 2
// CHECK-NEXT: equal to the generator's over
// CHECK-NEXT: size 9 width 100 index 4 count 3
// CHECK-NEXT: equal to the generator's over
// CHECK-NEXT: size 17 width 7 index 5 count 5
// CHECK-NEXT: equal to the generator's over
