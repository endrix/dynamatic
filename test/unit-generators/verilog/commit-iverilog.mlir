// REQUIRES: iverilog
// RUN: rm -rf %t && mkdir -p %t/gen %t/static %t/gen0 %t/static0
// RUN: for d in gen static gen0 static0; do cp %S/Inputs/commit-vectors.txt %t/$d/; done
// RUN: python3 %dynamatic_src_root/experimental/tools/unit-generators/verilog/verilog-unit-generator.py -n dut -o %t/gen/dut.v -t commit -p bitwidth=3 "extra_signals={}"
// RUN: iverilog -g2012 -o %t/gen/sim %t/gen/dut.v %S/Inputs/commit-tb.v
// RUN: cd %t/gen && vvp -N sim 2>&1 | FileCheck %s
// RUN: iverilog -g2012 -o %t/static/sim %dynamatic_src_root/data/verilog/handshake/commit.v %S/Inputs/commit-static-dut.v %S/Inputs/commit-tb.v
// RUN: cd %t/static && vvp -N sim 2>&1 | FileCheck %s
// RUN: python3 %dynamatic_src_root/experimental/tools/unit-generators/verilog/verilog-unit-generator.py -n dut -o %t/gen0/dut.v -t commit -p bitwidth=0 "extra_signals={}"
// RUN: iverilog -g2012 -DDATALESS -o %t/gen0/sim %t/gen0/dut.v %S/Inputs/commit-tb.v
// RUN: cd %t/gen0 && vvp -N sim 2>&1 | FileCheck %s
// RUN: iverilog -g2012 -DDATALESS -o %t/static0/sim %dynamatic_src_root/data/verilog/handshake/dataless/commit.v %S/Inputs/commit-dataless-static-dut.v %S/Inputs/commit-tb.v
// RUN: cd %t/static0 && vvp -N sim 2>&1 | FileCheck %s

// handshake.commit simulated in Verilog, the verilog-beta generator's output
// and the static modules the Verilog configuration emits (with data and
// dataless), against the VHDL's outputs on the same inputs
// (Inputs/commit-vectors.txt): valid, data and ready pass straight through,
// and `kill` is the transfer (valid in, ready out) or the reset.

// CHECK: commit: 96 cycles as expected
// CHECK-NOT: failure
// CHECK-NOT: MISMATCH
