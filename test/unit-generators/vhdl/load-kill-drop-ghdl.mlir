// REQUIRES: ghdl
// RUN: rm -rf %t && mkdir -p %t/gen %t/static
// RUN: python3 %dynamatic_src_root/tools/unit-generators/vhdl/vhdl-unit-generator.py -n dut -o %t/gen/dut.vhd -t load -p addr_bitwidth=2 data_bitwidth=8 kill_drop=1 "extra_signals={}"
// RUN: ghdl -a --std=08 --workdir=%t/gen %dynamatic_src_root/data/vhdl/support/types.vhd %dynamatic_src_root/data/vhdl/support/mc_support.vhd %t/gen/dut.vhd %S/Inputs/load-kill-drop-tb.vhd
// RUN: cd %t/gen && ghdl --elab-run --std=08 --workdir=. tb --stop-time=2us 2>&1 | FileCheck %s
// RUN: ghdl -a --std=08 --workdir=%t/static %dynamatic_src_root/data/vhdl/support/types.vhd %dynamatic_src_root/data/vhdl/support/mc_support.vhd %dynamatic_src_root/data/vhdl/handshake/dataless/tehb.vhd %dynamatic_src_root/data/vhdl/handshake/tehb.vhd %dynamatic_src_root/data/vhdl/handshake/load_kill_drop.vhd %S/Inputs/load-kill-drop-static-dut.vhd %S/Inputs/load-kill-drop-tb.vhd
// RUN: cd %t/static && ghdl --elab-run --std=08 --workdir=. tb --stop-time=2us 2>&1 | FileCheck %s

// The load that drops on a kill, simulated on the memory controller's own read
// path (mc_support.vhd's read_memory_arbiter), the generator's VHDL and the
// static file, against the same rounds (Inputs/load-kill-drop-tb.vhd): three
// words owed at the kill -- in the load's word slot, held by the controller,
// an address not yet granted -- are dropped with nothing offered meanwhile and
// no request withdrawn, and the next address gets its own word; a word passed
// on in the kill cycle is not dropped again; an address accepted in the kill
// cycle is.

// CHECK: load kill drop: 18 cycles as expected
// CHECK-NOT: failure
