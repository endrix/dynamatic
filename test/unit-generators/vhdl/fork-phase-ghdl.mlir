// REQUIRES: ghdl
// RUN: rm -rf %t && mkdir %t
// RUN: cd %t && d=%dynamatic_src_root/data/vhdl && g="python3 %dynamatic_src_root/tools/unit-generators/vhdl/vhdl-unit-generator.py" && for s in 1 2 3 4 5 8 33; do mkdir f$s && \
// RUN:   $g -n fork_gen -o f$s/gen.vhd -t fork -p size=$s bitwidth=0 'extra_signals={}' && \
// RUN:   ghdl -a --std=08 --workdir=f$s $d/support/logic.vhd $d/support/eager_fork_register_block.vhd $d/handshake/dataless/fork.vhd f$s/gen.vhd %S/Inputs/fork-per-output.vhd %S/Inputs/fork-phase-tb.vhd && \
// RUN:   (cd f$s && ghdl --elab-run --std=08 --workdir=. tb -gSIZE=$s) || exit 1; done 2>&1 | FileCheck %s
// RUN: cd %t && d=%dynamatic_src_root/data/vhdl && g="python3 %dynamatic_src_root/tools/unit-generators/vhdl/vhdl-unit-generator.py" && mkdir data && \
// RUN:   $g -n fork_data -o data/fork_data.vhd -t fork -p size=5 bitwidth=8 'extra_signals={}' && \
// RUN:   $g -n fork_spec -o data/fork_spec.vhd -t fork -p size=5 bitwidth=8 "extra_signals={'spec': 1}" && \
// RUN:   ghdl -a --std=08 --workdir=data $d/support/types.vhd data/fork_data.vhd data/fork_spec.vhd && \
// RUN:   ghdl -e --std=08 --workdir=data fork_data && ghdl -e --std=08 --workdir=data fork_spec

// The eager fork of the VHDL library and the fork the unit generator writes,
// each in lockstep with the fork that keeps one register per output (the
// form of the Verilog module and of the SMV model). From three outputs on,
// the library's fork and the generator's keep that state against a phase,
// so that a token's completion drives one flip-flop and not one per output;
// at one and two outputs all three are one form. They get the same random
// inputs, protocol or not, and must agree on ins_ready and outs_valid in
// every cycle. From two outputs on, the testbench also fails when its
// stimulus never tears a token, never completes one after that, never
// withdraws a valid from one or never resets on one.
//
// The generator is what the timing characterization measures and what a
// fork with extra signals is built from, so it must stay the library's
// logic: its fork with data, and with an extra signal, are elaborated around
// the new form at five outputs.

// CHECK: SIZE=1: 20000 cycles agree
// CHECK: SIZE=2: 20000 cycles agree
// CHECK: SIZE=3: 20000 cycles agree
// CHECK: SIZE=4: 20000 cycles agree
// CHECK: SIZE=5: 20000 cycles agree
// CHECK: SIZE=8: 20000 cycles agree
// CHECK: SIZE=33: 20000 cycles agree
// CHECK-NOT: failure
