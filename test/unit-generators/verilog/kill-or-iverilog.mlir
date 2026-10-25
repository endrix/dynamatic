// REQUIRES: iverilog
// RUN: rm -rf %t && mkdir -p %t
// RUN: python3 %dynamatic_src_root/experimental/tools/unit-generators/verilog/verilog-unit-generator.py -n dut -o %t/dut.v -t kill_or -p size=3
// RUN: iverilog -g2012 -o %t/gen %t/dut.v %S/Inputs/kill-or-tb.v
// RUN: vvp -N %t/gen 2>&1 | FileCheck %s
// RUN: iverilog -g2012 -o %t/static %dynamatic_src_root/data/verilog/support/kill_or.v %S/Inputs/kill-or-static-dut.v %S/Inputs/kill-or-tb.v
// RUN: vvp -N %t/static 2>&1 | FileCheck %s

// kill_or, the OR of a kill domain's commits' kills that HandshakeToHW puts
// beside a domain with several commits: the verilog-beta generator's and the
// static module, every combination of three kills.

// CHECK: kill_or: 8 combinations as expected
// CHECK-NOT: failure
// CHECK-NOT: MISMATCH
