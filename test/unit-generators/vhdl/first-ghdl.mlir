// REQUIRES: ghdl
// RUN: rm -rf %t && mkdir -p %t/gen %t/static
// RUN: cp %S/Inputs/first-vectors.txt %t/gen/ && cp %S/Inputs/first-vectors.txt %t/static/
// RUN: python3 %dynamatic_src_root/tools/unit-generators/vhdl/vhdl-unit-generator.py -n dut -o %t/gen/dut.vhd -t first -p size=3 bitwidth=2 "extra_signals={}"
// RUN: ghdl -a --std=08 --workdir=%t/gen %dynamatic_src_root/data/vhdl/support/types.vhd %t/gen/dut.vhd %S/Inputs/first-tb.vhd
// RUN: cd %t/gen && ghdl --elab-run --std=08 --workdir=. tb --stop-time=10us 2>&1 | FileCheck %s
// RUN: ghdl -a --std=08 --workdir=%t/static %dynamatic_src_root/data/vhdl/support/types.vhd %dynamatic_src_root/data/vhdl/handshake/first.vhd %S/Inputs/first-static-dut.vhd %S/Inputs/first-tb.vhd
// RUN: cd %t/static && ghdl --elab-run --std=08 --workdir=. tb --stop-time=10us 2>&1 | FileCheck %s

// handshake.first simulated, the generator's VHDL and the static file, against
// 400 random cycles whose expected outputs come from the requirement
// (Inputs/first-vectors.txt): the first carrying payload to arrive wins, an
// all-zero round answers zero, a stalled answer is held, an input that gave
// its token is ready again in the cycle the round completes and gives the next
// round's then, whose winner is answered then when the round's answer went out
// before.

// CHECK: first: 400 cycles as expected
// CHECK-NOT: failure
