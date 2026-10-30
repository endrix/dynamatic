// REQUIRES: nusmv
// RUN: for s in guard chain f mixed; do python3 %dynamatic_src_root/experimental/tools/unit-generators/smv/verify-race.py --shape $s || exit 1; done | FileCheck %s

// The race's SMV model, model-checked against a specification written apart
// from it (an observer of the ports' transfers that decides the round from its
// own record), on the nests a lowering makes: a guard alone over two flags and
// a negated one (one bit), a chain of priorities, an F of three incomparable
// guards, and P(t, F(g1(a, not b), P(g2(c), g3(d, b)))) with a token. The
// first offer of an answer is the lowest-index winner of the record, or zero
// once every candidate is refused; nothing before the record decides; the
// answer out the cycle it does; once a round; each input taken the cycle it
// arrives, and in the round's last cycle the next round's, answered then when
// they decide it; an answer held until taken; always reachable. And no ring
// through it: no input's ready reads that input's valid, and the output's
// valid does not read the output's ready (through the DEFINEs).

// CHECK: shape guard (p1:f0,1:u2): 14 of 14 properties hold
// CHECK: shape chain (p1:f0/p2:f1:a0/p4:f2:a0,1): 14 of 14 properties hold
// CHECK: shape f (p1:f0/p2:f1/p4:f2): 14 of 14 properties hold
// CHECK: shape mixed (t0/p1:f0:u1:a0/p2:f2:a0/p4:f3,1:a0,2): 18 of 18 properties hold
