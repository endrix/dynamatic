// The merge of identical gammas in addGsaGates. The gammas of a tree are in
// one block and take no suppression from one another, so the token of a gamma
// goes to every mux it feeds: two identical gammas are merged only when every
// mux they feed takes the token on every execution which produces it, that is
// when they are consumed under the same conditions. A sub-gamma of a block
// reached on two routes of the tree hangs below two parents, which are not
// selected on the same executions, and is not merged; nor are the roots of two
// blocks. Two gammas below one mux whose two inputs are then the same, and the
// initial inputs of two MUs of one loop, are merged.
//
// RUN: dynamatic-opt --force-memory-interface=force-mc=true --ftd-lower-cf-to-handshake --handshake-combine-steering-logic %s | FileCheck %s

// ^b is reached from ^a (when %a and %b hold) and from ^c (when %a does not
// hold and %d does): the gamma of ^b, on %c, is below the gamma on %b on the
// first route and below the gamma on %d on the second. Each of the two has its
// own, fed by %x2 and %x3 through its own suppression.
//
// CHECK-LABEL: handshake.func @order_topo(
// CHECK-DAG:     %[[R:[0-9]+]] = mux %arg0 [%[[VC:[0-9]+]], %[[VA:[0-9]+]]] {ftd.GAMMA
// CHECK-DAG:     %[[VC]] = mux %{{[a-zA-Z0-9_]+}} [%{{[a-zA-Z0-9_]+}}, %[[BC:[0-9]+]]] {ftd.GAMMA
// CHECK-DAG:     %[[VA]] = mux %{{[a-zA-Z0-9_]+}} [%{{[a-zA-Z0-9_]+}}, %[[BA:[0-9]+]]] {ftd.GAMMA
// CHECK-DAG:     %[[BC]] = mux %{{[a-zA-Z0-9_]+}} [%{{(true|false)Result[_0-9]*}}, %{{(true|false)Result[_0-9]*}}] {ftd.GAMMA
// CHECK-DAG:     %[[BA]] = mux %{{[a-zA-Z0-9_]+}} [%{{(true|false)Result[_0-9]*}}, %{{(true|false)Result[_0-9]*}}] {ftd.GAMMA
// CHECK-DAG:     end {{.*}} %[[R]], %arg8
func.func @order_topo(%a: i1, %b: i1, %c: i1, %d: i1, %x1: i64, %x2: i64, %x3: i64, %x4: i64) -> i64 {
  cf.cond_br %a, ^a, ^c
^a:
  cf.cond_br %b, ^b, ^j(%x1 : i64)
^c:
  cf.cond_br %d, ^b, ^j(%x4 : i64)
^b:
  cf.cond_br %c, ^j(%x2 : i64), ^e
^e:
  cf.br ^j(%x3 : i64)
^j(%l: i64):
  return %l : i64
}

// The shape of a random CFG (seed 10 of the fuzzer): ^p is reached from the
// entry (when %a holds) and from ^q (when %a does not hold and %b does), so the
// gamma of ^p, on %e, is below the root and below the gamma on %b. Each has
// its own.
//
// CHECK-LABEL: handshake.func @two_depths(
// CHECK-DAG:     %[[R:[0-9]+]] = mux %arg0 [%[[Q:[0-9]+]], %[[PA:[0-9]+]]] {ftd.GAMMA
// CHECK-DAG:     %[[Q]] = mux %{{[a-zA-Z0-9_]+}} [%[[RD:[0-9]+]], %[[PB:[0-9]+]]] {ftd.GAMMA
// CHECK-DAG:     %[[RD]] = mux %{{[a-zA-Z0-9_]+}} [%{{(true|false)Result[_0-9]*}}, %{{(true|false)Result[_0-9]*}}] {ftd.GAMMA
// CHECK-DAG:     %[[PA]] = mux %{{[a-zA-Z0-9_]+}} [%{{(true|false)Result[_0-9]*}}, %{{(true|false)Result[_0-9]*}}] {ftd.GAMMA
// CHECK-DAG:     %[[PB]] = mux %{{[a-zA-Z0-9_]+}} [%{{(true|false)Result[_0-9]*}}, %{{(true|false)Result[_0-9]*}}] {ftd.GAMMA
// CHECK-DAG:     end {{.*}} %[[R]], %arg7
func.func @two_depths(%a: i1, %b: i1, %d: i1, %e: i1, %x1: i64, %x2: i64, %x3: i64) -> i64 {
  cf.cond_br %a, ^p, ^q
^q:
  cf.cond_br %b, ^p, ^r
^r:
  cf.cond_br %d, ^j(%x1 : i64), ^s
^p:
  cf.cond_br %e, ^s, ^j(%x2 : i64)
^s:
  cf.br ^j(%x3 : i64)
^j(%v: i64):
  return %v : i64
}

// The phis of ^j1 (block 3) and ^j2 (block 4) both select %y or %x on %c, and
// each block has its own gamma: ^j2 is reached on the executions which do not
// reach ^j1. The addition of ^j2 takes the gamma of ^j2.
//
// CHECK-LABEL: handshake.func @two_blocks(
// CHECK-DAG:     %{{[0-9]+}} = mux %{{[a-zA-Z0-9_]+}} [%{{[a-zA-Z0-9_]+}}, %{{[a-zA-Z0-9_]+}}] {ftd.GAMMA, handshake.bb = 3 :
// CHECK-DAG:     %[[J2:[0-9]+]] = mux %{{[a-zA-Z0-9_]+}} [%{{[a-zA-Z0-9_]+}}, %{{[a-zA-Z0-9_]+}}] {ftd.GAMMA, handshake.bb = 4 :
// CHECK-DAG:     addi %[[J2]], %[[J2]] {handshake.bb = 4 :
func.func @two_blocks(%c: i1, %e: i1, %x: i64, %y: i64) -> i64 {
  cf.cond_br %c, ^t, ^f
^t:
  cf.cond_br %e, ^j1(%x : i64), ^j2(%x : i64)
^f:
  cf.cond_br %e, ^j1(%y : i64), ^j2(%y : i64)
^j1(%a: i64):
  cf.br ^r(%a : i64)
^j2(%b: i64):
  %b2 = arith.addi %b, %b : i64
  cf.br ^r(%b2 : i64)
^r(%o: i64):
  return %o : i64
}

// When %a does not hold, ^m is reached from ^q directly (when %b holds) or by
// the loop of ^w, left when %l does not hold: both sides of the gamma on %b
// select %x or %y on %c, the two gammas on %c are merged, and the gamma on %b,
// whose two inputs are then the same, is bypassed.
//
// CHECK-LABEL: handshake.func @loop_exit(
// CHECK-DAG:     %[[R:[0-9]+]] = mux %arg0 [%[[M:[0-9]+]], %{{[a-zA-Z0-9_]+}}] {ftd.GAMMA
// CHECK-DAG:     %[[M]] = mux %{{[a-zA-Z0-9_]+}} [%{{(true|false)Result[_0-9]*}}, %{{(true|false)Result[_0-9]*}}] {ftd.GAMMA
// CHECK-DAG:     end {{.*}} %[[R]], %arg6
func.func @loop_exit(%a: i1, %b: i1, %l: i1, %c: i1, %x: i64, %y: i64) -> i64 {
  cf.cond_br %a, ^s, ^q
^q:
  cf.cond_br %b, ^m, ^w
^w:
  cf.cond_br %l, ^w, ^m
^m:
  cf.cond_br %c, ^j(%x : i64), ^s
^s:
  cf.br ^j(%y : i64)
^j(%v: i64):
  return %v : i64
}

// The MUs of %u and %w in the inner loop's header (block 4) take %x or %s on
// %p on entry: one gamma is the initial input of both.
//
// CHECK-LABEL: handshake.func @two_mus(
// CHECK-DAG:     %[[I:[0-9]+]] = mux %{{[a-zA-Z0-9_]+}} [%{{[a-zA-Z0-9_]+}}, %{{[a-zA-Z0-9_]+}}] {ftd.GAMMA, handshake.bb = 4 :
// CHECK-DAG:     mux %{{[a-zA-Z0-9_]+}} [%[[I]], %{{[a-zA-Z0-9_]+}}] {ftd.MU, handshake.bb = 4 :
// CHECK-DAG:     mux %{{[a-zA-Z0-9_]+}} [%[[I]], %{{[a-zA-Z0-9_]+}}] {ftd.MU, handshake.bb = 4 :
func.func @two_mus(%n: i32, %m: i32, %p: i1, %x: i32) -> i32 {
  %c0 = arith.constant 0 : i32
  %c1 = arith.constant 1 : i32
  cf.br ^oh(%c0, %c0 : i32, i32)
^oh(%i: i32, %s: i32):
  %co = arith.cmpi slt, %i, %n : i32
  cf.cond_br %co, ^ob, ^e
^ob:
  cf.cond_br %p, ^ih(%c0, %x, %x : i32, i32, i32), ^ob2
^ob2:
  cf.br ^ih(%c0, %s, %s : i32, i32, i32)
^ih(%j: i32, %u: i32, %w: i32):
  %ci = arith.cmpi slt, %j, %m : i32
  cf.cond_br %ci, ^ib, ^ix
^ib:
  %j2 = arith.addi %j, %c1 : i32
  %u2 = arith.addi %u, %j : i32
  %w2 = arith.muli %w, %c1 : i32
  %w3 = arith.addi %w2, %c1 : i32
  cf.br ^ih(%j2, %u2, %w3 : i32, i32, i32)
^ix:
  %i2 = arith.addi %i, %c1 : i32
  %s2 = arith.addi %u, %w : i32
  cf.br ^oh(%i2, %s2 : i32, i32)
^e:
  return %s : i32
}
