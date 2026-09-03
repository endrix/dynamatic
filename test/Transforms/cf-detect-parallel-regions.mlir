// RUN: dynamatic-opt %s --cf-detect-parallel-regions --split-input-file --verify-diagnostics | FileCheck %s

// Two loops, one block each: the first sums a into x1, the second sums a into
// x2. They read one memory and write two others, through memory controllers,
// and share no value: the second loop's start is a constant the first loop's
// block holds, which the lowering re-makes.
// CHECK-LABEL:   func.func @independent(
// CHECK-SAME:      handshake.parallel_regions = [{entry = 0 : ui32, regions = {{\[}}[1], [2]], successor = 3 : ui32}]
// expected-remark @below {{parallel regions [1] [2] between blocks 0 and 3}}
func.func @independent(%a: memref<8xi32>, %x1: memref<8xi32>, %x2: memref<8xi32>) {
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
  %w = memref.load %a[%j] {handshake.mem_interface = #handshake.mem_interface<MC>, handshake.name = "load1"} : memref<8xi32>
  memref.store %w, %x2[%j] {handshake.mem_interface = #handshake.mem_interface<MC>, handshake.name = "store1"} : memref<8xi32>
  %j1 = arith.addi %j, %c1_0 {handshake.name = "inc_j"} : index
  %cond_0 = arith.cmpi ult, %j1, %c8_0 {handshake.name = "cmp2"} : index
  cf.cond_br %cond_0, ^bb2(%j1 : index), ^bb3 {handshake.name = "cond_br1"}
^bb3:
  return {handshake.name = "return0"}
}

// -----

// The second loop starts where the first ended: a live-out.
// CHECK-LABEL:   func.func @live_out(
// CHECK-NOT:       handshake.parallel_regions
func.func @live_out(%a: memref<8xi32>, %x1: memref<8xi32>, %x2: memref<8xi32>) {
  %c0 = arith.constant {handshake.name = "c0"} 0 : index
  cf.br ^bb1(%c0 : index) {handshake.name = "br0"}
^bb1(%i: index):
  %c1 = arith.constant {handshake.name = "c1"} 1 : index
  %c4 = arith.constant {handshake.name = "c4"} 4 : index
  %v = memref.load %a[%i] {handshake.mem_interface = #handshake.mem_interface<MC>, handshake.name = "load0"} : memref<8xi32>
  memref.store %v, %x1[%i] {handshake.mem_interface = #handshake.mem_interface<MC>, handshake.name = "store0"} : memref<8xi32>
  %i1 = arith.addi %i, %c1 {handshake.name = "inc_i"} : index
  %cond = arith.cmpi ult, %i1, %c4 {handshake.name = "cmp1"} : index
  cf.cond_br %cond, ^bb1(%i1 : index), ^bb2(%i1 : index) {handshake.name = "cond_br0"}
^bb2(%j: index):
  %c1_0 = arith.constant {handshake.name = "c1_0"} 1 : index
  %c8_0 = arith.constant {handshake.name = "c8_0"} 8 : index
  %w = memref.load %a[%j] {handshake.mem_interface = #handshake.mem_interface<MC>, handshake.name = "load1"} : memref<8xi32>
  memref.store %w, %x2[%j] {handshake.mem_interface = #handshake.mem_interface<MC>, handshake.name = "store1"} : memref<8xi32>
  %j1 = arith.addi %j, %c1_0 {handshake.name = "inc_j"} : index
  %cond_0 = arith.cmpi ult, %j1, %c8_0 {handshake.name = "cmp2"} : index
  cf.cond_br %cond_0, ^bb2(%j1 : index), ^bb3 {handshake.name = "cond_br1"}
^bb3:
  return {handshake.name = "return0"}
}

// -----

// The second loop reads what the first wrote, and the analysis said so.
// CHECK-LABEL:   func.func @dependence(
// CHECK-NOT:       handshake.parallel_regions
func.func @dependence(%a: memref<8xi32>, %x1: memref<8xi32>, %x2: memref<8xi32>) {
  %c0 = arith.constant {handshake.name = "c0"} 0 : index
  cf.br ^bb1(%c0 : index) {handshake.name = "br0"}
^bb1(%i: index):
  %c1 = arith.constant {handshake.name = "c1"} 1 : index
  %c8 = arith.constant {handshake.name = "c8"} 8 : index
  %z = arith.constant {handshake.name = "z"} 0 : index
  %v = memref.load %a[%i] {handshake.mem_interface = #handshake.mem_interface<MC>, handshake.name = "load0"} : memref<8xi32>
  memref.store %v, %x1[%i] {handshake.deps = #handshake<deps[{dstAccess : "load1", loopDepth : 0, distance : 0, isActive : true}]>, handshake.mem_interface = #handshake.mem_interface<LSQ: 0>, handshake.name = "store0"} : memref<8xi32>
  %i1 = arith.addi %i, %c1 {handshake.name = "inc_i"} : index
  %cond = arith.cmpi ult, %i1, %c8 {handshake.name = "cmp1"} : index
  cf.cond_br %cond, ^bb1(%i1 : index), ^bb2(%z : index) {handshake.name = "cond_br0"}
^bb2(%j: index):
  %c1_0 = arith.constant {handshake.name = "c1_0"} 1 : index
  %c8_0 = arith.constant {handshake.name = "c8_0"} 8 : index
  %w = memref.load %x1[%j] {handshake.mem_interface = #handshake.mem_interface<LSQ: 1>, handshake.name = "load1"} : memref<8xi32>
  memref.store %w, %x2[%j] {handshake.mem_interface = #handshake.mem_interface<MC>, handshake.name = "store1"} : memref<8xi32>
  %j1 = arith.addi %j, %c1_0 {handshake.name = "inc_j"} : index
  %cond_0 = arith.cmpi ult, %j1, %c8_0 {handshake.name = "cmp2"} : index
  cf.cond_br %cond_0, ^bb2(%j1 : index), ^bb3 {handshake.name = "cond_br1"}
^bb3:
  return {handshake.name = "return0"}
}

// -----

// Both loops write x1 with no dependence recorded between them (disjoint
// halves), every access on a memory controller: they may interleave, the way
// the controller already lets them.
// CHECK-LABEL:   func.func @shared_memory_on_mc(
// CHECK-SAME:      handshake.parallel_regions = [{entry = 0 : ui32, regions = {{\[}}[1], [2]], successor = 3 : ui32}]
// expected-remark @below {{parallel regions [1] [2] between blocks 0 and 3}}
func.func @shared_memory_on_mc(%a: memref<8xi32>, %x1: memref<8xi32>) {
  %c0 = arith.constant {handshake.name = "c0"} 0 : index
  cf.br ^bb1(%c0 : index) {handshake.name = "br0"}
^bb1(%i: index):
  %c1 = arith.constant {handshake.name = "c1"} 1 : index
  %c4 = arith.constant {handshake.name = "c4"} 4 : index
  %v = memref.load %a[%i] {handshake.mem_interface = #handshake.mem_interface<MC>, handshake.name = "load0"} : memref<8xi32>
  memref.store %v, %x1[%i] {handshake.mem_interface = #handshake.mem_interface<MC>, handshake.name = "store0"} : memref<8xi32>
  %i1 = arith.addi %i, %c1 {handshake.name = "inc_i"} : index
  %cond = arith.cmpi ult, %i1, %c4 {handshake.name = "cmp1"} : index
  cf.cond_br %cond, ^bb1(%i1 : index), ^bb2(%c4 : index) {handshake.name = "cond_br0"}
^bb2(%j: index):
  %c1_0 = arith.constant {handshake.name = "c1_0"} 1 : index
  %c8_0 = arith.constant {handshake.name = "c8_0"} 8 : index
  %w = memref.load %a[%j] {handshake.mem_interface = #handshake.mem_interface<MC>, handshake.name = "load1"} : memref<8xi32>
  memref.store %w, %x1[%j] {handshake.mem_interface = #handshake.mem_interface<MC>, handshake.name = "store1"} : memref<8xi32>
  %j1 = arith.addi %j, %c1_0 {handshake.name = "inc_j"} : index
  %cond_0 = arith.cmpi ult, %j1, %c8_0 {handshake.name = "cmp2"} : index
  cf.cond_br %cond_0, ^bb2(%j1 : index), ^bb3 {handshake.name = "cond_br1"}
^bb3:
  return {handshake.name = "return0"}
}

// -----

// The same, but the second loop's stores go through an LSQ: two loops on one
// queue cannot interleave.
// CHECK-LABEL:   func.func @shared_memory_on_lsq(
// CHECK-NOT:       handshake.parallel_regions
func.func @shared_memory_on_lsq(%a: memref<8xi32>, %x1: memref<8xi32>) {
  %c0 = arith.constant {handshake.name = "c0"} 0 : index
  cf.br ^bb1(%c0 : index) {handshake.name = "br0"}
^bb1(%i: index):
  %c1 = arith.constant {handshake.name = "c1"} 1 : index
  %c4 = arith.constant {handshake.name = "c4"} 4 : index
  %v = memref.load %a[%i] {handshake.mem_interface = #handshake.mem_interface<MC>, handshake.name = "load0"} : memref<8xi32>
  memref.store %v, %x1[%i] {handshake.mem_interface = #handshake.mem_interface<MC>, handshake.name = "store0"} : memref<8xi32>
  %i1 = arith.addi %i, %c1 {handshake.name = "inc_i"} : index
  %cond = arith.cmpi ult, %i1, %c4 {handshake.name = "cmp1"} : index
  cf.cond_br %cond, ^bb1(%i1 : index), ^bb2(%c4 : index) {handshake.name = "cond_br0"}
^bb2(%j: index):
  %c1_0 = arith.constant {handshake.name = "c1_0"} 1 : index
  %c8_0 = arith.constant {handshake.name = "c8_0"} 8 : index
  %w = memref.load %a[%j] {handshake.mem_interface = #handshake.mem_interface<MC>, handshake.name = "load1"} : memref<8xi32>
  memref.store %w, %x1[%j] {handshake.mem_interface = #handshake.mem_interface<LSQ: 0>, handshake.name = "store1"} : memref<8xi32>
  %j1 = arith.addi %j, %c1_0 {handshake.name = "inc_j"} : index
  %cond_0 = arith.cmpi ult, %j1, %c8_0 {handshake.name = "cmp2"} : index
  cf.cond_br %cond_0, ^bb2(%j1 : index), ^bb3 {handshake.name = "cond_br1"}
^bb3:
  return {handshake.name = "return0"}
}

// -----

// Three loops: the third depends on the first (it reads x1), so the run is
// the first two; the third stands alone.
// CHECK-LABEL:   func.func @three(
// CHECK-SAME:      handshake.parallel_regions = [{entry = 0 : ui32, regions = {{\[}}[1], [2]], successor = 3 : ui32}]
// expected-remark @below {{parallel regions [1] [2] between blocks 0 and 3}}
func.func @three(%a: memref<8xi32>, %x1: memref<8xi32>, %x2: memref<8xi32>, %x3: memref<8xi32>) {
  %c0 = arith.constant {handshake.name = "c0"} 0 : index
  cf.br ^bb1(%c0 : index) {handshake.name = "br0"}
^bb1(%i: index):
  %c1 = arith.constant {handshake.name = "c1"} 1 : index
  %c8 = arith.constant {handshake.name = "c8"} 8 : index
  %z = arith.constant {handshake.name = "z"} 0 : index
  %v = memref.load %a[%i] {handshake.mem_interface = #handshake.mem_interface<MC>, handshake.name = "load0"} : memref<8xi32>
  memref.store %v, %x1[%i] {handshake.deps = #handshake<deps[{dstAccess : "load2", loopDepth : 0, distance : 0, isActive : true}]>, handshake.mem_interface = #handshake.mem_interface<LSQ: 0>, handshake.name = "store0"} : memref<8xi32>
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
  %u = memref.load %x1[%k] {handshake.mem_interface = #handshake.mem_interface<LSQ: 1>, handshake.name = "load2"} : memref<8xi32>
  memref.store %u, %x3[%k] {handshake.mem_interface = #handshake.mem_interface<MC>, handshake.name = "store2"} : memref<8xi32>
  %k1 = arith.addi %k, %c1_1 {handshake.name = "inc_k"} : index
  %cond_1 = arith.cmpi ult, %k1, %c8_1 {handshake.name = "cmp3"} : index
  cf.cond_br %cond_1, ^bb3(%k1 : index), ^bb4 {handshake.name = "cond_br2"}
^bb4:
  return {handshake.name = "return0"}
}

// -----

// One block, no loops: nothing to find, and nothing to trip over.
// CHECK-LABEL:   func.func @one_block(
// CHECK-NOT:       handshake.parallel_regions
func.func @one_block(%a: memref<1xi32>) -> i32 {
  %c0 = arith.constant {handshake.name = "c0"} 0 : index
  %v = memref.load %a[%c0] {handshake.mem_interface = #handshake.mem_interface<MC>, handshake.name = "load0"} : memref<1xi32>
  return {handshake.name = "return0"} %v : i32
}
