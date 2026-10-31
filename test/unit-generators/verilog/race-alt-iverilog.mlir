// REQUIRES: iverilog
// RUN: rm -rf %t && mkdir -p %t
// RUN: cp %S/../vhdl/Inputs/race-alt-vectors.txt %t/race-vectors.txt
// RUN: python3 %dynamatic_src_root/experimental/tools/unit-generators/verilog/verilog-unit-generator.py -n dut -o %t/dut.v -t race -p size_tokens=1 size_flags=4 bitwidth=5 "candidates='p16:f1:u2/t0:a0/p1:f0:a0,1/p2:f2,3/t0:a3/p1:f0:a3,4'" "extra_signals={}"
// RUN: iverilog -g2012 -o %t/sim %t/dut.v %S/Inputs/race-tb.v
// RUN: cd %t && vvp -N sim 2>&1 | FileCheck %s
// RUN: mkdir -p %t/reopen && cp %S/../vhdl/Inputs/race-alt-reopen-vectors.txt %t/reopen/race-vectors.txt
// RUN: python3 %dynamatic_src_root/experimental/tools/unit-generators/verilog/verilog-unit-generator.py -n dut -o %t/reopen/dut.v -t race -p size_tokens=1 size_flags=4 bitwidth=5 "candidates='p16:f1:u2/t0:a0/p1:f0:a0,1/p2:f2,3/t0:a3/p1:f0:a3,4'" "extra_signals={}" reopen_after_taken=1
// RUN: iverilog -g2012 -o %t/reopen/sim %t/reopen/dut.v %S/Inputs/race-tb.v
// RUN: cd %t/reopen && vvp -N sim 2>&1 | FileCheck %s

// handshake.race with ALTERNATIVES simulated in Verilog, the verilog-beta
// generator's output, against the random rounds of the VHDL testbench's
// shape `alt` (../vhdl/Inputs/race-alt-vectors.txt, the one copy, from
// race_spec.py there):
// F(P(h(b, not c), S), P(k(c, d), S)), S = P(t, g(a)) taken in under both of
// its dominators -- t read by two candidates, g's payload two -- so S's
// answer wins once h or k is refused, an alternative after k alone while h
// is out, two alternatives winning together answering their payload once.
//
// And the same shape with `reopen_after_taken`, against the vectors for that
// form (../vhdl/Inputs/race-alt-reopen-vectors.txt): the two features are
// independent -- reopening is per input, an alternative is a candidate's
// term -- and the Verilog agrees with the requirement on both at once, as
// the VHDL does (race-alt-ghdl.mlir).

// CHECK: race: 1000 cycles as expected
// CHECK-NOT: failure
// CHECK-NOT: MISMATCH
