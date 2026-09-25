// REQUIRES: ghdl
// RUN: rm -rf %t && mkdir %t
// RUN: cd %t && for c in 2:4:1111111111111101,0000000000000111 3:3:1111111111111101,0000000000000111,0000000000101010 0:4:none; do \
// RUN:   n=${c%%%%:*}; r=${c#*:}; s=${r%%%%:*}; t=${r#*:}; mkdir q$n && \
// RUN:   python3 %dynamatic_src_root/tools/unit-generators/vhdl/vhdl-unit-generator.py -n dut -o q$n/dut.vhd -t queue -p num_slots=$s bitwidth=16 size_width=3 space_width=3 initial_tokens="'$t'" && \
// RUN:   ghdl -a --std=08 --workdir=q$n q$n/dut.vhd %S/Inputs/queue-initial-tb.vhd && \
// RUN:   (cd q$n && ghdl --elab-run --std=08 --workdir=. tb -gNINIT=$n -gSLOTS=$s --stop-time=10us) || exit 1; done 2>&1 | FileCheck %s

// A queue holding tokens at reset, simulated: -3 and 7 in four slots, -3, 7
// and 42 filling three (the tail wraps to slot 0), and none. Out of reset it
// offers the first token with `size` and `space` counting the ones held; then
// what comes out is those tokens and the ten pushed after, in order, under a
// ready stalled one cycle in three.

// CHECK: 12 tokens in order
// CHECK: 13 tokens in order
// CHECK: 10 tokens in order
// CHECK-NOT: failure
