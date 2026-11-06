// RUN: dynamatic-opt --force-memory-interface=force-mc=true --ftd-lower-cf-to-handshake --handshake-combine-steering-logic %s | FileCheck %s

// The exit block as the lowering numbers it, in the shadow CFG.
//
// Several returns: the lowering puts the end and the merges of the returned
// values in a "fake" block numbered one past the last, and the shadow CFG the
// pass rebuilds from the original topology has that block too, with every
// returning block branching to it. Without it, the first consumer tagged with
// that index asked the shadow for a block it did not have and the compiler
// aborted ("BB index out of range in shadow CFG"); skip_mode_params' first
// loop was the AV1 body that hit it.
//
// The merges of that block take one value from each returning block, and the
// suppression, seeing every path reach the block, delivered all of them: a
// two-return function returned both values. Each operand now passes through
// a branch tagged with its own return block, fed only when that block ran.
//
// One return in a block that is not the last: the end is tagged with the
// return's block. Tagged with the last block (^b, which branches to the
// return), the suppression read the end as a consumer in ^b, where the
// values returned from ^r never go, and steered them wrong (the review's
// nontopo).

// CHECK-LABEL:   handshake.func @twoReturns(
// CHECK:           %[[X:.*]] = br %{{.*}} {handshake.bb = 1 : ui32,
// CHECK:           %[[Y:.*]] = br %{{.*}} {handshake.bb = 2 : ui32,
// CHECK:           %[[R:.*]] = merge %[[X]], %[[Y]] {handshake.bb = 3 : ui32,
// CHECK:           end {handshake.bb = 3 : ui32, {{.*}} %[[R]],
func.func @twoReturns(%c: i1, %a: i64, %b: i64) -> i64 {
  cf.cond_br %c, ^x, ^y
^x:
  return %a : i64
^y:
  return %b : i64
}

// CHECK-LABEL:   handshake.func @returnNotLast(
// CHECK:           end {handshake.bb = 1 : ui32,
func.func @returnNotLast(%p: i1, %q: i1, %x: i64, %y: i64, %z: i64) -> i64 {
  cf.cond_br %p, ^b1, ^b2
^j(%v: i64):
  return %v : i64
^b1:
  %y2 = arith.addi %y, %y : i64
  cf.cond_br %q, ^j(%y2 : i64), ^b3
^b3:
  %z2 = arith.addi %z, %y2 : i64
  cf.br ^j(%z2 : i64)
^b2:
  %x2 = arith.addi %x, %x : i64
  cf.br ^j(%x2 : i64)
}
