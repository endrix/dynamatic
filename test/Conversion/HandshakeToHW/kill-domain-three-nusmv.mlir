// REQUIRES: nusmv
// RUN: rm -rf %t && mkdir -p %t
// RUN: dynamatic-opt %S/kill-domain-three.mlir --lower-handshake-to-hw > %t/three.hw
// RUN: export-rtl %t/three.hw %t/out %dynamatic_src_root/data/rtl-config-smv.json --dynamatic-path %dynamatic_src_root --hdl smv
// RUN: cd %t/out && grep -hv '^#include' handshake_*.smv kill_or_*.smv three.smv %S/Inputs/kill-domain-three-main.smv > %t/all.smv
// RUN: NuSMV %t/all.smv | FileCheck %s

// The circuit of kill-domain-three.mlir (a domain with three commits beside
// one with two) exported to SMV and model-checked under free inputs
// (Inputs/kill-domain-three-main.smv): each domain's latch is empty the step
// after any of its commits (kill_or_3, kill_or_2), domain 4's latch keeps a
// held token across the commit that is domain 3's alone, each stand-in owes a
// zero the cycle after any of its kills ended a round in which nothing
// passed, each pair of commits in series transfers together, and each
// kill_or's `many` is two or more of its inputs. Lesioned (an input left out
// of an OR; `many` on one input) the property of the thing broken fails.

// CHECK-DAG: -- invariant (was_c0 -> !u.buffer0.full)  is true
// CHECK-DAG: -- invariant (was_c2 -> !u.buffer0.full)  is true
// CHECK-DAG: -- invariant (was_c4 -> !u.buffer0.full)  is true
// CHECK-DAG: -- invariant (was_c1 -> !u.buffer1.full)  is true
// CHECK-DAG: -- invariant (was_c3 -> !u.buffer1.full)  is true
// CHECK-DAG: -- invariant ((((was_c4 & !was_c1) & !was_c3) & held4) -> u.buffer1.full)  is true
// CHECK-DAG: -- invariant (owed3 -> (u.stand_in0.outs_valid & u.stand_in0.outs = FALSE))  is true
// CHECK-DAG: -- invariant (owed4 -> (u.stand_in1.outs_valid & u.stand_in1.outs = FALSE))  is true
// CHECK-DAG: -- invariant (u.commit0.kill <-> u.commit1.kill)  is true
// CHECK-DAG: -- invariant (u.commit2.kill <-> u.commit3.kill)  is true
// CHECK-DAG: -- invariant (u.kill_domain3.many <-> (((u.commit0.kill & u.commit2.kill) | (u.commit0.kill & u.commit4.kill)) | (u.commit2.kill & u.commit4.kill)))  is true
// CHECK-DAG: -- invariant (u.kill_domain4.many <-> (u.commit1.kill & u.commit3.kill))  is true
// CHECK-NOT: is false
