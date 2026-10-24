// REQUIRES: ghdl
// RUN: rm -rf %t && mkdir -p %t/gen %t/static
// RUN: cp %S/../verilog/Inputs/stand-in2-vectors.txt %t/gen/ && cp %S/../verilog/Inputs/stand-in2-vectors.txt %t/static/
// RUN: python3 %dynamatic_src_root/tools/unit-generators/vhdl/vhdl-unit-generator.py -n dut -o %t/gen/dut.vhd -t stand_in -p size=2 bitwidth=2 "extra_signals={}"
// RUN: cd %t/gen && ghdl -a --std=08 dut.vhd %S/Inputs/stand-in2-tb.vhd && ghdl --elab-run --std=08 tb 2>&1 | FileCheck %s
// RUN: cd %t/static && ghdl -a --std=08 %dynamatic_src_root/data/vhdl/handshake/stand_in.vhd %S/Inputs/stand-in2-static-dut.vhd %S/Inputs/stand-in2-tb.vhd && ghdl --elab-run --std=08 tb 2>&1 | FileCheck %s
// RUN: mkdir -p %t/gen-both %t/static-both
// RUN: cp %S/../verilog/Inputs/stand-in2-both-vectors.txt %t/gen-both/stand-in2-vectors.txt && cp %S/../verilog/Inputs/stand-in2-both-vectors.txt %t/static-both/stand-in2-vectors.txt
// RUN: cd %t/gen-both && ghdl -a --std=08 ../gen/dut.vhd %S/Inputs/stand-in2-tb.vhd && not ghdl --elab-run --std=08 tb 2>&1 | FileCheck %s --check-prefix=PROMISE
// RUN: cd %t/static-both && ghdl -a --std=08 %dynamatic_src_root/data/vhdl/handshake/stand_in.vhd %S/Inputs/stand-in2-static-dut.vhd %S/Inputs/stand-in2-tb.vhd && not ghdl --elab-run --std=08 tb 2>&1 | FileCheck %s --check-prefix=PROMISE

// handshake.stand_in with two kills (the commits of one domain) simulated in
// VHDL, the generator's output and the static entity the vivado configuration
// emits, on the vectors the Verilog forms replay
// (../verilog/Inputs/stand-in2-vectors.txt): the ports of domain 0's stand-in
// in the kill-domain bench, then random rounds ended by either kill, never
// both in one cycle (the domain's promise). Either kill ends the round as one
// kill does.
//
// Then the promise broken (../verilog/Inputs/stand-in2-both-vectors.txt): both
// kills high in one cycle outside reset. The unit's simulation assertion stops
// the run at that cycle (85 ns), and not before, at the reset with both kills
// high.

// CHECK: stand_in, two kills: 339 cycles as expected
// CHECK-NOT: failure

// PROMISE: @85ns:(assertion failure): stand_in: two commits of its kill domain transferred in one cycle (the domain's rounds overlap)
// PROMISE-NOT: cycles as expected
