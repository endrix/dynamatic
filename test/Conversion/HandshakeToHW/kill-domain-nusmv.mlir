// REQUIRES: nusmv
// RUN: rm -rf %t && mkdir -p %t
// RUN: dynamatic-opt %S/kill-domain.mlir --lower-handshake-to-hw > %t/guard.hw
// RUN: export-rtl %t/guard.hw %t/out %dynamatic_src_root/data/rtl-config-smv.json --dynamatic-path %dynamatic_src_root --hdl smv
// RUN: cd %t/out && grep -hv '^#include' handshake_*.smv mem_to_bram_*.smv guard.smv %S/Inputs/kill-domain-main.smv > %t/all.smv
// RUN: NuSMV %t/all.smv | FileCheck %s

// The circuit of kill-domain.mlir exported to SMV and model-checked: every
// unit of the domain is modelled with the commit's kill as its reset (the
// KILL_RESET entries of the SMV configuration, the generic reset transform),
// the units it marks by hand that hold nothing (the sink, the narrowing) among
// them, and NuSMV takes the model. The step after the commit's transfer the
// latch, the permit's slot and the slot between the latch and the load are
// empty; the neighbour outside the domain keeps the token it held
// (Inputs/kill-domain-main.smv).

// CHECK-DAG: -- invariant (was_kill -> {{.*}} is true
// CHECK-DAG: -- invariant ((was_kill & held) -> u.buffer3.full)  is true
// CHECK-NOT: is false
