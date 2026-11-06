// RUN: dynamatic-opt --lower-cf-to-handshake --remove-operation-names %s | FileCheck %s

// The end node of a function with one return is tagged with the block that
// holds the return, wherever that block is in the region. It used to be tagged
// with the last block, which put it in a block the returned values never
// reach (here ^b: a branch to the return block), and a lowering that reads the
// tag -- fast token delivery's suppression -- then steered the values wrong.
// A function of several returns keeps the fake exit block one past the last.

// CHECK-LABEL:   handshake.func @returnNotLast(
// CHECK:           end {handshake.bb = 1 : ui32}
func.func @returnNotLast(%c: i1, %a: i64, %b: i64) -> i64 {
  cf.cond_br %c, ^r(%a : i64), ^b
^r(%v: i64):
  return %v : i64
^b:
  cf.br ^r(%b : i64)
}

// CHECK-LABEL:   handshake.func @twoReturns(
// CHECK:           merge {{.*}} {handshake.bb = 3 : ui32}
// CHECK:           end {handshake.bb = 3 : ui32}
func.func @twoReturns(%c: i1, %a: i64, %b: i64) -> i64 {
  cf.cond_br %c, ^x, ^y
^x:
  return %a : i64
^y:
  return %b : i64
}
