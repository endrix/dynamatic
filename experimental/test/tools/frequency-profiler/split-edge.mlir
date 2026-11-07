// RUN: exp-frequency-profiler %s --top-level-function=twoValues 5 2 3 | FileCheck %s --check-prefix=PLAIN
// RUN: exp-frequency-profiler %s --top-level-function=twoValues --ftd 5 2 3 | FileCheck %s --check-prefix=FTD
// REQUIRES: exp-frequency-profiler

// A conditional branch reaching one block on both of its edges, with
// different operands, sends two values from one predecessor. The fast token
// delivery lowering routes its true edge through a new block placed right
// after it (splitEdgesSendingTwoValues), which shifts the position of every
// later block by one, and the profile of that flow has to number the blocks
// the same way: here ^j is 1 in the plain lowering's circuit and 2 in the
// fast token delivery's, and the transition out of the split edge goes
// through the new block 1. Without `--ftd` the profile is the plain one.

// PLAIN:      srcBlock,dstBlock,numTransitions,is_backedge
// PLAIN-NEXT: 0,1,1,0
// PLAIN-NOT:  {{[0-9]}}

// FTD:      srcBlock,dstBlock,numTransitions,is_backedge
// FTD-NEXT: 0,1,1,0
// FTD-NEXT: 1,2,1,0
// FTD-NEXT: 0,2,0,0
// FTD-NOT:  {{[0-9]}}
func.func @twoValues(%n: i32, %x0: i64, %x1: i64) -> i64 {
  %zero = arith.constant 0 : i32
  %p = arith.cmpi sgt, %n, %zero : i32
  cf.cond_br %p, ^j(%x0 : i64), ^j(%x1 : i64)
^j(%l: i64):
  return %l : i64
}
