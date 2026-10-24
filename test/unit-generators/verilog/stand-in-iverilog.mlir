// REQUIRES: iverilog
// RUN: rm -rf %t && mkdir -p %t/gen %t/static
// RUN: cp %S/Inputs/stand-in-vectors.txt %t/gen/ && cp %S/Inputs/stand-in-vectors.txt %t/static/
// RUN: python3 %dynamatic_src_root/experimental/tools/unit-generators/verilog/verilog-unit-generator.py -n dut -o %t/gen/dut.v -t stand_in -p size=1 bitwidth=2 "extra_signals={}"
// RUN: iverilog -g2012 -o %t/gen/sim %t/gen/dut.v %S/Inputs/stand-in-tb.v
// RUN: cd %t/gen && vvp -N sim 2>&1 | FileCheck %s
// RUN: iverilog -g2012 -o %t/static/sim %dynamatic_src_root/data/verilog/handshake/stand_in.v %S/Inputs/stand-in-static-dut.v %S/Inputs/stand-in-tb.v
// RUN: cd %t/static && vvp -N sim 2>&1 | FileCheck %s
// RUN: mkdir -p %t/gen2 %t/static2
// RUN: cp %S/Inputs/stand-in2-vectors.txt %t/gen2/ && cp %S/Inputs/stand-in2-vectors.txt %t/static2/
// RUN: python3 %dynamatic_src_root/experimental/tools/unit-generators/verilog/verilog-unit-generator.py -n dut -o %t/gen2/dut.v -t stand_in -p size=2 bitwidth=2 "extra_signals={}"
// RUN: iverilog -g2012 -o %t/gen2/sim %t/gen2/dut.v %S/Inputs/stand-in2-tb.v
// RUN: cd %t/gen2 && vvp -N sim 2>&1 | FileCheck %s --check-prefix=TWO
// RUN: iverilog -g2012 -o %t/static2/sim %dynamatic_src_root/data/verilog/handshake/stand_in.v %S/Inputs/stand-in2-static-dut.v %S/Inputs/stand-in2-tb.v
// RUN: cd %t/static2 && vvp -N sim 2>&1 | FileCheck %s --check-prefix=TWO
// RUN: mkdir -p %t/gen2-both %t/static2-both
// RUN: cp %S/Inputs/stand-in2-both-vectors.txt %t/gen2-both/stand-in2-vectors.txt && cp %S/Inputs/stand-in2-both-vectors.txt %t/static2-both/stand-in2-vectors.txt
// RUN: cd %t/gen2-both && not vvp -N ../gen2/sim 2>&1 | FileCheck %s --check-prefix=PROMISE
// RUN: cd %t/static2-both && not vvp -N ../static2/sim 2>&1 | FileCheck %s --check-prefix=PROMISE

// handshake.stand_in simulated in Verilog, the verilog-beta generator's output
// and the static module the Verilog configuration emits, against the VHDL's
// outputs on the same inputs (Inputs/stand-in-vectors.txt): the stand-in's
// ports in the kill-domain bench (../vhdl/Inputs/kill-domain-tb.vhd), then
// random rounds within its precondition. A kill with the round's token not
// passed owes one zero, offered from the next cycle until taken, the input
// waiting meanwhile; a token passed in the kill's cycle, or earlier in the
// round, owes nothing; a kill in the cycle a zero is taken owes the next one.
// No vector breaks the precondition, which the unit asserts ($fatal).
//
// Then the stand-in with two kills (the commits of one domain), both forms,
// against the VHDL's outputs (Inputs/stand-in2-vectors.txt): the ports of
// domain 0's stand-in in the kill-domain bench, then random rounds ended by
// either kill, never both in one cycle (the domain's promise). Either kill
// ends the round as the one kill did.
//
// Then the promise broken (Inputs/stand-in2-both-vectors.txt): both kills
// high in one cycle outside reset. The unit's simulation assertion ($fatal)
// stops the run at that cycle (85 ns), and not before, at the reset with both
// kills high.

// CHECK: stand_in: 319 cycles as expected
// CHECK-NOT: failure
// CHECK-NOT: MISMATCH
// CHECK-NOT: FATAL

// TWO: stand_in, two kills: 339 cycles as expected
// TWO-NOT: failure
// TWO-NOT: MISMATCH
// TWO-NOT: FATAL

// PROMISE: FATAL: {{.*}}two commits of its kill domain transferred in one cycle (the domain's rounds overlap)
// PROMISE-NEXT: Time: 85000
// PROMISE-NOT: cycles as expected
