// RUN: dynamatic-opt %s --handshake-parallelize-regions --split-input-file --verify-diagnostics | FileCheck %s

// Two loops of one block each, run one after the other: block 1's exit branch
// hands the control to block 2's merge. With the attribute the entry's control
// feeds both merges and the two exit tokens meet in a join before block 3. The
// constant block 1 made for block 2's first iteration is re-made in the entry;
// the value the entry sent through block 1 into block 2 comes from the entry
// directly. The archs lose 1->2 and gain 0->2 and 1->3.

// CHECK-LABEL:   handshake.func @two_loops(
// CHECK-SAME:      handshake.frequencies = {{\[}}[0, 1, 1, 0], [1, 1, 9, 1], [2, 2, 9, 1], [2, 3, 1, 0], [0, 2, 1, 0], [1, 3, 1, 0]]
// CHECK:           %[[ZERO:.*]] = constant %arg1 {handshake.bb = 0 : ui32, {{.*}}value = 0 : i32}
// CHECK:           %[[K:.*]] = br %arg0 {handshake.bb = 0 : ui32, handshake.name = "br_k"}
// CHECK:           %[[CTRL:.*]] = br %arg1 {handshake.bb = 0 : ui32, handshake.name = "br_ctrl"}
// CHECK:           control_merge [%[[CTRL]], %{{.*}}] {handshake.bb = 1 : ui32, handshake.name = "merge1"}
// CHECK:           %{{.*}}, %[[EXIT1:.*]] = cond_br %{{.*}}, %{{.*}} {handshake.bb = 1 : ui32, handshake.name = "exit1"}
// CHECK:           control_merge [%[[CTRL]], %{{.*}}] {handshake.bb = 2 : ui32, handshake.name = "merge2"}
// CHECK:           mux %{{.*}} [%[[ZERO]], %{{.*}}] {handshake.bb = 2 : ui32, handshake.name = "mux_j"}
// CHECK:           mux %{{.*}} [%[[K]], %{{.*}}] {handshake.bb = 2 : ui32, handshake.name = "mux_k2"}
// CHECK:           %{{.*}}, %[[EXIT2:.*]] = cond_br %{{.*}}, %{{.*}} {handshake.bb = 2 : ui32, handshake.name = "exit2"}
// CHECK:           %[[JOIN:.*]] = join %[[EXIT1]], %[[EXIT2]] {handshake.bb = 3 : ui32
// CHECK:           control_merge [%[[JOIN]]] {handshake.bb = 3 : ui32, handshake.name = "merge3"}
handshake.func @two_loops(%arg0: !handshake.channel<i32>, %arg1: !handshake.control<>, ...) -> !handshake.control<> attributes {argNames = ["k", "start"], resNames = ["end"], handshake.parallel_regions = [{entry = 0 : ui32, regions = [[1], [2]], successor = 3 : ui32}], handshake.frequencies = [[0, 1, 1, 0], [1, 1, 9, 1], [1, 2, 1, 0], [2, 2, 9, 1], [2, 3, 1, 0]]} {
  %0 = constant %arg1 {handshake.bb = 0 : ui32, handshake.name = "five", value = 5 : i32} : <>, <i32>
  %1 = br %0 {handshake.bb = 0 : ui32, handshake.name = "br_five"} : <i32>
  %2 = br %arg0 {handshake.bb = 0 : ui32, handshake.name = "br_k"} : <i32>
  %3 = br %arg1 {handshake.bb = 0 : ui32, handshake.name = "br_ctrl"} : <>
  %result, %index = control_merge [%3, %trueResult_2]  {handshake.bb = 1 : ui32, handshake.name = "merge1"} : [<>, <>] to <>, <i1>
  %4 = mux %index [%1, %trueResult] {handshake.bb = 1 : ui32, handshake.name = "mux_i"} : <i1>, [<i32>, <i32>] to <i32>
  %5 = mux %index [%2, %trueResult_0] {handshake.bb = 1 : ui32, handshake.name = "mux_k1"} : <i1>, [<i32>, <i32>] to <i32>
  %6 = constant %result {handshake.bb = 1 : ui32, handshake.name = "one", value = 1 : i32} : <>, <i32>
  %7 = addi %4, %6 {handshake.bb = 1 : ui32, handshake.name = "inc_i"} : <i32>
  %8 = constant %result {handshake.bb = 1 : ui32, handshake.name = "ten1", value = 10 : i32} : <>, <i32>
  %9 = cmpi ult, %7, %8 {handshake.bb = 1 : ui32, handshake.name = "cmp1"} : <i32>
  %trueResult, %falseResult = cond_br %9, %7 {handshake.bb = 1 : ui32, handshake.name = "loop_i"} : <i1>, <i32>
  %trueResult_0, %falseResult_1 = cond_br %9, %5 {handshake.bb = 1 : ui32, handshake.name = "loop_k1"} : <i1>, <i32>
  %trueResult_2, %falseResult_3 = cond_br %9, %result {handshake.bb = 1 : ui32, handshake.name = "exit1"} : <i1>, <>
  %10 = constant %result {handshake.bb = 1 : ui32, handshake.name = "zero_for_j", value = 0 : i32} : <>, <i32>
  %trueResult_4, %falseResult_5 = cond_br %9, %10 {handshake.bb = 1 : ui32, handshake.name = "loop_zero"} : <i1>, <i32>
  %result_6, %index_7 = control_merge [%falseResult_3, %trueResult_10]  {handshake.bb = 2 : ui32, handshake.name = "merge2"} : [<>, <>] to <>, <i1>
  %11 = mux %index_7 [%falseResult_5, %trueResult_8] {handshake.bb = 2 : ui32, handshake.name = "mux_j"} : <i1>, [<i32>, <i32>] to <i32>
  %12 = mux %index_7 [%falseResult_1, %trueResult_9] {handshake.bb = 2 : ui32, handshake.name = "mux_k2"} : <i1>, [<i32>, <i32>] to <i32>
  %13 = addi %11, %12 {handshake.bb = 2 : ui32, handshake.name = "inc_j"} : <i32>
  %14 = constant %result_6 {handshake.bb = 2 : ui32, handshake.name = "ten2", value = 10 : i32} : <>, <i32>
  %15 = cmpi ult, %13, %14 {handshake.bb = 2 : ui32, handshake.name = "cmp2"} : <i32>
  %trueResult_8, %falseResult_9 = cond_br %15, %13 {handshake.bb = 2 : ui32, handshake.name = "loop_j"} : <i1>, <i32>
  %trueResult_9, %falseResult_11 = cond_br %15, %12 {handshake.bb = 2 : ui32, handshake.name = "loop_k2"} : <i1>, <i32>
  %trueResult_10, %falseResult_12 = cond_br %15, %result_6 {handshake.bb = 2 : ui32, handshake.name = "exit2"} : <i1>, <>
  %result_13, %index_14 = control_merge [%falseResult_12]  {handshake.bb = 3 : ui32, handshake.name = "merge3"} : [<>] to <>, <i1>
  end {handshake.bb = 3 : ui32, handshake.name = "end0"} %result_13 : <>
}

// -----

// Block 2 uses the final value of block 1's induction variable: a live-out.
handshake.func @live_out(%arg0: !handshake.control<>, ...) -> !handshake.control<> attributes {argNames = ["start"], resNames = ["end"], handshake.parallel_regions = [{entry = 0 : ui32, regions = [[1], [2]], successor = 3 : ui32}]} {
  %0 = constant %arg0 {handshake.bb = 0 : ui32, handshake.name = "zero", value = 0 : i32} : <>, <i32>
  %1 = br %0 {handshake.bb = 0 : ui32, handshake.name = "br_zero"} : <i32>
  %2 = br %arg0 {handshake.bb = 0 : ui32, handshake.name = "br_ctrl"} : <>
  %result, %index = control_merge [%2, %trueResult_0]  {handshake.bb = 1 : ui32, handshake.name = "merge1"} : [<>, <>] to <>, <i1>
  %3 = mux %index [%1, %trueResult] {handshake.bb = 1 : ui32, handshake.name = "mux_i"} : <i1>, [<i32>, <i32>] to <i32>
  %4 = constant %result {handshake.bb = 1 : ui32, handshake.name = "one", value = 1 : i32} : <>, <i32>
  // expected-error @below {{region 0 computes this value and region 1 uses it}}
  %5 = addi %3, %4 {handshake.bb = 1 : ui32, handshake.name = "inc_i"} : <i32>
  %6 = constant %result {handshake.bb = 1 : ui32, handshake.name = "ten1", value = 10 : i32} : <>, <i32>
  %7 = cmpi ult, %5, %6 {handshake.bb = 1 : ui32, handshake.name = "cmp1"} : <i32>
  %trueResult, %falseResult = cond_br %7, %5 {handshake.bb = 1 : ui32, handshake.name = "loop_i"} : <i1>, <i32>
  %trueResult_0, %falseResult_1 = cond_br %7, %result {handshake.bb = 1 : ui32, handshake.name = "exit1"} : <i1>, <>
  %result_2, %index_3 = control_merge [%falseResult_1, %trueResult_5]  {handshake.bb = 2 : ui32, handshake.name = "merge2"} : [<>, <>] to <>, <i1>
  %8 = mux %index_3 [%falseResult, %trueResult_4] {handshake.bb = 2 : ui32, handshake.name = "mux_j"} : <i1>, [<i32>, <i32>] to <i32>
  %9 = constant %result_2 {handshake.bb = 2 : ui32, handshake.name = "one2", value = 1 : i32} : <>, <i32>
  %10 = addi %8, %9 {handshake.bb = 2 : ui32, handshake.name = "inc_j"} : <i32>
  %11 = constant %result_2 {handshake.bb = 2 : ui32, handshake.name = "twenty", value = 20 : i32} : <>, <i32>
  %12 = cmpi ult, %10, %11 {handshake.bb = 2 : ui32, handshake.name = "cmp2"} : <i32>
  %trueResult_4, %falseResult_6 = cond_br %12, %10 {handshake.bb = 2 : ui32, handshake.name = "loop_j"} : <i1>, <i32>
  %trueResult_5, %falseResult_7 = cond_br %12, %result_2 {handshake.bb = 2 : ui32, handshake.name = "exit2"} : <i1>, <>
  %result_8, %index_9 = control_merge [%falseResult_7]  {handshake.bb = 3 : ui32, handshake.name = "merge3"} : [<>] to <>, <i1>
  end {handshake.bb = 3 : ui32, handshake.name = "end0"} %result_8 : <>
}

// -----

// A load in block 1 depends on a store in block 2 (a WAR the analysis
// recorded), and both go through one LSQ. The dependence is found first.
handshake.func @dependence(%arg0: memref<8xi32>, %arg1: !handshake.control<>, %arg2: !handshake.control<>, ...) -> (!handshake.control<>, !handshake.control<>) attributes {argNames = ["a", "a_start", "start"], resNames = ["a_end", "end"], handshake.parallel_regions = [{entry = 0 : ui32, regions = [[1], [2]], successor = 3 : ui32}]} {
  %0:2 = lsq[%arg0 : memref<8xi32>] (%arg1, %result, %addressResult, %result_2, %addressResult_4, %dataResult_5, %arg2)  {groupSizes = [1 : i32, 1 : i32], handshake.name = "lsq0"} : (!handshake.control<>, !handshake.control<>, !handshake.channel<i32>, !handshake.control<>, !handshake.channel<i32>, !handshake.channel<i32>, !handshake.control<>) -> (!handshake.channel<i32>, !handshake.control<>)
  %1 = constant %arg2 {handshake.bb = 0 : ui32, handshake.name = "zero", value = 0 : i32} : <>, <i32>
  %2 = br %1 {handshake.bb = 0 : ui32, handshake.name = "br_zero"} : <i32>
  %3 = br %arg2 {handshake.bb = 0 : ui32, handshake.name = "br_ctrl"} : <>
  %result, %index = control_merge [%3, %trueResult_0]  {handshake.bb = 1 : ui32, handshake.name = "merge1"} : [<>, <>] to <>, <i1>
  %4 = mux %index [%2, %trueResult] {handshake.bb = 1 : ui32, handshake.name = "mux_i"} : <i1>, [<i32>, <i32>] to <i32>
  // expected-error @below {{a memory dependence with 'store0' crosses from region 0 to region 1}}
  %addressResult, %dataResult = load[%4] %0#0 {handshake.bb = 1 : ui32, handshake.deps = #handshake<deps[{dstAccess : "store0", loopDepth : 0, distance : 0, isActive : true}]>, handshake.name = "load0"} : <i32>, <i32>, <i32>, <i32>
  %5 = constant %result {handshake.bb = 1 : ui32, handshake.name = "one", value = 1 : i32} : <>, <i32>
  %6 = addi %4, %5 {handshake.bb = 1 : ui32, handshake.name = "inc_i"} : <i32>
  %7 = constant %result {handshake.bb = 1 : ui32, handshake.name = "eight", value = 8 : i32} : <>, <i32>
  %8 = cmpi ult, %6, %7 {handshake.bb = 1 : ui32, handshake.name = "cmp1"} : <i32>
  %trueResult, %falseResult = cond_br %8, %6 {handshake.bb = 1 : ui32, handshake.name = "loop_i"} : <i1>, <i32>
  %trueResult_0, %falseResult_1 = cond_br %8, %result {handshake.bb = 1 : ui32, handshake.name = "exit1"} : <i1>, <>
  %9 = constant %result {handshake.bb = 1 : ui32, handshake.name = "zero_for_j", value = 0 : i32} : <>, <i32>
  %trueResult_6, %falseResult_7 = cond_br %8, %9 {handshake.bb = 1 : ui32, handshake.name = "loop_zero"} : <i1>, <i32>
  %result_2, %index_3 = control_merge [%falseResult_1, %trueResult_10]  {handshake.bb = 2 : ui32, handshake.name = "merge2"} : [<>, <>] to <>, <i1>
  %10 = mux %index_3 [%falseResult_7, %trueResult_8] {handshake.bb = 2 : ui32, handshake.name = "mux_j"} : <i1>, [<i32>, <i32>] to <i32>
  %addressResult_4, %dataResult_5 = store[%10] %10 {handshake.bb = 2 : ui32, handshake.name = "store0"} : <i32>, <i32>, <i32>, <i32>
  %11 = constant %result_2 {handshake.bb = 2 : ui32, handshake.name = "one2", value = 1 : i32} : <>, <i32>
  %12 = addi %10, %11 {handshake.bb = 2 : ui32, handshake.name = "inc_j"} : <i32>
  %13 = constant %result_2 {handshake.bb = 2 : ui32, handshake.name = "eight2", value = 8 : i32} : <>, <i32>
  %14 = cmpi ult, %12, %13 {handshake.bb = 2 : ui32, handshake.name = "cmp2"} : <i32>
  %trueResult_8, %falseResult_9 = cond_br %14, %12 {handshake.bb = 2 : ui32, handshake.name = "loop_j"} : <i1>, <i32>
  %trueResult_10, %falseResult_11 = cond_br %14, %result_2 {handshake.bb = 2 : ui32, handshake.name = "exit2"} : <i1>, <>
  %result_12, %index_13 = control_merge [%falseResult_11]  {handshake.bb = 3 : ui32, handshake.name = "merge3"} : [<>] to <>, <i1>
  end {handshake.bb = 3 : ui32, handshake.name = "end0"} %0#1, %result_12 : <>, <>
}

// -----

// The same two loops on one LSQ, without a recorded dependence.
handshake.func @shared_lsq(%arg0: memref<8xi32>, %arg1: !handshake.control<>, %arg2: !handshake.control<>, ...) -> (!handshake.control<>, !handshake.control<>) attributes {argNames = ["a", "a_start", "start"], resNames = ["a_end", "end"], handshake.parallel_regions = [{entry = 0 : ui32, regions = [[1], [2]], successor = 3 : ui32}]} {
  // expected-error @below {{this LSQ serves both region 0 and region 1}}
  %0:2 = lsq[%arg0 : memref<8xi32>] (%arg1, %result, %addressResult, %result_2, %addressResult_4, %dataResult_5, %arg2)  {groupSizes = [1 : i32, 1 : i32], handshake.name = "lsq0"} : (!handshake.control<>, !handshake.control<>, !handshake.channel<i32>, !handshake.control<>, !handshake.channel<i32>, !handshake.channel<i32>, !handshake.control<>) -> (!handshake.channel<i32>, !handshake.control<>)
  %1 = constant %arg2 {handshake.bb = 0 : ui32, handshake.name = "zero", value = 0 : i32} : <>, <i32>
  %2 = br %1 {handshake.bb = 0 : ui32, handshake.name = "br_zero"} : <i32>
  %3 = br %arg2 {handshake.bb = 0 : ui32, handshake.name = "br_ctrl"} : <>
  %result, %index = control_merge [%3, %trueResult_0]  {handshake.bb = 1 : ui32, handshake.name = "merge1"} : [<>, <>] to <>, <i1>
  %4 = mux %index [%2, %trueResult] {handshake.bb = 1 : ui32, handshake.name = "mux_i"} : <i1>, [<i32>, <i32>] to <i32>
  %addressResult, %dataResult = load[%4] %0#0 {handshake.bb = 1 : ui32, handshake.name = "load0"} : <i32>, <i32>, <i32>, <i32>
  %5 = constant %result {handshake.bb = 1 : ui32, handshake.name = "one", value = 1 : i32} : <>, <i32>
  %6 = addi %4, %5 {handshake.bb = 1 : ui32, handshake.name = "inc_i"} : <i32>
  %7 = constant %result {handshake.bb = 1 : ui32, handshake.name = "eight", value = 8 : i32} : <>, <i32>
  %8 = cmpi ult, %6, %7 {handshake.bb = 1 : ui32, handshake.name = "cmp1"} : <i32>
  %trueResult, %falseResult = cond_br %8, %6 {handshake.bb = 1 : ui32, handshake.name = "loop_i"} : <i1>, <i32>
  %trueResult_0, %falseResult_1 = cond_br %8, %result {handshake.bb = 1 : ui32, handshake.name = "exit1"} : <i1>, <>
  %9 = constant %result {handshake.bb = 1 : ui32, handshake.name = "zero_for_j", value = 0 : i32} : <>, <i32>
  %trueResult_6, %falseResult_7 = cond_br %8, %9 {handshake.bb = 1 : ui32, handshake.name = "loop_zero"} : <i1>, <i32>
  %result_2, %index_3 = control_merge [%falseResult_1, %trueResult_10]  {handshake.bb = 2 : ui32, handshake.name = "merge2"} : [<>, <>] to <>, <i1>
  %10 = mux %index_3 [%falseResult_7, %trueResult_8] {handshake.bb = 2 : ui32, handshake.name = "mux_j"} : <i1>, [<i32>, <i32>] to <i32>
  %addressResult_4, %dataResult_5 = store[%10] %10 {handshake.bb = 2 : ui32, handshake.name = "store0"} : <i32>, <i32>, <i32>, <i32>
  %11 = constant %result_2 {handshake.bb = 2 : ui32, handshake.name = "one2", value = 1 : i32} : <>, <i32>
  %12 = addi %10, %11 {handshake.bb = 2 : ui32, handshake.name = "inc_j"} : <i32>
  %13 = constant %result_2 {handshake.bb = 2 : ui32, handshake.name = "eight2", value = 8 : i32} : <>, <i32>
  %14 = cmpi ult, %12, %13 {handshake.bb = 2 : ui32, handshake.name = "cmp2"} : <i32>
  %trueResult_8, %falseResult_9 = cond_br %14, %12 {handshake.bb = 2 : ui32, handshake.name = "loop_j"} : <i1>, <i32>
  %trueResult_10, %falseResult_11 = cond_br %14, %result_2 {handshake.bb = 2 : ui32, handshake.name = "exit2"} : <i1>, <>
  %result_12, %index_13 = control_merge [%falseResult_11]  {handshake.bb = 3 : ui32, handshake.name = "merge3"} : [<>] to <>, <i1>
  end {handshake.bb = 3 : ui32, handshake.name = "end0"} %0#1, %result_12 : <>, <>
}
