// RUN: dynamatic-opt --force-memory-interface=force-mc=true --ftd-lower-cf-to-handshake --handshake-combine-steering-logic --handshake-straight-to-queue %s | FileCheck %s

// The exit block in the restored CFG.
//
// Several returns: the lowering puts the end and the merges of the returned
// values in a "fake" block numbered one past the last, but the CFG annotation
// had no edge into it, so the restore listed neither the returning blocks
// (sources of no edge) nor that block, and the entry's branch to a returning
// block aborted the pass. The annotation now has an edge from every returning
// block to the exit block, and the restore rebuilds every block an edge or an
// operation names.
//
// One return in a block that is not the last: the return block was not a
// source either, so the restore rebuilt the function without it and with a
// phantom block one past the last source.

// CHECK-LABEL:   handshake.func @twoReturns(
// CHECK:           %[[X:.*]] = br %{{.*}} {handshake.bb = 1 : ui32
// CHECK:           %[[Y:.*]] = br %{{.*}} {handshake.bb = 2 : ui32
// CHECK:           %[[R:.*]] = merge %[[X]], %[[Y]] {handshake.bb = 3 : ui32
// CHECK-NEXT:      end {handshake.bb = 3 : ui32{{.*}} %[[R]],
// CHECK-NEXT:    }
func.func @twoReturns(%n: i32, %a: i32, %b: i32) -> i32 {
  %zero = arith.constant 0 : i32
  %c = arith.cmpi sgt, %n, %zero : i32
  cf.cond_br %c, ^x, ^y
^x:
  %a2 = arith.addi %a, %n : i32
  return %a2 : i32
^y:
  %b2 = arith.subi %b, %n : i32
  return %b2 : i32
}

// CHECK-LABEL:   handshake.func @returnNotLast(
// CHECK:           %[[V:.*]] = mux %{{.*}} {ftd.GAMMA, handshake.bb = 1 : ui32
// CHECK:           end {handshake.bb = 1 : ui32{{.*}} %[[V]],
// CHECK-NEXT:    }
func.func @returnNotLast(%n: i32, %x: i32, %y: i32) -> i32 {
  %zero = arith.constant 0 : i32
  %p = arith.cmpi sgt, %n, %zero : i32
  cf.cond_br %p, ^b1, ^b2
^j(%v: i32):
  return %v : i32
^b1:
  %y2 = arith.addi %y, %y : i32
  cf.br ^j(%y2 : i32)
^b2:
  %x2 = arith.addi %x, %x : i32
  cf.br ^j(%x2 : i32)
}
