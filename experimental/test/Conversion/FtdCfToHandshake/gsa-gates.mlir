// The gates of the GSA analysis, through fast token delivery. A phi takes an
// operand when it is reached from one of the operand's senders (the
// predecessors passing it), wherever the operand is produced: a function
// argument, or a phi of a block above passed through unchanged, may be
// produced in a block dominating the blocks of the other operands. Each mux
// below is pinned by its select and by the value each of its inputs carries.
//
// RUN: dynamatic-opt --force-memory-interface=force-mc=true --ftd-lower-cf-to-handshake --handshake-combine-steering-logic %s | FileCheck %s

// A join of two: %w, the phi of a diamond, passed through from the block that
// branches to the join, and %x2, a function argument, from the other arm. The
// root selects on %q (false: %w, true: %x2), %w on %p (false: %x0, true: %x1).
//
// CHECK-LABEL: handshake.func @pass_through_and_argument(
// CHECK-DAG:     %[[X2:[a-zA-Z0-9_]+]], %{{[a-zA-Z0-9_]+}} = cond_br %arg1, %arg4
// CHECK-DAG:     %{{[a-zA-Z0-9_]+}}, %[[W:[a-zA-Z0-9_]+]] = cond_br %arg1, %[[PHI:[0-9]+]]
// CHECK-DAG:     %[[X1:[a-zA-Z0-9_]+]], %{{[a-zA-Z0-9_]+}} = cond_br %arg0, %arg3
// CHECK-DAG:     %{{[a-zA-Z0-9_]+}}, %[[X0:[a-zA-Z0-9_]+]] = cond_br %arg0, %arg2
// CHECK-DAG:     %[[PHI]] = mux %arg0 [%[[X0]], %[[X1]]] {ftd.GAMMA
// CHECK-DAG:     %[[J:[0-9]+]] = mux %arg1 [%[[W]], %[[X2]]] {ftd.GAMMA
// CHECK:         end {{.*}} %[[J]], %arg5
func.func @pass_through_and_argument(%p: i1, %q: i1, %x0: i64, %x1: i64, %x2: i64) -> i64 {
  cf.cond_br %p, ^b3, ^b4(%x0 : i64)
^b3:
  cf.br ^b4(%x1 : i64)
^b4(%w: i64):
  cf.cond_br %q, ^b7, ^j(%w : i64)
^b7:
  cf.br ^j(%x2 : i64)
^j(%l: i64):
  return %l : i64
}

// The phi of ^b4 has a single predecessor, hence a single operand: it is that
// operand, and no gate stands for it.
//
// CHECK-LABEL: handshake.func @single_predecessor(
// CHECK-DAG:     %[[X2:[a-zA-Z0-9_]+]], %{{[a-zA-Z0-9_]+}} = cond_br %arg0, %arg2
// CHECK-DAG:     %{{[a-zA-Z0-9_]+}}, %[[X0:[a-zA-Z0-9_]+]] = cond_br %arg0, %arg1
// CHECK-DAG:     %[[J:[0-9]+]] = mux %arg0 [%[[X0]], %[[X2]]] {ftd.GAMMA
// CHECK:         end {{.*}} %[[J]], %arg3
func.func @single_predecessor(%q: i1, %x0: i64, %x2: i64) -> i64 {
  cf.br ^b4(%x0 : i64)
^b4(%w: i64):
  cf.cond_br %q, ^b7, ^j(%w : i64)
^b7:
  cf.br ^j(%x2 : i64)
^j(%l: i64):
  return %l : i64
}

// Both predecessors of ^m send %x0: the phi of ^m has a single operand.
//
// CHECK-LABEL: handshake.func @same_value(
// CHECK-DAG:     %[[X1:[a-zA-Z0-9_]+]], %{{[a-zA-Z0-9_]+}} = cond_br %arg1, %arg3
// CHECK-DAG:     %{{[a-zA-Z0-9_]+}}, %[[X0:[a-zA-Z0-9_]+]] = cond_br %arg1, %arg2
// CHECK-DAG:     %[[J:[0-9]+]] = mux %arg1 [%[[X0]], %[[X1]]] {ftd.GAMMA
// CHECK:         end {{.*}} %[[J]], %arg4
func.func @same_value(%p: i1, %q: i1, %x0: i64, %x1: i64) -> i64 {
  cf.cond_br %p, ^t, ^f
^t:
  cf.br ^m(%x0 : i64)
^f:
  cf.br ^m(%x0 : i64)
^m(%w: i64):
  cf.cond_br %q, ^a, ^j(%w : i64)
^a:
  cf.br ^j(%x1 : i64)
^j(%l: i64):
  return %l : i64
}

// A join of three, with a pass-through and arguments. The root selects on %q
// (true: %x2), the gamma under it on %r, delivered when %q is false (false:
// %w, which is %x0, true: %x4).
//
// CHECK-LABEL: handshake.func @three_way(
// CHECK-DAG:     %{{[a-zA-Z0-9_]+}}, %[[X4:[a-zA-Z0-9_]+]] = cond_br %{{[0-9]+}}, %arg4
// CHECK-DAG:     %{{[a-zA-Z0-9_]+}}, %[[X0:[a-zA-Z0-9_]+]] = cond_br %{{[0-9]+}}, %arg2
// CHECK-DAG:     %[[X2:[a-zA-Z0-9_]+]], %{{[a-zA-Z0-9_]+}} = cond_br %arg0, %arg3
// CHECK-DAG:     %{{[a-zA-Z0-9_]+}}, %[[R:[a-zA-Z0-9_]+]] = cond_br %arg0, %arg1
// CHECK-DAG:     %[[J:[0-9]+]] = mux %arg0 [%[[INNER:[0-9]+]], %[[X2]]] {ftd.GAMMA
// CHECK-DAG:     %[[INNER]] = mux %[[R]] [%[[X0]], %[[X4]]] {ftd.GAMMA
// CHECK:         end {{.*}} %[[J]], %arg5
func.func @three_way(%q: i1, %r: i1, %x0: i64, %x2: i64, %x4: i64) -> i64 {
  cf.br ^b4(%x0 : i64)
^b4(%w: i64):
  cf.cond_br %q, ^b7, ^b10
^b7:
  cf.br ^j(%x2 : i64)
^b10:
  cf.cond_br %r, ^b13, ^j(%w : i64)
^b13:
  cf.br ^j(%x4 : i64)
^j(%l: i64):
  return %l : i64
}

// A latch sends %c0, produced before the loop: it is an input of the MU from
// inside the loop, and the same value sent from the entry is its initial
// input. The loop input of the MU of %s is a gamma on %p (false: %c0, true:
// %s2).
//
// CHECK-LABEL: handshake.func @latch_sends_value_from_before_loop(
// CHECK-DAG:     %[[PR:[0-9]+]] = mux %{{[0-9]+}} [%arg1, %[[P:[a-zA-Z0-9_]+]]] {ftd.regen
// CHECK-DAG:     %[[P]], %{{[a-zA-Z0-9_]+}} = cond_br %{{[0-9]+}}, %[[PR]]
// CHECK-DAG:     %[[C0:[0-9]+]] = constant %{{[0-9]+}} {{.*}}value = 0 : i32
// CHECK-DAG:     %[[S2L:[a-zA-Z0-9_]+]], %{{[a-zA-Z0-9_]+}} = cond_br %[[P]], %[[S2:[0-9]+]]
// CHECK-DAG:     %[[S2]] = addi
// CHECK-DAG:     %[[LOOP:[0-9]+]] = mux %[[P]] [%[[C0]], %[[S2L]]] {ftd.GAMMA
// CHECK-DAG:     %[[S:[0-9]+]] = mux %{{[0-9]+}} [%[[C0]], %[[LOOP]]] {ftd.MU
// CHECK-DAG:     %{{[a-zA-Z0-9_]+}}, %[[OUT:[a-zA-Z0-9_]+]] = cond_br %{{[0-9]+}}, %[[S]]
// CHECK:         end {{.*}} %[[OUT]], %arg2
func.func @latch_sends_value_from_before_loop(%n: i32, %p: i1) -> i32 {
  %c0 = arith.constant 0 : i32
  %c1 = arith.constant 1 : i32
  cf.br ^h(%c0, %c0 : i32, i32)
^h(%i: i32, %s: i32):
  %cond = arith.cmpi slt, %i, %n : i32
  cf.cond_br %cond, ^b, ^e
^b:
  %s2 = arith.addi %s, %i : i32
  %i2 = arith.addi %i, %c1 : i32
  cf.cond_br %p, ^l1, ^l2
^l1:
  cf.br ^h(%i2, %s2 : i32, i32)
^l2:
  cf.br ^h(%i2, %c0 : i32, i32)
^e:
  return %s : i32
}

// The CFG of an action body (skip_mode_params of an AV1 decoder), reduced as
// far as the analysis still failed on it: in a loop, ^bb14 joins the phi of
// ^bb10 (single predecessor), passed through, and a function argument. The
// MU's loop input is a gamma on %a16 (false: %a14, true: %z28).
//
// CHECK-LABEL: handshake.func @skip_mode_params_reduced(
// CHECK-DAG:     %[[A16R:[0-9]+]] = mux %{{[0-9]+}} [%arg2, %[[A16:[a-zA-Z0-9_]+]]] {ftd.regen
// CHECK-DAG:     %[[A16]], %{{[a-zA-Z0-9_]+}} = cond_br %{{[0-9]+}}, %[[A16R]]
// CHECK-DAG:     %{{[a-zA-Z0-9_]+}}, %[[A14:[a-zA-Z0-9_]+]] = cond_br %{{[0-9]+}}, %arg1
// CHECK-DAG:     %{{[a-zA-Z0-9_]+}}, %[[Z28:[a-zA-Z0-9_]+]] = cond_br %{{[0-9]+}}, %arg3
// CHECK-DAG:     %[[G:[0-9]+]] = mux %[[A16]] [%[[A14]], %[[Z28]]] {ftd.GAMMA
// CHECK-DAG:     %[[MU:[0-9]+]] = mux %{{[0-9]+}} [%arg4, %[[G]]] {ftd.MU
// CHECK-DAG:     %{{[a-zA-Z0-9_]+}}, %[[OUT:[a-zA-Z0-9_]+]] = cond_br %{{[0-9]+}}, %[[MU]]
// CHECK:         end {{.*}} %[[OUT]], %arg5
func.func @skip_mode_params_reduced(%a5: i1, %a14: i64, %a16: i1, %z28: i64, %z13: i64) -> i64 {
  cf.br ^bb1(%z13 : i64)
^bb1(%acc: i64):
  cf.cond_br %a5, ^bb10(%a14 : i64), ^bb30
^bb10(%519: i64):
  cf.cond_br %a16, ^bb13, ^bb14(%519 : i64)
^bb13:
  cf.br ^bb14(%z28 : i64)
^bb14(%547: i64):
  cf.br ^bb1(%547 : i64)
^bb30:
  return %acc : i64
}

// The CFG of an action body (lr_params of an AV1 decoder), reduced as far as
// it still failed when its 17 blocks were indexed by a sort with dominance as
// comparator: in the order that sort gave, the delivery of the returned
// argument and of the end's control went through a branch on a constant true
// and never reached the end. The block indexing is a topological order of the
// CFG without its back edges, and the end takes both directly.
//
// CHECK-LABEL: handshake.func @seventeen_blocks(
// CHECK-NOT:     constant
// CHECK:         end {{.*}} %arg3, %arg4
func.func @seventeen_blocks(%a0: i1, %a12: i1, %a23: i1, %z9: i33) -> i33 {
  cf.cond_br %a0, ^bb1, ^bb2
^bb1:
  cf.br ^bb2
^bb2:
  cf.br ^bb3
^bb3:
  cf.br ^bb4
^bb4:
  cf.cond_br %a12, ^bb5, ^bb8
^bb5:
  cf.br ^bb6
^bb6:
  cf.br ^bb7
^bb7:
  cf.br ^bb4
^bb8:
  cf.br ^bb9
^bb9:
  cf.cond_br %a23, ^bb10, ^bb11
^bb10:
  cf.br ^bb13
^bb11:
  cf.br ^bb12
^bb12:
  cf.br ^bb13
^bb13:
  cf.br ^bb14
^bb14:
  cf.br ^bb15
^bb15:
  cf.br ^bb16
^bb16:
  return %z9 : i33
}
