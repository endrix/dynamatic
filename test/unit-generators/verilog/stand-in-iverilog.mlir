// REQUIRES: iverilog
// RUN: rm -rf %t && mkdir -p %t/gen %t/static
// RUN: cp %S/Inputs/stand-in-vectors.txt %t/gen/ && cp %S/Inputs/stand-in-vectors.txt %t/static/
// RUN: python3 %dynamatic_src_root/experimental/tools/unit-generators/verilog/verilog-unit-generator.py -n dut -o %t/gen/dut.v -t stand_in -p bitwidth=2 "extra_signals={}"
// RUN: iverilog -g2012 -o %t/gen/sim %t/gen/dut.v %S/Inputs/stand-in-tb.v
// RUN: cd %t/gen && vvp -N sim 2>&1 | FileCheck %s
// RUN: iverilog -g2012 -o %t/static/sim %dynamatic_src_root/data/verilog/handshake/stand_in.v %S/Inputs/stand-in-static-dut.v %S/Inputs/stand-in-tb.v
// RUN: cd %t/static && vvp -N sim 2>&1 | FileCheck %s

// handshake.stand_in simulated in Verilog, the verilog-beta generator's output
// and the static module the Verilog configuration emits, against the VHDL's
// outputs on the same inputs (Inputs/stand-in-vectors.txt): the stand-in's
// ports in the kill-domain bench (../vhdl/Inputs/kill-domain-tb.vhd), then
// random rounds within its precondition. A kill with the round's token not
// passed owes one zero, offered from the next cycle until taken, the input
// waiting meanwhile; a token passed in the kill's cycle, or earlier in the
// round, owes nothing; a kill in the cycle a zero is taken owes the next one.
// No vector breaks the precondition, which the unit asserts ($fatal).

// CHECK: stand_in: 319 cycles as expected
// CHECK-NOT: failure
// CHECK-NOT: MISMATCH
// CHECK-NOT: FATAL
