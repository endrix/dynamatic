// REQUIRES: iverilog
// RUN: rm -rf %t && mkdir -p %t
// RUN: cp %S/Inputs/race-vectors.txt %t/
// RUN: python3 %dynamatic_src_root/experimental/tools/unit-generators/verilog/verilog-unit-generator.py -n dut -o %t/dut.v -t race -p size_tokens=1 size_flags=4 bitwidth=5 "candidates='t0/p1:f0:u1:a0/p2:f2:a0/p16:f0:u0:a0,2/p4:f3,1:a0,2,3'" "extra_signals={}"
// RUN: iverilog -g2012 -o %t/sim %t/dut.v %S/Inputs/race-tb.v
// RUN: cd %t && vvp -N sim 2>&1 | FileCheck %s

// handshake.race simulated in Verilog, the verilog-beta generator's output,
// against the random rounds of the VHDL testbench (Inputs/race-vectors.txt,
// expected outputs from the requirement, ../vhdl/Inputs/race_spec.py): the
// nest P(t, F(g1(a, not b), P(g2(c), P(g0(a, not a), g3(d, b))))) -- a
// winner the cycle it is enabled and its predecessors refused, ties to the
// lower index, zero once every candidate is refused, a guard over a and not
// a never winning and refused once a arrives, a stalled answer held, the
// next round's tokens taken and answered in the cycle the round completes.

// CHECK: race: 1000 cycles as expected
// CHECK-NOT: failure
// CHECK-NOT: MISMATCH
