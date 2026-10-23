// REQUIRES: iverilog
// RUN: rm -rf %t && mkdir -p %t/gen %t/static
// RUN: cp %S/Inputs/load-kill-drop-vectors.txt %t/gen/ && cp %S/Inputs/load-kill-drop-vectors.txt %t/static/
// RUN: python3 %dynamatic_src_root/experimental/tools/unit-generators/verilog/verilog-unit-generator.py -n dut -o %t/gen/dut.v -t load -p addr_bitwidth=2 data_bitwidth=8 kill_drop=1 "extra_signals={}"
// RUN: iverilog -g2012 -o %t/gen/sim %t/gen/dut.v %S/Inputs/load-kill-drop-tb.v
// RUN: cd %t/gen && vvp -N sim 2>&1 | FileCheck %s
// RUN: iverilog -g2012 -o %t/static/sim %dynamatic_src_root/data/verilog/handshake/dataless/tehb.v %dynamatic_src_root/data/verilog/handshake/tehb.v %dynamatic_src_root/data/verilog/handshake/load_kill_drop.v %S/Inputs/load-kill-drop-static-dut.v %S/Inputs/load-kill-drop-tb.v
// RUN: cd %t/static && vvp -N sim 2>&1 | FileCheck %s

// The load that drops on a kill simulated in Verilog, the verilog-beta
// generator's output and the static module the Verilog configuration emits,
// against the VHDL's outputs on the same inputs
// (Inputs/load-kill-drop-vectors.txt): the load's ports in the GHDL bench
// (../vhdl/Inputs/load-kill-drop-tb.vhd, on the memory controller's read path:
// three words owed at a kill and dropped with nothing offered, a word passed on
// in the kill cycle not dropped again, an address accepted in it dropped), then
// random inputs with kills and resets anywhere.

// CHECK: load kill drop: 418 cycles as expected
// CHECK-NOT: failure
// CHECK-NOT: MISMATCH
