// REQUIRES: nusmv
// RUN: for a in "" --at-valid; do for w in 0 2; do python3 %dynamatic_src_root/experimental/tools/unit-generators/smv/verify-commit.py --bitwidth $w $a || exit 1; done; done | FileCheck %s

// The commit's SMV model, both forms, dataless and with data, model-checked
// against a specification written apart from it (an observer of the ports
// under a producer that keeps the protocol and a consumer free to stall): a
// wire on the channel, and the kill in each cycle a token transfers -- or,
// with `kill_at_valid`, in the first cycle each token is offered and never in
// another, one kill a token by its transfer, none without a token. Lesioned
// (the one-shot dropped, its flip-flop never cleared or cleared every cycle,
// the transfer's AND in the at-valid form), each fails `kill_first`.

// CHECK: commit (transfer), bitwidth 0: 3 of 3 properties hold
// CHECK: commit (transfer), bitwidth 2: 4 of 4 properties hold
// CHECK: commit (kill_at_valid), bitwidth 0: 5 of 5 properties hold
// CHECK: commit (kill_at_valid), bitwidth 2: 6 of 6 properties hold
