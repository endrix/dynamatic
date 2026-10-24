// REQUIRES: iverilog
// RUN: rm -rf %t && mkdir -p %t/gen %t/static
// RUN: cp %S/Inputs/first-vectors.txt %t/gen/ && cp %S/Inputs/first-vectors.txt %t/static/
// RUN: python3 %dynamatic_src_root/experimental/tools/unit-generators/verilog/verilog-unit-generator.py -n dut -o %t/gen/dut.v -t first -p size=3 bitwidth=2 "extra_signals={}"
// RUN: iverilog -g2012 -o %t/gen/sim %t/gen/dut.v %S/Inputs/first-tb.v
// RUN: cd %t/gen && vvp -N sim 2>&1 | FileCheck %s
// RUN: iverilog -g2012 -o %t/static/sim %dynamatic_src_root/data/verilog/handshake/first.v %S/Inputs/first-static-dut.v %S/Inputs/first-tb.v
// RUN: cd %t/static && vvp -N sim 2>&1 | FileCheck %s

// handshake.first simulated in Verilog, the verilog-beta generator's output
// and the static module the Verilog configuration emits, against the random
// rounds of the VHDL testbench (Inputs/first-vectors.txt, expected outputs from
// the requirement): the first carrying payload wins, an all-zero round answers
// zero, an input that gave its token is ready again in the cycle the round
// completes, the next round's winner answered then when the output is free.

// CHECK: first: 400 cycles as expected
// CHECK-NOT: failure
// CHECK-NOT: MISMATCH
