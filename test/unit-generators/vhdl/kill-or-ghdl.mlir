// REQUIRES: ghdl
// RUN: rm -rf %t && mkdir -p %t/gen %t/static
// RUN: python3 %dynamatic_src_root/tools/unit-generators/vhdl/vhdl-unit-generator.py -n dut -o %t/gen/dut.vhd -t kill_or -p size=3
// RUN: cd %t/gen && ghdl -a --std=08 dut.vhd %S/Inputs/kill-or-tb.vhd && ghdl --elab-run --std=08 tb 2>&1 | FileCheck %s
// RUN: cd %t/static && ghdl -a --std=08 %dynamatic_src_root/data/vhdl/support/kill_or.vhd %S/Inputs/kill-or-static-dut.vhd %S/Inputs/kill-or-tb.vhd && ghdl --elab-run --std=08 tb 2>&1 | FileCheck %s

// kill_or, the OR of a kill domain's commits' kills that HandshakeToHW puts
// beside a domain with several commits: the VHDL generator's and the static
// entity, every combination of three kills.

// CHECK: kill_or: 8 combinations as expected
// CHECK-NOT: failure
