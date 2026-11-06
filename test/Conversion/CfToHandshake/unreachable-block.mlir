// RUN: dynamatic-opt --lower-cf-to-handshake --remove-operation-names %s | FileCheck %s

// A block no path reaches is erased before the lowering looks at the CFG. It
// has no control token and no predecessor to merge its arguments from, and
// the lowering asserted on it ("block argument must have predecessors").

// CHECK-LABEL:   handshake.func @unreachable(
// CHECK-NOT:       handshake.bb = 2
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
