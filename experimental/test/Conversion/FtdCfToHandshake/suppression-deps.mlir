// The suppression of a value delivered to a gamma, where the condition driving
// the gamma is itself control dependent on another condition. The suppression
// condition must be built over both: the gamma's own condition and the
// conditions the gamma's block is reached under. A suppression which reads only
// the gamma's own condition emits no branch in front of the input taken on the
// other path, and that input's token is left behind.
//
// The second RUN line fills freed memory with a pattern (glibc's
// MALLOC_PERTURB_; other C libraries ignore it). The suppression once read
// those dependences from a freed set, which dropped them on some runs only;
// with freed memory poisoned such a read fails on every run.
//
// RUN: dynamatic-opt --force-memory-interface=force-mc=true --ftd-lower-cf-to-handshake --handshake-combine-steering-logic %s | FileCheck %s
// RUN: env MALLOC_PERTURB_=165 dynamatic-opt --force-memory-interface=force-mc=true --ftd-lower-cf-to-handshake --handshake-combine-steering-logic %s | FileCheck %s

// A loop whose exit join takes either a value from before the loop (%x, when
// the loop never runs) or the value of the last iteration (%i2, when the
// in-loop condition ends it). The exit gamma selects on the loop condition
// (suppressed to one token per delivery, %[[SEL]]); its before-the-loop input
// must arrive through a branch on that same condition, so that %x is dropped on
// the executions the loop runs.
//
// CHECK-LABEL: handshake.func @exitx(
// CHECK-DAG:     %{{[a-zA-Z0-9_]+}}, %[[SEL:[a-zA-Z0-9_]+]] = cond_br %{{[0-9]+}}, %[[CH:[0-9]+]] {ftd.skip
// CHECK-DAG:     %{{[a-zA-Z0-9_]+}}, %[[X:[a-zA-Z0-9_]+]] = cond_br %[[SEL]], %arg2 {ftd.skip
// CHECK-DAG:     %{{[a-zA-Z0-9_]+}}, %[[I2:[a-zA-Z0-9_]+]] = cond_br %[[CB:[0-9]+]], %{{[0-9]+}} {handshake.bb = 2
// CHECK-DAG:     %[[CH]] = cmpi slt, %{{[a-zA-Z0-9_]+}}, %{{[a-zA-Z0-9_]+}} {handshake.bb = 1
// CHECK-DAG:     %[[CB]] = cmpi slt, %{{[a-zA-Z0-9_]+}}, %{{[a-zA-Z0-9_]+}} {handshake.bb = 2
// CHECK-DAG:     %[[J:[0-9]+]] = mux %[[SEL]] [%[[X]], %[[I2]]] {ftd.GAMMA
// CHECK:         end {{.*}} %[[J]], %arg3
func.func @exitx(%n: i32, %m: i32, %x: i32) -> i32 {
  %c0 = arith.constant 0 : i32
  %c1 = arith.constant 1 : i32
  cf.br ^h(%c0 : i32)
^h(%i: i32):
  %ch = arith.cmpi slt, %i, %n : i32
  cf.cond_br %ch, ^body, ^p(%x : i32)
^body:
  %i2 = arith.addi %i, %c1 : i32
  %cb = arith.cmpi slt, %i2, %m : i32
  cf.cond_br %cb, ^h(%i2 : i32), ^p(%i2 : i32)
^p(%v: i32):
  return %v : i32
}

// The same exit, with a diamond inside the loop between the header and the
// latch: the condition of the exit gamma (the loop condition, %[[SEL]]) is
// reached under conditions of its own. Again the before-the-loop input of the
// exit gamma (%x, sent from the header's exit) passes a branch on %[[SEL]],
// while the in-loop input comes from the latch's own exit.
//
// CHECK-LABEL: handshake.func @mexit(
// CHECK-DAG:     %[[XKEPT:[a-zA-Z0-9_]+]], %{{[a-zA-Z0-9_]+}} = cond_br %[[SEL:[a-zA-Z0-9_]+]], %arg3 {handshake.bb = 0
// CHECK-DAG:     %{{[a-zA-Z0-9_]+}}, %[[SEL]] = cond_br %{{[0-9]+}}, %{{[0-9]+}} {ftd.skip
// CHECK-DAG:     %{{[a-zA-Z0-9_]+}}, %[[S:[a-zA-Z0-9_]+]] = cond_br %{{[0-9]+}}, %{{[0-9]+}} {handshake.bb = 1
// CHECK-DAG:     %[[J:[0-9]+]] = mux %[[SEL]] [%[[S]], %[[XKEPT]]] {ftd.GAMMA, handshake.bb = 7
// CHECK:         end {{.*}} %[[J]], %arg4
func.func @mexit(%n: i32, %m: i32, %p: i1, %x: i32) -> i32 {
  %c0 = arith.constant 0 : i32
  %c1 = arith.constant 1 : i32
  cf.br ^h(%c0, %c0 : i32, i32)
^h(%i: i32, %s: i32):
  %ch = arith.cmpi slt, %i, %n : i32
  cf.cond_br %ch, ^b, ^e1
^b:
  %i2 = arith.addi %i, %c1 : i32
  cf.cond_br %p, ^t, ^jn(%i2 : i32)
^t:
  cf.br ^jn(%x : i32)
^jn(%v: i32):
  %s2 = arith.addi %s, %v : i32
  %cm = arith.cmpi slt, %s2, %m : i32
  cf.cond_br %cm, ^h(%i2, %s2 : i32, i32), ^e2
^e1:
  cf.br ^p(%s : i32)
^e2:
  cf.br ^p(%x : i32)
^p(%r: i32):
  return %r : i32
}
