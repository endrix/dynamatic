// REQUIRES: nusmv
// RUN: for w in 1 2; do python3 %dynamatic_src_root/experimental/tools/unit-generators/smv/verify-stand-in.py --bitwidth $w || exit 1; done | FileCheck %s

// The stand-in's SMV model, model-checked against a specification written
// apart from it (tokens out counted against the rounds the kills end, from the
// ports): one token a round, the producer's or a zero, never both and never
// none; the zero offered from the cycle after the kill until taken; the
// producer's token passed untouched otherwise; the output held until taken.
// Lesioned (a zero owed even when the round's token went out, never owed, not
// held until taken, a round that a kill does not end), each fails `one`.

// CHECK: bitwidth 1: 6 of 6 properties hold
// CHECK: bitwidth 2: 6 of 6 properties hold
