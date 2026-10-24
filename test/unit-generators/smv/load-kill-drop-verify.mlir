// REQUIRES: nusmv
// RUN: python3 %dynamatic_src_root/experimental/tools/unit-generators/smv/verify-load-kill-drop.py --addr-bitwidth 2 | FileCheck %s

// The SMV model of the load that drops on a kill, model-checked on the memory
// controller's own read path against a specification written apart from it
// (the addresses accepted, oldest first, each marked stale once a kill stopped
// the evaluation that asked for it): no stale word is offered, only stale ones
// are dropped, at most three are owed, and no request is withdrawn before the
// controller grants it. Lesioned (no drop, a drop blind to the word slot, one
// blind to the kill cycle's address, a word offered while dropping, the load
// reset with the units it serves), each fails some of them.

// CHECK: address bitwidth 2: 4 of 4 properties hold
