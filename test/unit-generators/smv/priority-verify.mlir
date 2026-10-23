// REQUIRES: nusmv
// RUN: for w in 1 2 3; do python3 %dynamatic_src_root/experimental/tools/unit-generators/smv/verify-priority.py --bitwidth $w || exit 1; done | FileCheck %s

// The priority's SMV model, model-checked against a specification written
// apart from it (an observer of the ports' transfers): the answer is hi when
// hi carries something and lo otherwise, never before hi, never before lo when
// hi does not decide, the cycle hi or (hi being zero) lo decides it, once a round, each input taken the cycle it
// arrives, held until taken, and always reachable; and the round closes in its
// last cycle: the input that gave its token is taken again then, that token
// the next round's, and a non-zero next hi is answered then. Lesioned (an
// answer given twice, a late lo left on its channel, a lo answered before hi, a
// wait for lo when hi decides, a stalled answer overwritten; the next round's
// token not taken in the closing cycle, taken and forgotten, taken and not
// answered, taken with this round's answer still pending; the completing
// round read through `done`, its own valid or the output's ready), each fails
// some of them. And no ring through it: neither input's ready reads that
// input's valid, and the output's valid does not read the output's ready.

// CHECK: bitwidth 1: 14 of 14 properties hold
// CHECK: bitwidth 2: 14 of 14 properties hold
// CHECK: bitwidth 3: 14 of 14 properties hold
