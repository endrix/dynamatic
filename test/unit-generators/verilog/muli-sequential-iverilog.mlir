// REQUIRES: iverilog
// RUN: rm -rf %t && mkdir -p %t
// RUN: for p in 1:1:0 8:3:0 8:8:0 33:4:0 70:16:0 64:1:32 64:8:32 33:4:5 16:16:3 8:3:8; do \
// RUN:   w=${p%%%%:*}; r=${p#*:}; s=${r%%%%:*}; i=${r#*:}; \
// RUN:   iverilog -g2012 -Ptb.W=$w -Ptb.S=$s -Ptb.IW=$i -o %t/sim-$w-$s-$i %dynamatic_src_root/data/verilog/arith/muli_sequential.v %dynamatic_src_root/data/verilog/handshake/join.v %S/Inputs/muli-sequential-tb.v || exit 1; \
// RUN:   vvp -N %t/sim-$w-$s-$i || exit 1; \
// RUN: done 2>&1 | FileCheck %s --implicit-check-not=MISMATCH

// The Verilog sequential multiplier simulated (Inputs/muli-sequential-tb.v):
// the low W bits of the product of random operands, held until taken, at
// several widths and steps, and with an ITER_WIDTH (the third number): a
// 32-bit multiplier in 64 bits at 1 and 8 bits a cycle, an iteration width
// that is no multiple of the step, a step wider than it, and one equal to
// the width. A multiply takes ceil(ITER_WIDTH / STEP) cycles, ceil(W / STEP)
// without it.

// CHECK: W=1 S=1 IW=0: 60 multiplies, 0 mismatches
// CHECK: W=8 S=3 IW=0: 60 multiplies, 0 mismatches
// CHECK: W=8 S=8 IW=0: 60 multiplies, 0 mismatches
// CHECK: W=33 S=4 IW=0: 60 multiplies, 0 mismatches
// CHECK: W=70 S=16 IW=0: 60 multiplies, 0 mismatches
// CHECK: W=64 S=1 IW=32: 60 multiplies, 0 mismatches
// CHECK: W=64 S=8 IW=32: 60 multiplies, 0 mismatches
// CHECK: W=33 S=4 IW=5: 60 multiplies, 0 mismatches
// CHECK: W=16 S=16 IW=3: 60 multiplies, 0 mismatches
// CHECK: W=8 S=3 IW=8: 60 multiplies, 0 mismatches
