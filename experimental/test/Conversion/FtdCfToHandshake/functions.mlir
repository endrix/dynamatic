// Fast token delivery on a module of several functions (the analysis is
// built per function), with a branch condition that is an argument (no
// defining operation to name), and with a loop. A diamond whose arms are
// pure becomes one mux on its condition and no control merge; the arms'
// operands are branched on the condition, so an arm that is not taken
// computes nothing and leaves no token behind.
//
// RUN: dynamatic-opt --force-memory-interface=force-mc=true --ftd-lower-cf-to-handshake --handshake-combine-steering-logic %s | FileCheck %s

// CHECK-LABEL: handshake.func @diamond(
// CHECK-NOT:     control_merge
// CHECK:         mux %{{.*}} [%{{.*}}, %{{.*}}] {ftd.GAMMA
// CHECK-NOT:     control_merge
// CHECK:         end
func.func @diamond(%a: i32, %b: i32) -> i32 {
  %c = arith.cmpi slt, %a, %b : i32
  cf.cond_br %c, ^t, ^f
^t:
  %x = arith.addi %a, %a : i32
  cf.br ^j(%x : i32)
^f:
  %y = arith.muli %a, %a : i32
  cf.br ^j(%y : i32)
^j(%v: i32):
  %r = arith.subi %v, %a : i32
  return %r : i32
}

// CHECK-LABEL: handshake.func @argument_condition(
// CHECK:         mux %arg1 [%{{.*}}, %{{.*}}] {ftd.GAMMA
// CHECK:         end
func.func @argument_condition(%a: i32, %c: i1) -> i32 {
  cf.cond_br %c, ^t, ^f
^t:
  %x = arith.addi %a, %a : i32
  cf.br ^j(%x : i32)
^f:
  %y = arith.muli %a, %a : i32
  cf.br ^j(%y : i32)
^j(%v: i32):
  return %v : i32
}

// CHECK-LABEL: handshake.func @loop(
// CHECK:         mux %{{.*}} [%{{.*}}, %{{.*}}] {ftd.MU
// CHECK:         end
func.func @loop(%n: i32) -> i32 {
  %c0 = arith.constant 0 : i32
  %c1 = arith.constant 1 : i32
  cf.br ^h(%c0, %c0 : i32, i32)
^h(%i: i32, %s: i32):
  %cond = arith.cmpi slt, %i, %n : i32
  cf.cond_br %cond, ^b, ^e
^b:
  %s2 = arith.addi %s, %i : i32
  %i2 = arith.addi %i, %c1 : i32
  cf.br ^h(%i2, %s2 : i32, i32)
^e:
  return %s : i32
}

// An argument read inside a conditional block is delivered like any other
// value: suppressed when the block does not run. Without it the addition
// waited for ever at its join, the argument's token there and the branched
// value never coming (found on an action body of the picorv32 Core).
// CHECK-LABEL: handshake.func @argument_in_branch(
// CHECK-DAG:     %[[B:.*]], %{{.*}} = cond_br %{{.*}}, %arg1 {
// CHECK-DAG:     %[[A:.*]], %{{.*}} = cond_br %{{.*}}, %arg0 {
// CHECK:         addi %[[A]], %[[B]] {handshake.bb = 1
// CHECK:         end
func.func @argument_in_branch(%a: i32, %b: i32) -> i32 {
  %c = arith.cmpi slt, %a, %b : i32
  cf.cond_br %c, ^t, ^j(%a : i32)
^t:
  %x = arith.addi %a, %b : i32
  cf.br ^j(%x : i32)
^j(%v: i32):
  return %v : i32
}
