// REQUIRES: ghdl
// RUN: rm -rf %t && mkdir -p %t/gen %t/static
// RUN: python3 %dynamatic_src_root/tools/unit-generators/vhdl/vhdl-unit-generator.py -n dut -o %t/gen/dut.vhd -t priority -p bitwidth=4 "extra_signals={}"
// RUN: ghdl -a --std=08 --workdir=%t/gen %t/gen/dut.vhd %S/Inputs/priority-tb.vhd
// RUN: cd %t/gen && ghdl --elab-run --std=08 --workdir=. tb --stop-time=2us 2>&1 | FileCheck %s
// RUN: ghdl -a --std=08 --workdir=%t/static %dynamatic_src_root/data/vhdl/handshake/priority.vhd %S/Inputs/priority-static-dut.vhd %S/Inputs/priority-tb.vhd
// RUN: cd %t/static && ghdl --elab-run --std=08 --workdir=. tb --stop-time=2us 2>&1 | FileCheck %s

// handshake.priority simulated, the generator's VHDL and the static file the
// characterization measures, against the same rounds (Inputs/priority-tb.vhd):
// hi decides alone the cycle it arrives, a late lo is absorbed, lo is held
// until a zero hi answers it, a non-zero hi beats a lo that came first, a
// stalled answer is kept, one round a cycle back to back, a zero hi and lo in
// one cycle under a stall, the next round's hi refused while the round is open
// and taken in the cycle it closes, the next round's hi taken and answered in
// the cycle a late lo closes the round. The same rounds drive the Verilog in ../verilog/priority-iverilog.mlir.

// CHECK: priority: 44 cycles as expected
// CHECK-NOT: failure
