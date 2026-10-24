// REQUIRES: nusmv
// RUN: rm -rf %t && mkdir -p %t
// RUN: dynamatic-opt %S/kill-domain-shared.mlir --lower-handshake-to-hw > %t/shared.hw
// RUN: export-rtl %t/shared.hw %t/out %dynamatic_src_root/data/rtl-config-smv.json --dynamatic-path %dynamatic_src_root --hdl smv
// RUN: cd %t/out && grep -hv '^#include' handshake_*.smv kill_or_*.smv mem_to_bram_*.smv shared_guard.smv %S/Inputs/kill-domain-shared-main.smv > %t/all.smv
// RUN: NuSMV %t/all.smv | FileCheck %s

// The circuit of kill-domain-shared.mlir (a domain with two commits, each in
// series after another domain's) exported to SMV and model-checked under free
// inputs (Inputs/kill-domain-shared-main.smv): the units of the shared domain
// take the OR of its commits' kills as their reset (kill_or), so the domain is
// empty the step after EITHER commit's transfer; each private domain is empty
// the step after its own commit's and keeps a held token across the other's;
// the shared stand-in owes a zero the cycle after either commit ended a round
// in which nothing passed. Lesioned (one commit left out of the OR; the
// stand-in on one kill only) the property of the commit left out fails.

// CHECK-DAG: -- invariant (was_k2a -> domain2_empty)  is true
// CHECK-DAG: -- invariant (was_k2b -> domain2_empty)  is true
// CHECK-DAG: -- invariant (was_k0 -> !u.buffer0.full)  is true
// CHECK-DAG: -- invariant (was_k1 -> !u.buffer1.full)  is true
// CHECK-DAG: -- invariant (((was_k1 & !was_k0) & held0) -> u.buffer0.full)  is true
// CHECK-DAG: -- invariant (((was_k0 & !was_k1) & held1) -> u.buffer1.full)  is true
// CHECK-DAG: -- invariant (owed2 -> (u.stand_in2.outs_valid & u.stand_in2.outs = FALSE))  is true
// CHECK-NOT: is false
