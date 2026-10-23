// REQUIRES: nusmv
// RUN: for w in 1 2 3; do python3 %dynamatic_src_root/experimental/tools/unit-generators/smv/verify-priority.py --bitwidth $w || exit 1; done | FileCheck %s

// The priority's SMV model, model-checked against a specification written
// apart from it (an observer of the ports' transfers): the answer is hi when
// hi carries something and lo otherwise, never before hi, the cycle hi or (hi
// being zero) lo decides it, once a round, each input taken the cycle it
// arrives, held until taken, and always reachable. Lesioned (an answer given
// twice, a late lo left on its channel, a lo answered before hi, a wait for lo
// when hi decides, a stalled answer overwritten), each fails some of them.

// CHECK: bitwidth 1: 9 of 9 properties hold
// CHECK: bitwidth 2: 9 of 9 properties hold
// CHECK: bitwidth 3: 9 of 9 properties hold
