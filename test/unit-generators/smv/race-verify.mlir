// REQUIRES: nusmv
// RUN: for s in guard chain f mixed dead alt; do python3 %dynamatic_src_root/experimental/tools/unit-generators/smv/verify-race.py --shape $s || exit 1; done | FileCheck %s
// RUN: for s in guard chain f mixed dead alt; do python3 %dynamatic_src_root/experimental/tools/unit-generators/smv/verify-race.py --shape $s --reopen-after-taken || exit 1; done | FileCheck %s --check-prefix=REOPEN

// The race's SMV model, model-checked against a specification written apart
// from it (an observer of the ports' transfers that decides the round from its
// own record), on the nests a lowering makes: a guard alone over two flags and
// a negated one (one bit), a chain of priorities, an F of three incomparable
// guards, P(t, F(g1(a, not b), P(g2(c), g3(d, b)))) with a token, and
// P(F(g0(s, a, not a), g1(b)), g2(a)), g0 a guard that can never pass, and
// F(P(h(b, not c), S), P(k(c, d), S)) with S = P(t, g(a)) taken in under both
// of its dominators (ALTERNATIVES: t read by two candidates, g's payload two;
// S's answer wins once h or k is refused). The
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
// CHECK: shape dead (p1:f1,0:u0/p2:f2/p3:f0:a0,1): 14 of 14 properties hold
// CHECK: shape alt (p4:f1:u2/t0:a0/p1:f0:a0,1/p2:f2,3/t0:a3/p1:f0:a3,4): 18 of 18 properties hold

// The race whose inputs reopen only after its answer was taken
// (`reopen_after_taken`), on the same shapes: everything above, but an input
// that gave its token is taken again only in a closing cycle whose answer was
// out before it, and, through the DEFINEs, no input's ready reads the output's
// ready. Lesioned (the generator ignoring the attribute), `on_arrival` and the
// structural check fail. The shape with ALTERNATIVES is among them: reopening
// is per input, so candidates of one answer change nothing about it.

// REOPEN: shape guard, reopen after taken (p1:f0,1:u2): 17 of 17 properties hold
// REOPEN: shape chain, reopen after taken (p1:f0/p2:f1:a0/p4:f2:a0,1): 17 of 17 properties hold
// REOPEN: shape f, reopen after taken (p1:f0/p2:f1/p4:f2): 17 of 17 properties hold
// REOPEN: shape mixed, reopen after taken (t0/p1:f0:u1:a0/p2:f2:a0/p4:f3,1:a0,2): 23 of 23 properties hold
// REOPEN: shape dead, reopen after taken (p1:f1,0:u0/p2:f2/p3:f0:a0,1): 17 of 17 properties hold
// REOPEN: shape alt, reopen after taken (p4:f1:u2/t0:a0/p1:f0:a0,1/p2:f2,3/t0:a3/p1:f0:a3,4): 23 of 23 properties hold
