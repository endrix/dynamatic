// REQUIRES: ghdl
// RUN: rm -rf %t && mkdir -p %t
// RUN: cp %S/Inputs/race-alt-vectors.txt %t/race-vectors.txt
// RUN: python3 %dynamatic_src_root/tools/unit-generators/vhdl/vhdl-unit-generator.py -n dut -o %t/dut.vhd -t race -p size_tokens=1 size_flags=4 bitwidth=5 "candidates='p16:f1:u2/t0:a0/p1:f0:a0,1/p2:f2,3/t0:a3/p1:f0:a3,4'" "extra_signals={}"
// RUN: ghdl -a --std=08 --workdir=%t %dynamatic_src_root/data/vhdl/support/types.vhd %t/dut.vhd %S/Inputs/race-tb.vhd
// RUN: cd %t && ghdl --elab-run --std=08 --workdir=. tb --stop-time=20us 2>&1 | FileCheck %s

// handshake.race with ALTERNATIVES, simulated: the generator's VHDL for
// F(P(h(b, not c), S), P(k(c, d), S)), S = P(t, g(a)) a shared subtree taken
// in once for each place that reads it -- the token t read by two candidates
// (after h, and after k) and g's payload two candidates (after h and t, and
// after k and t) -- against 1000 random cycles whose expected outputs come
// from the requirement written apart from the unit (Inputs/race_spec.py,
// shape `alt`, which made Inputs/race-alt-vectors.txt; its header counts the
// cycles that exercise each rule): S's answer wins once h OR k is refused,
// so an alternative after k answers alone while h is still out (25 cycles);
// two alternatives of one answer win together and answer it once (84); the
// rest as race-ghdl.mlir -- decided before the round's last input (161),
// ties between incomparable winners to the lower index (148), zero once every
// candidate is refused (12 early), a stalled answer held though a lower index
// came in since (14), the next round answered in the cycle the round
// completes (83).

// CHECK: race: 1000 cycles as expected
// CHECK-NOT: failure
