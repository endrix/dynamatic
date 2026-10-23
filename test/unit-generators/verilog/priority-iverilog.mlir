// REQUIRES: iverilog
// RUN: rm -rf %t && mkdir -p %t/gen %t/static
// RUN: cp %S/Inputs/priority-vectors.txt %t/gen/ && cp %S/Inputs/priority-vectors.txt %t/static/
// RUN: python3 %dynamatic_src_root/experimental/tools/unit-generators/verilog/verilog-unit-generator.py -n dut -o %t/gen/dut.v -t priority -p bitwidth=4 "extra_signals={}"
// RUN: iverilog -g2012 -o %t/gen/sim %t/gen/dut.v %S/Inputs/priority-tb.v
// RUN: cd %t/gen && vvp -N sim 2>&1 | FileCheck %s
// RUN: iverilog -g2012 -o %t/static/sim %dynamatic_src_root/data/verilog/handshake/priority_merge.v %S/Inputs/priority-static-dut.v %S/Inputs/priority-tb.v
// RUN: cd %t/static && vvp -N sim 2>&1 | FileCheck %s

// handshake.priority simulated in Verilog, the verilog-beta generator's output
// and the static module the Verilog configuration emits, against the rounds of
// the VHDL testbench (Inputs/priority-vectors.txt, extracted from
// ../vhdl/Inputs/priority-tb.vhd): hi decides alone the cycle it arrives, a
// late lo is absorbed, lo is held until a zero hi answers it, a non-zero hi
// beats a lo that came first, a stalled answer is kept, one round a cycle back
// to back, a zero hi and lo in one cycle under a stall, the next round's hi
// refused while the round is open.

// CHECK: priority: 39 cycles as expected
// CHECK-NOT: failure
// CHECK-NOT: MISMATCH
