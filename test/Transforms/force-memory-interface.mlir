// RUN: dynamatic-opt %s --mark-memory-interfaces --force-memory-interface=force-mc | FileCheck %s

// Forcing the interfaces after they were chosen from dependences takes the
// word back: a forced controller says nothing about dependences.
// CHECK-LABEL:   func.func @forced(
// CHECK-NOT:       handshake.mem_interfaces_from_deps
// CHECK:           memref.load {{.*}}handshake.mem_interface<MC>
func.func @forced(%a: memref<8xi32>) -> i32 {
  %c0 = arith.constant {handshake.name = "c0"} 0 : index
  %v = memref.load %a[%c0] {handshake.name = "load0"} : memref<8xi32>
  return {handshake.name = "return0"} %v : i32
}
