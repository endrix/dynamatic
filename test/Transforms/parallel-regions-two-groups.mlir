// RUN: dynamatic-opt %s --cf-detect-parallel-regions --lower-cf-to-handshake --handshake-deactivate-mem-dependencies --handshake-replace-memory-interfaces --handshake-parallelize-regions --split-input-file --verify-diagnostics | FileCheck %s

// Two groups in one chain, from the cf level to the rewired circuit (the
// order compile.sh runs the passes in). The third loop is the first group's
// successor and runs alone, so the second group's entry, the third loop's
// block, is not in the first group: the first group's join goes into the
// third loop's block, and the second group, between that block and the
// return, is rewired as well. A second group that started at the third loop
// would find the first's join in its first region and be declined.
// CHECK-LABEL:   handshake.func @two_groups(
// CHECK-SAME:      handshake.parallel_regions = [{entry = 0 : ui32, regions = {{\[}}[1], [2]], successor = 3 : ui32}, {entry = 3 : ui32, regions = {{\[}}[4], [5]], successor = 6 : ui32}]
// CHECK:           join %{{.*}}, %{{.*}} {handshake.bb = 3 : ui32
// CHECK:           join %{{.*}}, %{{.*}} {handshake.bb = 6 : ui32
// expected-remark @below {{parallel regions [1] [2] between blocks 0 and 3}}
// expected-remark @below {{parallel regions [4] [5] between blocks 3 and 6}}
func.func @two_groups(%a: memref<8xi32>, %x1: memref<8xi32>, %x2: memref<8xi32>, %x3: memref<8xi32>, %x4: memref<8xi32>, %x5: memref<8xi32>) {
  %c0 = arith.constant {handshake.name = "c0"} 0 : index
  cf.br ^bb1(%c0 : index) {handshake.name = "br0"}
^bb1(%i: index):
  %c1 = arith.constant {handshake.name = "c1"} 1 : index
  %c8 = arith.constant {handshake.name = "c8"} 8 : index
  %z = arith.constant {handshake.name = "z"} 0 : index
  %v = memref.load %a[%i] {handshake.mem_interface = #handshake.mem_interface<MC>, handshake.name = "load0"} : memref<8xi32>
  memref.store %v, %x1[%i] {handshake.mem_interface = #handshake.mem_interface<MC>, handshake.name = "store0"} : memref<8xi32>
  %i1 = arith.addi %i, %c1 {handshake.name = "inc_i"} : index
  %cond = arith.cmpi ult, %i1, %c8 {handshake.name = "cmp1"} : index
  cf.cond_br %cond, ^bb1(%i1 : index), ^bb2(%z : index) {handshake.name = "cond_br0"}
^bb2(%j: index):
  %c1_0 = arith.constant {handshake.name = "c1_0"} 1 : index
  %c8_0 = arith.constant {handshake.name = "c8_0"} 8 : index
  %z_0 = arith.constant {handshake.name = "z_0"} 0 : index
  %w = memref.load %a[%j] {handshake.mem_interface = #handshake.mem_interface<MC>, handshake.name = "load1"} : memref<8xi32>
  memref.store %w, %x2[%j] {handshake.mem_interface = #handshake.mem_interface<MC>, handshake.name = "store1"} : memref<8xi32>
  %j1 = arith.addi %j, %c1_0 {handshake.name = "inc_j"} : index
  %cond_0 = arith.cmpi ult, %j1, %c8_0 {handshake.name = "cmp2"} : index
  cf.cond_br %cond_0, ^bb2(%j1 : index), ^bb3(%z_0 : index) {handshake.name = "cond_br1"}
^bb3(%k: index):
  %c1_1 = arith.constant {handshake.name = "c1_1"} 1 : index
  %c8_1 = arith.constant {handshake.name = "c8_1"} 8 : index
  %z_1 = arith.constant {handshake.name = "z_1"} 0 : index
  %u = memref.load %x1[%k] {handshake.mem_interface = #handshake.mem_interface<MC>, handshake.name = "load2"} : memref<8xi32>
  memref.store %u, %x3[%k] {handshake.mem_interface = #handshake.mem_interface<MC>, handshake.name = "store2"} : memref<8xi32>
  %k1 = arith.addi %k, %c1_1 {handshake.name = "inc_k"} : index
  %cond_1 = arith.cmpi ult, %k1, %c8_1 {handshake.name = "cmp3"} : index
  cf.cond_br %cond_1, ^bb3(%k1 : index), ^bb4(%z_1 : index) {handshake.name = "cond_br2"}
^bb4(%l: index):
  %c1_2 = arith.constant {handshake.name = "c1_2"} 1 : index
  %c8_2 = arith.constant {handshake.name = "c8_2"} 8 : index
  %z_2 = arith.constant {handshake.name = "z_2"} 0 : index
  %p = memref.load %a[%l] {handshake.mem_interface = #handshake.mem_interface<MC>, handshake.name = "load3"} : memref<8xi32>
  memref.store %p, %x4[%l] {handshake.mem_interface = #handshake.mem_interface<MC>, handshake.name = "store3"} : memref<8xi32>
  %l1 = arith.addi %l, %c1_2 {handshake.name = "inc_l"} : index
  %cond_2 = arith.cmpi ult, %l1, %c8_2 {handshake.name = "cmp4"} : index
  cf.cond_br %cond_2, ^bb4(%l1 : index), ^bb5(%z_2 : index) {handshake.name = "cond_br3"}
^bb5(%m: index):
  %c1_3 = arith.constant {handshake.name = "c1_3"} 1 : index
  %c8_3 = arith.constant {handshake.name = "c8_3"} 8 : index
  %q = memref.load %a[%m] {handshake.mem_interface = #handshake.mem_interface<MC>, handshake.name = "load4"} : memref<8xi32>
  memref.store %q, %x5[%m] {handshake.mem_interface = #handshake.mem_interface<MC>, handshake.name = "store4"} : memref<8xi32>
  %m1 = arith.addi %m, %c1_3 {handshake.name = "inc_m"} : index
  %cond_3 = arith.cmpi ult, %m1, %c8_3 {handshake.name = "cmp5"} : index
  cf.cond_br %cond_3, ^bb5(%m1 : index), ^bb6 {handshake.name = "cond_br4"}
^bb6:
  return {handshake.name = "return0"}
}

// -----

// Three regions, and a value of the entry (k) that the first and the third
// read: the lowering threads it through every loop, and the third receives
// it through the second's exit, which received it through the first's.
// Followed back through both, it is the entry's; every loop reads it from
// there.
// CHECK-LABEL:   handshake.func @three_regions(
// CHECK:           %[[K:.*]] = addi %{{.*}}, %{{.*}} {handshake.bb = 0 : ui32, handshake.name = "k"}
// CHECK:           %[[BK:.*]] = br %[[K]] {handshake.bb = 0 : ui32
// CHECK:           mux %{{.*}} [%[[BK]], %{{.*}}] {handshake.bb = 1 : ui32
// CHECK:           mux %{{.*}} [%[[BK]], %{{.*}}] {handshake.bb = 2 : ui32
// CHECK:           mux %{{.*}} [%[[BK]], %{{.*}}] {handshake.bb = 3 : ui32
// CHECK:           join %{{.*}}, %{{.*}}, %{{.*}} {handshake.bb = 4 : ui32
// expected-remark @below {{parallel regions [1] [2] [3] between blocks 0 and 4}}
func.func @three_regions(%a: memref<8xi32>, %x1: memref<8xi32>, %x2: memref<8xi32>, %x3: memref<8xi32>, %n: i32) {
  %c0 = arith.constant {handshake.name = "c0"} 0 : index
  %k = arith.addi %n, %n {handshake.name = "k"} : i32
  cf.br ^bb1(%c0 : index) {handshake.name = "br0"}
^bb1(%i: index):
  %c1 = arith.constant {handshake.name = "c1"} 1 : index
  %c8 = arith.constant {handshake.name = "c8"} 8 : index
  %z = arith.constant {handshake.name = "z"} 0 : index
  %v = memref.load %a[%i] {handshake.mem_interface = #handshake.mem_interface<MC>, handshake.name = "load0"} : memref<8xi32>
  %vk = arith.addi %v, %k {handshake.name = "add_k0"} : i32
  memref.store %vk, %x1[%i] {handshake.mem_interface = #handshake.mem_interface<MC>, handshake.name = "store0"} : memref<8xi32>
  %i1 = arith.addi %i, %c1 {handshake.name = "inc_i"} : index
  %cond = arith.cmpi ult, %i1, %c8 {handshake.name = "cmp1"} : index
  cf.cond_br %cond, ^bb1(%i1 : index), ^bb2(%z : index) {handshake.name = "cond_br0"}
^bb2(%j: index):
  %c1_0 = arith.constant {handshake.name = "c1_0"} 1 : index
  %c8_0 = arith.constant {handshake.name = "c8_0"} 8 : index
  %z_0 = arith.constant {handshake.name = "z_0"} 0 : index
  %w = memref.load %a[%j] {handshake.mem_interface = #handshake.mem_interface<MC>, handshake.name = "load1"} : memref<8xi32>
  memref.store %w, %x2[%j] {handshake.mem_interface = #handshake.mem_interface<MC>, handshake.name = "store1"} : memref<8xi32>
  %j1 = arith.addi %j, %c1_0 {handshake.name = "inc_j"} : index
  %cond_0 = arith.cmpi ult, %j1, %c8_0 {handshake.name = "cmp2"} : index
  cf.cond_br %cond_0, ^bb2(%j1 : index), ^bb3(%z_0 : index) {handshake.name = "cond_br1"}
^bb3(%l: index):
  %c1_1 = arith.constant {handshake.name = "c1_1"} 1 : index
  %c8_1 = arith.constant {handshake.name = "c8_1"} 8 : index
  %u = memref.load %a[%l] {handshake.mem_interface = #handshake.mem_interface<MC>, handshake.name = "load2"} : memref<8xi32>
  %uk = arith.addi %u, %k {handshake.name = "add_k2"} : i32
  memref.store %uk, %x3[%l] {handshake.mem_interface = #handshake.mem_interface<MC>, handshake.name = "store2"} : memref<8xi32>
  %l1 = arith.addi %l, %c1_1 {handshake.name = "inc_l"} : index
  %cond_1 = arith.cmpi ult, %l1, %c8_1 {handshake.name = "cmp3"} : index
  cf.cond_br %cond_1, ^bb3(%l1 : index), ^bb4 {handshake.name = "cond_br2"}
^bb4:
  return {handshake.name = "return0"}
}
