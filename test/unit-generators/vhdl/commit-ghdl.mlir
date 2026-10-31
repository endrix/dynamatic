// REQUIRES: ghdl
// RUN: rm -rf %t && mkdir -p %t/transfer %t/static %t/at-valid %t/at-valid-on-transfer
// RUN: cp %S/../verilog/Inputs/commit-transfer-vectors.txt %t/transfer/commit-vectors.txt
// RUN: cp %S/../verilog/Inputs/commit-transfer-vectors.txt %t/static/commit-vectors.txt
// RUN: cp %S/../verilog/Inputs/commit-at-valid-vectors.txt %t/at-valid/commit-vectors.txt
// RUN: cp %S/../verilog/Inputs/commit-transfer-vectors.txt %t/at-valid-on-transfer/commit-vectors.txt
// RUN: python3 %dynamatic_src_root/tools/unit-generators/vhdl/vhdl-unit-generator.py -n dut -o %t/transfer/dut.vhd -t commit -p bitwidth=3 "extra_signals={}"
// RUN: cd %t/transfer && ghdl -a --std=08 dut.vhd %S/Inputs/commit-tb.vhd && ghdl --elab-run --std=08 tb 2>&1 | FileCheck %s
// RUN: cd %t/static && ghdl -a --std=08 %dynamatic_src_root/data/vhdl/handshake/commit.vhd %S/Inputs/commit-static-dut.vhd %S/Inputs/commit-tb.vhd && ghdl --elab-run --std=08 tb 2>&1 | FileCheck %s
// RUN: python3 %dynamatic_src_root/tools/unit-generators/vhdl/vhdl-unit-generator.py -n dut -o %t/at-valid/dut.vhd -t commit -p bitwidth=3 "extra_signals={}" kill_at_valid=1
// RUN: cd %t/at-valid && ghdl -a --std=08 dut.vhd %S/Inputs/commit-tb.vhd && ghdl --elab-run --std=08 tb 2>&1 | FileCheck %s
// RUN: cd %t/at-valid-on-transfer && ghdl -a --std=08 ../at-valid/dut.vhd %S/Inputs/commit-tb.vhd && not ghdl --elab-run --std=08 tb 2>&1 | FileCheck %s --check-prefix=OTHER

// handshake.commit simulated in VHDL, both forms, against the requirement of
// each (../verilog/Inputs/commit_spec.py, which wrote the vectors; 200 cycles
// of protocol-keeping tokens with bubbles, stalls, tokens taken at once,
// tokens back to back and resets): the transfer's commit (the generator's
// output and the static entity the vivado configuration emits) kills in each
// cycle a token transfers; the `kill_at_valid` one in the FIRST cycle each
// token is offered and never again for it, its transfer included, and again
// for the next token, the cycle after a transfer too. The channel is a wire
// in both. Then the kill_at_valid unit on the transfer's vectors: the forms
// are told apart (the first cycle where a token waits or is taken late).

// CHECK: commit: 200 cycles as expected
// CHECK-NOT: failure

// OTHER: (assertion failure): cycle {{[0-9]+}}: kill
// OTHER-NOT: cycles as expected
