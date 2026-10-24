// REQUIRES: nusmv
// RUN: for w in 1 2; do for n in 1 2 3; do python3 %dynamatic_src_root/experimental/tools/unit-generators/smv/verify-stand-in.py --bitwidth $w --kills $n || exit 1; done; done | FileCheck %s

// The stand-in's SMV model, model-checked against a specification written
// apart from it (tokens out counted against the rounds the kills end, from the
// ports): one token a round, the producer's or a zero, never both and never
// none; the zero offered from the cycle after the kill until taken; the
// producer's token passed untouched otherwise; the output held until taken.
// With several kills (the commits of one domain) each commit's transfer ends a
// round of its own, under the domain's promise that two never come in one
// cycle. Lesioned (a zero owed even when the round's token went out, never
// owed, not held until taken, a round that a kill does not end, a kill left
// out of the OR), each fails `one`; so does the promise dropped
// (--no-exclusive).

// CHECK: bitwidth 1, 1 kill(s): 6 of 6 properties hold
// CHECK: bitwidth 1, 2 kill(s): 6 of 6 properties hold
// CHECK: bitwidth 1, 3 kill(s): 6 of 6 properties hold
// CHECK: bitwidth 2, 1 kill(s): 6 of 6 properties hold
// CHECK: bitwidth 2, 2 kill(s): 6 of 6 properties hold
// CHECK: bitwidth 2, 3 kill(s): 6 of 6 properties hold
