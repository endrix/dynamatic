// REQUIRES: nusmv
// RUN: rm -rf %t && mkdir -p %t
// RUN: python3 %dynamatic_src_root/experimental/tools/unit-generators/smv/smv-unit-generator.py -n slot -o %t/slot.smv -t buffer -p num_slots=1 dv_latency=0 bitwidth=2 buffer_type='"ONE_SLOT_BREAK_R"' kill_reset=1
// RUN: python3 %dynamatic_src_root/experimental/tools/unit-generators/smv/smv-unit-generator.py -n copy -o %t/copy.smv -t fork -p size=2 bitwidth=0 kill_reset=1
// RUN: cat %t/slot.smv %t/copy.smv %S/Inputs/kill-reset-main.smv > %t/all.smv
// RUN: NuSMV %t/all.smv | FileCheck %s

// A unit a commit stops (KILL_RESET) gets `rst` as its last parameter, and
// every state variable of it -- in its own module and in the modules it
// instantiates (the slot's dataless inner one, the fork's register blocks) --
// is back at its initial value the step after `rst`. A slot holding a token
// and a fork that has delivered one copy, reset: empty, re-armed.

// CHECK: -- invariant {{.*}} is true
// CHECK: -- invariant {{.*}} is true
// CHECK-NOT: is false
