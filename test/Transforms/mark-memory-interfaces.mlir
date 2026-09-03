// RUN: dynamatic-opt %s --mark-memory-interfaces | FileCheck %s

// A function whose interfaces this pass chose says so, for a pass that then
// takes a controller as the dependence analysis's word.
// CHECK-LABEL:   func.func @vouched(
// CHECK-SAME:      attributes {handshake.mem_interfaces_from_deps}
// CHECK:           memref.load {{.*}}handshake.mem_interface<MC>
func.func @vouched(%a: memref<8xi32>) -> i32 {
  %c0 = arith.constant {handshake.name = "c0"} 0 : index
  %v = memref.load %a[%c0] {handshake.name = "load0"} : memref<8xi32>
  return {handshake.name = "return0"} %v : i32
}
