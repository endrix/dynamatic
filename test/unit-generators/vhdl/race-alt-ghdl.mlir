// REQUIRES: ghdl
// RUN: rm -rf %t && mkdir -p %t
// RUN: cp %S/Inputs/race-alt-vectors.txt %t/race-vectors.txt
// RUN: python3 %dynamatic_src_root/tools/unit-generators/vhdl/vhdl-unit-generator.py -n dut -o %t/dut.vhd -t race -p size_tokens=1 size_flags=4 bitwidth=5 "candidates='p16:f1:u2/t0:a0/p1:f0:a0,1/p2:f2,3/t0:a3/p1:f0:a3,4'" "extra_signals={}"
// RUN: ghdl -a --std=08 --workdir=%t %dynamatic_src_root/data/vhdl/support/types.vhd %t/dut.vhd %S/Inputs/race-tb.vhd
// RUN: cd %t && ghdl --elab-run --std=08 --workdir=. tb --stop-time=20us 2>&1 | FileCheck %s
// RUN: mkdir -p %t/reopen %t/reopen-other && cp %S/Inputs/race-alt-reopen-vectors.txt %t/reopen/race-vectors.txt && cp %S/Inputs/race-alt-vectors.txt %t/reopen-other/race-vectors.txt
// RUN: python3 %dynamatic_src_root/tools/unit-generators/vhdl/vhdl-unit-generator.py -n dut -o %t/reopen/dut.vhd -t race -p size_tokens=1 size_flags=4 bitwidth=5 "candidates='p16:f1:u2/t0:a0/p1:f0:a0,1/p2:f2,3/t0:a3/p1:f0:a3,4'" "extra_signals={}" reopen_after_taken=1
// RUN: ghdl -a --std=08 --workdir=%t/reopen %dynamatic_src_root/data/vhdl/support/types.vhd %t/reopen/dut.vhd %S/Inputs/race-tb.vhd
// RUN: cd %t/reopen && ghdl --elab-run --std=08 --workdir=. tb --stop-time=20us 2>&1 | FileCheck %s
// RUN: cd %t/reopen-other && not ghdl --elab-run --std=08 --workdir=../reopen tb --stop-time=20us 2>&1 | FileCheck %s --check-prefix=OTHER

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

// BOTH AT ONCE: the same shape with `reopen_after_taken` (an input that gave
// its token is ready again only once the answer was taken in an EARLIER
// cycle) against its own vectors (Inputs/race-alt-reopen-vectors.txt,
// `race_spec.py --reopen-after-taken 1000 7 alt`): the two features are
// independent, since reopening is per input (seen, others_in) and an
// alternative is a candidate's term. An input read by two candidates is one
// input with one `seen` bit and reopens once. 138 of the 1000 cycles are
// ones the two reopening forms tell apart (`taking`), and the plain race's
// vectors fail on this unit (OTHER), so the run is not vacuous.
// CHECK: race: 1000 cycles as expected
// CHECK-NOT: failure
// OTHER: (assertion failure): cycle {{[0-9]+}}: {{tokens|flags}}_ready
// OTHER-NOT: cycles as expected
