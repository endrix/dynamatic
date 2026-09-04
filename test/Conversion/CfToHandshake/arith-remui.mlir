// RUN: dynamatic-opt --lower-cf-to-handshake --remove-operation-names %s | FileCheck %s

// The unsigned remainder is a unit of its own, beside the signed one: a loop
// nest coalesced into one loop recovers its inner index with `remui` by the
// inner trip count, and nothing may lower that as a signed remainder on the
// strength of an argument about the operands' signs.
// CHECK-LABEL:   handshake.func @window(
// CHECK:           %[[REM:.*]] = remui %{{.*}}, %{{.*}} {handshake.bb = 0 : ui32} : <i32>
// CHECK:           %[[DIV:.*]] = divui %{{.*}}, %{{.*}} {handshake.bb = 0 : ui32} : <i32>
// CHECK:           %[[SUM:.*]] = addi %[[REM]], %[[DIV]] {handshake.bb = 0 : ui32} : <i32>
// CHECK:           end {handshake.bb = 0 : ui32} %[[SUM]], %{{.*}} : <i32>, <>
func.func @window(%k: i32) -> i32 {
  %c9 = arith.constant 9 : i32
  %j = arith.remui %k, %c9 : i32
  %i = arith.divui %k, %c9 : i32
  %s = arith.addi %j, %i : i32
  return %s : i32
}
