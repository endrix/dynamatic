// RUN: dynamatic-opt --force-memory-interface=force-mc=true --ftd-lower-cf-to-handshake --handshake-combine-steering-logic %s | FileCheck %s

// The exit merges of several returns are the merges that feed the end's
// results, and only their operands pass through a branch tagged with the
// operand's return block. The end control of the memory interface is also a
// merge of the exit block with one operand per return, and a match on block
// and shape wrapped it too: its operands are the returning blocks' controls,
// not values to steer.

// CHECK-LABEL:   handshake.func @twoReturnsMemory(
// CHECK:           mem_controller{{.*}} %[[CTRL:[a-z0-9_]+]] {connectedBlocks
// CHECK-NOT:       br %{{.*}} : <>
// CHECK:           %[[CTRL]] = merge %{{.*}}, %{{.*}} {handshake.bb = 3 : ui32{{.*}} : <>
// CHECK:           %[[X:.*]] = br %{{.*}} {handshake.bb = 1 : ui32{{.*}} : <i32>
// CHECK:           %[[Y:.*]] = br %{{.*}} {handshake.bb = 2 : ui32{{.*}} : <i32>
// CHECK:           %[[R:.*]] = merge %[[X]], %[[Y]] {handshake.bb = 3 : ui32
// CHECK:           end {handshake.bb = 3 : ui32{{.*}} %[[R]],
func.func @twoReturnsMemory(%c: i1, %i: index, %m: memref<4xi32>) -> i32 {
  cf.cond_br %c, ^x, ^y
^x:
  %a = memref.load %m[%i] {handshake.mem_interface = #handshake.mem_interface<MC>} : memref<4xi32>
  return %a : i32
^y:
  %b = memref.load %m[%i] {handshake.mem_interface = #handshake.mem_interface<MC>} : memref<4xi32>
  return %b : i32
}
