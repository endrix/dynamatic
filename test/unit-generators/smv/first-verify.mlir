// REQUIRES: nusmv
// RUN: for n in 2 3; do python3 %dynamatic_src_root/experimental/tools/unit-generators/smv/verify-first.py --size $n --bitwidth 2 || exit 1; done | FileCheck %s

// The first's SMV model, model-checked against a specification written apart
// from it (an observer of the ports' transfers): the answer is the first
// payload to arrive carrying an action, "nothing selected" only once every
// input came without one, out the cycle it is known, once a round, each input
// taken the cycle it arrives, held until taken, always reachable; and the round
// closes in its last cycle: an input that gave its token is taken again then,
// that token the next round's, and a winner among those is answered then.
// And no ring through it: no input's ready reads that input's valid, and the
// output's valid does not read the output's ready (through the DEFINEs).
// Lesioned (the next round's tokens not taken in the closing cycle, taken and
// forgotten, taken and not answered, taken with this round's answer still
// pending; the completing round read through `done`, its own valid or the
// output's ready; an answer given twice, a late loser left on its channel),
// each fails some of them.

// CHECK: size 2, bitwidth 2: 12 of 12 properties hold
// CHECK: size 3, bitwidth 2: 14 of 14 properties hold
