// REQUIRES: ghdl
// RUN: rm -rf %t && mkdir -p %t
// RUN: cp %S/Inputs/race-vectors.txt %t/
// RUN: python3 %dynamatic_src_root/tools/unit-generators/vhdl/vhdl-unit-generator.py -n dut -o %t/dut.vhd -t race -p size_tokens=1 size_flags=4 bitwidth=4 "candidates='t0/p1:f0:u1:a0/p2:f2:a0/p4:f3,1:a0,2'" "extra_signals={}"
// RUN: ghdl -a --std=08 --workdir=%t %dynamatic_src_root/data/vhdl/support/types.vhd %t/dut.vhd %S/Inputs/race-tb.vhd
// RUN: cd %t && ghdl --elab-run --std=08 --workdir=. tb --stop-time=20us 2>&1 | FileCheck %s

// handshake.race simulated, the generator's VHDL for the nest
// P(t, F(g1(a, not b), P(g2(c), g3(d, b)))) -- one 4-bit token, four flags,
// flag b read by two candidates, once negated -- against 1000 random cycles
// whose expected outputs come from the requirement written apart from the
// unit (Inputs/race_spec.py, which made Inputs/race-vectors.txt; its header
// counts the cycles that exercise each rule): a candidate wins once its flags
// arrived as it needs them and its token carries, the cycle every candidate
// before it is refused, whatever has not arrived (decided before the round's
// last input: 133 cycles); a candidate after another waits for that one's
// refusal; two incomparable winners in one cycle go to the lower index (11);
// every candidate refused answers zero at once (11); a stalled answer is held
// (122); an input that gave its token is ready again in the cycle the round
// completes and gives the next round's then, which is answered then when it
// decides and the output is free (80).

// CHECK: race: 1000 cycles as expected
// CHECK-NOT: failure
