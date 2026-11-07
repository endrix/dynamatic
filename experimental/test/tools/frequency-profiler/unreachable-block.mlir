// RUN: exp-frequency-profiler %s --top-level-function=unreachable 5 2 3 4 | FileCheck %s --implicit-check-not=4

// The profile numbers the blocks by position, as the lowering does. The
// lowering erases the blocks no path reaches before numbering the rest, and
// the profiler now does the same, or every block after an unreachable one was
// numbered one higher in the profile than in the circuit: here ^dead sat at
// 2, and the transitions into ^j named block 4, which the circuit has as 3.

// CHECK:     srcBlock,dstBlock,numTransitions,is_backedge
// CHECK-DAG: 0,1,1,0
// CHECK-DAG: 1,3,1,0
// CHECK-DAG: 0,2,0,0
// CHECK-DAG: 2,3,0,0
func.func @unreachable(%n: i32, %x0: i64, %x1: i64, %x2: i64) -> i64 {
  %zero = arith.constant 0 : i32
  %p = arith.cmpi sgt, %n, %zero : i32
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
