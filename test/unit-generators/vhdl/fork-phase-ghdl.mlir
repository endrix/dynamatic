// REQUIRES: ghdl
// RUN: rm -rf %t && mkdir %t
// RUN: cd %t && for s in 1 2 3 4 5 8 33; do mkdir f$s && \
// RUN:   python3 %dynamatic_src_root/tools/unit-generators/vhdl/vhdl-unit-generator.py -n fork_ref -o f$s/ref.vhd -t fork -p size=$s bitwidth=0 && \
// RUN:   ghdl -a --std=08 --workdir=f$s %dynamatic_src_root/data/vhdl/support/logic.vhd %dynamatic_src_root/data/vhdl/support/eager_fork_register_block.vhd %dynamatic_src_root/data/vhdl/handshake/dataless/fork.vhd f$s/ref.vhd %S/Inputs/fork-phase-tb.vhd && \
// RUN:   (cd f$s && ghdl --elab-run --std=08 --workdir=. tb -gSIZE=$s) || exit 1; done 2>&1 | FileCheck %s

// The eager fork of the VHDL library against the fork the unit generator
// writes, in lockstep. The generator's fork keeps one register per output;
// from three outputs on, the library's keeps the same state against a phase,
// so that the cycle a token completes writes one flip-flop and not one per
// output. At one and two outputs the two are the same form. The two forks
// get the same random inputs, protocol or not, and must agree on ins_ready
// and outs_valid in every cycle; the testbench also fails when its stimulus
// never tears a token, never completes one after that, never withdraws a
// valid from one or never resets on one.

// CHECK: SIZE=1: 20000 cycles agree
// CHECK: SIZE=2: 20000 cycles agree
// CHECK: SIZE=3: 20000 cycles agree
// CHECK: SIZE=4: 20000 cycles agree
// CHECK: SIZE=5: 20000 cycles agree
// CHECK: SIZE=8: 20000 cycles agree
// CHECK: SIZE=33: 20000 cycles agree
// CHECK-NOT: failure
