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
// halves), every access on a memory controller that `mark-memory-interfaces`
// chose from the recorded dependences: they may interleave, the way the
// controller already lets them.
// CHECK-LABEL:   func.func @shared_memory_on_mc(
// CHECK-SAME:      handshake.mem_interfaces_from_deps
// CHECK-SAME:      handshake.parallel_regions = [{entry = 0 : ui32, regions = {{\[}}[1], [2]], successor = 3 : ui32}]
// expected-remark @below {{parallel regions [1] [2] between blocks 0 and 3}}
func.func @shared_memory_on_mc(%a: memref<8xi32>, %x1: memref<8xi32>) attributes {handshake.mem_interfaces_from_deps} {
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

// The same interfaces, forced rather than chosen from dependences (nothing
// says the halves are disjoint): the memory keeps the loops in order.
// CHECK-LABEL:   func.func @shared_memory_forced_on_mc(
// CHECK-NOT:       handshake.parallel_regions
func.func @shared_memory_forced_on_mc(%a: memref<8xi32>, %x1: memref<8xi32>) {
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

// -----

// scf-to-cf leaves a block of constants between two loops. It is a straight
// line with nothing that touches memory, so the second region absorbs it:
// regions [1] and [2, 3], between blocks 0 and 4. The value the first loop
// hands to its exit block goes to an argument nothing reads.
// CHECK-LABEL:   func.func @constants_between(
// CHECK-SAME:      handshake.parallel_regions = [{entry = 0 : ui32, regions = {{\[}}[1], [2, 3]], successor = 4 : ui32}]
// expected-remark @below {{parallel regions [1] [2, 3] between blocks 0 and 4}}
func.func @constants_between(%a: memref<8xi32>, %x1: memref<8xi32>, %x2: memref<8xi32>) {
  %c0 = arith.constant {handshake.name = "c0"} 0 : index
  %c1 = arith.constant {handshake.name = "c1"} 1 : index
  %c8 = arith.constant {handshake.name = "c8"} 8 : index
  cf.br ^bb1(%c0 : index) {handshake.name = "br0"}
^bb1(%i: index):
  %v = memref.load %a[%i] {handshake.mem_interface = #handshake.mem_interface<MC>, handshake.name = "load0"} : memref<8xi32>
  memref.store %v, %x1[%i] {handshake.mem_interface = #handshake.mem_interface<MC>, handshake.name = "store0"} : memref<8xi32>
  %i1 = arith.addi %i, %c1 {handshake.name = "inc_i"} : index
  %cond = arith.cmpi ult, %i1, %c8 {handshake.name = "cmp1"} : index
  cf.cond_br %cond, ^bb1(%i1 : index), ^bb2(%i1 : index) {handshake.name = "cond_br0"}
^bb2(%unused: index):
  %z = arith.constant {handshake.name = "z"} 0 : index
  %c8_0 = arith.constant {handshake.name = "c8_0"} 8 : index
  cf.br ^bb3(%z : index) {handshake.name = "br1"}
^bb3(%j: index):
  %w = memref.load %a[%j] {handshake.mem_interface = #handshake.mem_interface<MC>, handshake.name = "load1"} : memref<8xi32>
  memref.store %w, %x2[%j] {handshake.mem_interface = #handshake.mem_interface<MC>, handshake.name = "store1"} : memref<8xi32>
  %j1 = arith.addi %j, %c1 {handshake.name = "inc_j"} : index
  %cond_0 = arith.cmpi ult, %j1, %c8_0 {handshake.name = "cmp2"} : index
  cf.cond_br %cond_0, ^bb3(%j1 : index), ^bb4 {handshake.name = "cond_br1"}
^bb4:
  return {handshake.name = "return0"}
}

// -----

// The first loop sums a, the second copies a to x2, and the return reads the
// sum. The second loop does not read it, but the lowering threads the sum
// through its blocks to the return, and only the last region may hand a
// value to what comes after the group: the first loop merges with the
// second, and there is no group.
// CHECK-LABEL:   func.func @read_after_the_group(
// CHECK-NOT:       handshake.parallel_regions
func.func @read_after_the_group(%a: memref<8xi32>, %x2: memref<8xi32>) -> i32 {
  %c0 = arith.constant {handshake.name = "c0"} 0 : index
  %s0 = arith.constant {handshake.name = "s0"} 0 : i32
  cf.br ^bb1(%c0, %s0 : index, i32) {handshake.name = "br0"}
^bb1(%i: index, %s: i32):
  %c1 = arith.constant {handshake.name = "c1"} 1 : index
  %c8 = arith.constant {handshake.name = "c8"} 8 : index
  %z = arith.constant {handshake.name = "z"} 0 : index
  %v = memref.load %a[%i] {handshake.mem_interface = #handshake.mem_interface<MC>, handshake.name = "load0"} : memref<8xi32>
  %s1 = arith.addi %s, %v {handshake.name = "acc"} : i32
  %i1 = arith.addi %i, %c1 {handshake.name = "inc_i"} : index
  %cond = arith.cmpi ult, %i1, %c8 {handshake.name = "cmp1"} : index
  cf.cond_br %cond, ^bb1(%i1, %s1 : index, i32), ^bb2(%z : index) {handshake.name = "cond_br0"}
^bb2(%j: index):
  %c1_0 = arith.constant {handshake.name = "c1_0"} 1 : index
  %c8_0 = arith.constant {handshake.name = "c8_0"} 8 : index
  %w = memref.load %a[%j] {handshake.mem_interface = #handshake.mem_interface<MC>, handshake.name = "load1"} : memref<8xi32>
  memref.store %w, %x2[%j] {handshake.mem_interface = #handshake.mem_interface<MC>, handshake.name = "store1"} : memref<8xi32>
  %j1 = arith.addi %j, %c1_0 {handshake.name = "inc_j"} : index
  %cond_0 = arith.cmpi ult, %j1, %c8_0 {handshake.name = "cmp2"} : index
  cf.cond_br %cond_0, ^bb2(%j1 : index), ^bb3 {handshake.name = "cond_br1"}
^bb3:
  return {handshake.name = "return0"} %s1 : i32
}

// -----

// The same two loops, and a third that adds the sum to every word of a into
// x3. The third loop reads a value of the first, a region other than the
// last of [1] [2]: the first merges with the second, and the run is the
// second and the third, after the first.
// CHECK-LABEL:   func.func @read_by_a_later_unit(
// CHECK-SAME:      handshake.parallel_regions = [{entry = 1 : ui32, regions = {{\[}}[2], [3]], successor = 4 : ui32}]
// expected-remark @below {{parallel regions [2] [3] between blocks 1 and 4}}
func.func @read_by_a_later_unit(%a: memref<8xi32>, %x2: memref<8xi32>, %x3: memref<8xi32>) {
  %c0 = arith.constant {handshake.name = "c0"} 0 : index
  %s0 = arith.constant {handshake.name = "s0"} 0 : i32
  cf.br ^bb1(%c0, %s0 : index, i32) {handshake.name = "br0"}
^bb1(%i: index, %s: i32):
  %c1 = arith.constant {handshake.name = "c1"} 1 : index
  %c8 = arith.constant {handshake.name = "c8"} 8 : index
  %z = arith.constant {handshake.name = "z"} 0 : index
  %v = memref.load %a[%i] {handshake.mem_interface = #handshake.mem_interface<MC>, handshake.name = "load0"} : memref<8xi32>
  %s1 = arith.addi %s, %v {handshake.name = "acc"} : i32
  %i1 = arith.addi %i, %c1 {handshake.name = "inc_i"} : index
  %cond = arith.cmpi ult, %i1, %c8 {handshake.name = "cmp1"} : index
  cf.cond_br %cond, ^bb1(%i1, %s1 : index, i32), ^bb2(%z : index) {handshake.name = "cond_br0"}
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
  %u = memref.load %a[%k] {handshake.mem_interface = #handshake.mem_interface<MC>, handshake.name = "load2"} : memref<8xi32>
  %us = arith.addi %u, %s1 {handshake.name = "add_s"} : i32
  memref.store %us, %x3[%k] {handshake.mem_interface = #handshake.mem_interface<MC>, handshake.name = "store2"} : memref<8xi32>
  %k1 = arith.addi %k, %c1_1 {handshake.name = "inc_k"} : index
  %cond_1 = arith.cmpi ult, %k1, %c8_1 {handshake.name = "cmp3"} : index
  cf.cond_br %cond_1, ^bb3(%k1 : index), ^bb4 {handshake.name = "cond_br2"}
^bb4:
  return {handshake.name = "return0"}
}

// -----

// The first loop sets a flag on every iteration (its back edge hands the flag
// a constant 1, its entry a 0), and the second loop stores the flag. Both
// origins are constants, but which one the flag holds when the first loop
// leaves is the first loop's control flow's doing: a live-out.
// CHECK-LABEL:   func.func @reset_in_the_loop(
// CHECK-NOT:       handshake.parallel_regions
func.func @reset_in_the_loop(%a: memref<8xi32>, %x1: memref<8xi32>, %x2: memref<8xi32>) {
  %c0 = arith.constant {handshake.name = "c0"} 0 : index
  %f0 = arith.constant {handshake.name = "f0"} 0 : i32
  cf.br ^bb1(%c0, %f0 : index, i32) {handshake.name = "br0"}
^bb1(%i: index, %f: i32):
  %c1 = arith.constant {handshake.name = "c1"} 1 : index
  %c8 = arith.constant {handshake.name = "c8"} 8 : index
  %z = arith.constant {handshake.name = "z"} 0 : index
  %f1 = arith.constant {handshake.name = "f1"} 1 : i32
  %v = memref.load %a[%i] {handshake.mem_interface = #handshake.mem_interface<MC>, handshake.name = "load0"} : memref<8xi32>
  memref.store %v, %x1[%i] {handshake.mem_interface = #handshake.mem_interface<MC>, handshake.name = "store0"} : memref<8xi32>
  %i1 = arith.addi %i, %c1 {handshake.name = "inc_i"} : index
  %cond = arith.cmpi ult, %i1, %c8 {handshake.name = "cmp1"} : index
  cf.cond_br %cond, ^bb1(%i1, %f1 : index, i32), ^bb2(%z : index) {handshake.name = "cond_br0"}
^bb2(%j: index):
  %c1_0 = arith.constant {handshake.name = "c1_0"} 1 : index
  %c8_0 = arith.constant {handshake.name = "c8_0"} 8 : index
  memref.store %f, %x2[%j] {handshake.mem_interface = #handshake.mem_interface<MC>, handshake.name = "store1"} : memref<8xi32>
  %j1 = arith.addi %j, %c1_0 {handshake.name = "inc_j"} : index
  %cond_0 = arith.cmpi ult, %j1, %c8_0 {handshake.name = "cmp2"} : index
  cf.cond_br %cond_0, ^bb2(%j1 : index), ^bb3 {handshake.name = "cond_br1"}
^bb3:
  return {handshake.name = "return0"}
}

// -----

// The last region may hand a value on: the second loop sums a, the return
// reads the sum, and the first loop, which copies a to x1, runs beside it.
// CHECK-LABEL:   func.func @last_region_read_after(
// CHECK-SAME:      handshake.parallel_regions = [{entry = 0 : ui32, regions = {{\[}}[1], [2]], successor = 3 : ui32}]
// expected-remark @below {{parallel regions [1] [2] between blocks 0 and 3}}
func.func @last_region_read_after(%a: memref<8xi32>, %x1: memref<8xi32>) -> i32 {
  %c0 = arith.constant {handshake.name = "c0"} 0 : index
  cf.br ^bb1(%c0 : index) {handshake.name = "br0"}
^bb1(%i: index):
  %c1 = arith.constant {handshake.name = "c1"} 1 : index
  %c8 = arith.constant {handshake.name = "c8"} 8 : index
  %z = arith.constant {handshake.name = "z"} 0 : index
  %s0 = arith.constant {handshake.name = "s0"} 0 : i32
  %v = memref.load %a[%i] {handshake.mem_interface = #handshake.mem_interface<MC>, handshake.name = "load0"} : memref<8xi32>
  memref.store %v, %x1[%i] {handshake.mem_interface = #handshake.mem_interface<MC>, handshake.name = "store0"} : memref<8xi32>
  %i1 = arith.addi %i, %c1 {handshake.name = "inc_i"} : index
  %cond = arith.cmpi ult, %i1, %c8 {handshake.name = "cmp1"} : index
  cf.cond_br %cond, ^bb1(%i1 : index), ^bb2(%z, %s0 : index, i32) {handshake.name = "cond_br0"}
^bb2(%j: index, %s: i32):
  %c1_0 = arith.constant {handshake.name = "c1_0"} 1 : index
  %c8_0 = arith.constant {handshake.name = "c8_0"} 8 : index
  %w = memref.load %a[%j] {handshake.mem_interface = #handshake.mem_interface<MC>, handshake.name = "load1"} : memref<8xi32>
  %s1 = arith.addi %s, %w {handshake.name = "acc"} : i32
  %j1 = arith.addi %j, %c1_0 {handshake.name = "inc_j"} : index
  %cond_0 = arith.cmpi ult, %j1, %c8_0 {handshake.name = "cmp2"} : index
  cf.cond_br %cond_0, ^bb2(%j1, %s1 : index, i32), ^bb3 {handshake.name = "cond_br1"}
^bb3:
  return {handshake.name = "return0"} %s1 : i32
}

// -----

// The first loop sums a; the second carries the sum unchanged in an argument
// of its own (%c, which only copies itself) while it copies a to x2; the
// third reads %c. %c is the first loop's sum again, so the third loop reads
// a value of the first through the second, and the first cannot run beside
// either. The second and the third run side by side after it, the third
// reading the sum where the first loop leaves it.
// CHECK-LABEL:   func.func @carried_by_a_later_unit(
// CHECK-SAME:      handshake.parallel_regions = [{entry = 1 : ui32, regions = {{\[}}[2], [3]], successor = 4 : ui32}]
// expected-remark @below {{parallel regions [2] [3] between blocks 1 and 4}}
func.func @carried_by_a_later_unit(%a: memref<8xi32>, %x2: memref<8xi32>, %x3: memref<8xi32>) {
  %c0 = arith.constant {handshake.name = "c0"} 0 : index
  %s0 = arith.constant {handshake.name = "s0"} 0 : i32
  cf.br ^bb1(%c0, %s0 : index, i32) {handshake.name = "br0"}
^bb1(%i: index, %s: i32):
  %c1 = arith.constant {handshake.name = "c1"} 1 : index
  %c8 = arith.constant {handshake.name = "c8"} 8 : index
  %z = arith.constant {handshake.name = "z"} 0 : index
  %v = memref.load %a[%i] {handshake.mem_interface = #handshake.mem_interface<MC>, handshake.name = "load0"} : memref<8xi32>
  %s1 = arith.addi %s, %v {handshake.name = "acc"} : i32
  %i1 = arith.addi %i, %c1 {handshake.name = "inc_i"} : index
  %cond = arith.cmpi ult, %i1, %c8 {handshake.name = "cmp1"} : index
  cf.cond_br %cond, ^bb1(%i1, %s1 : index, i32), ^bb2(%z, %s1 : index, i32) {handshake.name = "cond_br0"}
^bb2(%j: index, %c: i32):
  %c1_0 = arith.constant {handshake.name = "c1_0"} 1 : index
  %c8_0 = arith.constant {handshake.name = "c8_0"} 8 : index
  %z_0 = arith.constant {handshake.name = "z_0"} 0 : index
  %w = memref.load %a[%j] {handshake.mem_interface = #handshake.mem_interface<MC>, handshake.name = "load1"} : memref<8xi32>
  memref.store %w, %x2[%j] {handshake.mem_interface = #handshake.mem_interface<MC>, handshake.name = "store1"} : memref<8xi32>
  %j1 = arith.addi %j, %c1_0 {handshake.name = "inc_j"} : index
  %cond_0 = arith.cmpi ult, %j1, %c8_0 {handshake.name = "cmp2"} : index
  cf.cond_br %cond_0, ^bb2(%j1, %c : index, i32), ^bb3(%z_0 : index) {handshake.name = "cond_br1"}
^bb3(%k: index):
  %c1_1 = arith.constant {handshake.name = "c1_1"} 1 : index
  %c8_1 = arith.constant {handshake.name = "c8_1"} 8 : index
  %u = memref.load %a[%k] {handshake.mem_interface = #handshake.mem_interface<MC>, handshake.name = "load2"} : memref<8xi32>
  %uc = arith.addi %u, %c {handshake.name = "add_c"} : i32
  memref.store %uc, %x3[%k] {handshake.mem_interface = #handshake.mem_interface<MC>, handshake.name = "store2"} : memref<8xi32>
  %k1 = arith.addi %k, %c1_1 {handshake.name = "inc_k"} : index
  %cond_1 = arith.cmpi ult, %k1, %c8_1 {handshake.name = "cmp3"} : index
  cf.cond_br %cond_1, ^bb3(%k1 : index), ^bb4 {handshake.name = "cond_br2"}
^bb4:
  return {handshake.name = "return0"}
}
