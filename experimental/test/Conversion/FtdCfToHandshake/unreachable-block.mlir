// RUN: dynamatic-opt --force-memory-interface=force-mc=true --ftd-lower-cf-to-handshake --handshake-combine-steering-logic %s | FileCheck %s

// A block no path reaches is erased before the CFG is captured: the lowering
// asserted on it, and the GSA analysis would have read its argument as a
// third input of the join.

// CHECK-LABEL:   handshake.func @unreachable(
// CHECK:           end
func.func @unreachable(%p: i1, %x0: i64, %x1: i64, %x2: i64) -> i64 {
  cf.cond_br %p, ^b1, ^b2
^b1:
  cf.br ^j(%x0 : i64)
^dead:
  cf.br ^j(%x2 : i64)
^b2:
  cf.br ^j(%x1 : i64)
^j(%l: i64):
  return %l : i64
}
