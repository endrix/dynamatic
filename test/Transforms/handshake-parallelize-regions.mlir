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

// -----

// A value from a block BEFORE the group: block 0 computes it and branches
// into the entry, block 1; region 3 reads it. It is a value of the firing
// like one from the entry -- computed once, forked to whichever regions read
// it (the parser copies a block into two arrays in one loop, then pushes
// each in its own) -- and the group lowers.
// CHECK-LABEL:   handshake.func @before_the_group(
// CHECK:           %[[K:.*]] = constant %arg0 {handshake.bb = 0 : ui32, handshake.name = "k", value = 7 : i32}
// CHECK:           %[[BK:.*]] = br %[[K]] {handshake.bb = 0 : ui32, handshake.name = "br_k"}
// CHECK:           control_merge [%{{.*}}, %{{.*}}] {handshake.bb = 2 : ui32, handshake.name = "merge2"}
// CHECK:           control_merge [%{{.*}}, %{{.*}}] {handshake.bb = 3 : ui32, handshake.name = "merge3"}
// CHECK:           addi %{{.*}}, %[[BK]] {handshake.bb = 3 : ui32, handshake.name = "use_k"}
// CHECK:           join %{{.*}}, %{{.*}} {handshake.bb = 4 : ui32
handshake.func @before_the_group(%arg0: !handshake.control<>, ...) -> !handshake.control<> attributes {argNames = ["start"], resNames = ["end"], handshake.parallel_regions = [{entry = 1 : ui32, regions = [[2], [3]], successor = 4 : ui32}]} {
  %k = constant %arg0 {handshake.bb = 0 : ui32, handshake.name = "k", value = 7 : i32} : <>, <i32>
  %bk = br %k {handshake.bb = 0 : ui32, handshake.name = "br_k"} : <i32>
  %c0 = br %arg0 {handshake.bb = 0 : ui32, handshake.name = "br_ctrl0"} : <>
  %e, %ei = control_merge [%c0]  {handshake.bb = 1 : ui32, handshake.name = "merge1"} : [<>] to <>, <i1>
  %zero = constant %e {handshake.bb = 1 : ui32, handshake.name = "zero", value = 0 : i32} : <>, <i32>
  %bz = br %zero {handshake.bb = 1 : ui32, handshake.name = "br_zero"} : <i32>
  %c1 = br %e {handshake.bb = 1 : ui32, handshake.name = "br_ctrl1"} : <>
  %result, %index = control_merge [%c1, %trueResult_2]  {handshake.bb = 2 : ui32, handshake.name = "merge2"} : [<>, <>] to <>, <i1>
  %4 = mux %index [%bz, %trueResult] {handshake.bb = 2 : ui32, handshake.name = "mux_i"} : <i1>, [<i32>, <i32>] to <i32>
  %6 = constant %result {handshake.bb = 2 : ui32, handshake.name = "one", value = 1 : i32} : <>, <i32>
  %7 = addi %4, %6 {handshake.bb = 2 : ui32, handshake.name = "inc_i"} : <i32>
  %8 = constant %result {handshake.bb = 2 : ui32, handshake.name = "ten1", value = 10 : i32} : <>, <i32>
  %9 = cmpi ult, %7, %8 {handshake.bb = 2 : ui32, handshake.name = "cmp1"} : <i32>
  %trueResult, %falseResult = cond_br %9, %7 {handshake.bb = 2 : ui32, handshake.name = "loop_i"} : <i1>, <i32>
  %trueResult_2, %falseResult_3 = cond_br %9, %result {handshake.bb = 2 : ui32, handshake.name = "exit1"} : <i1>, <>
  %10 = constant %result {handshake.bb = 2 : ui32, handshake.name = "zero_for_j", value = 0 : i32} : <>, <i32>
  %trueResult_4, %falseResult_5 = cond_br %9, %10 {handshake.bb = 2 : ui32, handshake.name = "loop_zero"} : <i1>, <i32>
  %result_6, %index_7 = control_merge [%falseResult_3, %trueResult_10]  {handshake.bb = 3 : ui32, handshake.name = "merge3"} : [<>, <>] to <>, <i1>
  %11 = mux %index_7 [%falseResult_5, %trueResult_8] {handshake.bb = 3 : ui32, handshake.name = "mux_j"} : <i1>, [<i32>, <i32>] to <i32>
  %13 = addi %11, %bk {handshake.bb = 3 : ui32, handshake.name = "use_k"} : <i32>
  %14 = constant %result_6 {handshake.bb = 3 : ui32, handshake.name = "ten2", value = 10 : i32} : <>, <i32>
  %15 = cmpi ult, %13, %14 {handshake.bb = 3 : ui32, handshake.name = "cmp2"} : <i32>
  %trueResult_8, %falseResult_9 = cond_br %15, %13 {handshake.bb = 3 : ui32, handshake.name = "loop_j"} : <i1>, <i32>
  %trueResult_10, %falseResult_12 = cond_br %15, %result_6 {handshake.bb = 3 : ui32, handshake.name = "exit2"} : <i1>, <>
  %result_13, %index_14 = control_merge [%falseResult_12]  {handshake.bb = 4 : ui32, handshake.name = "merge4"} : [<>] to <>, <i1>
  end {handshake.bb = 4 : ui32, handshake.name = "end0"} %result_13 : <>
}

// -----

// Block 1 sums its induction variable into mux_s, and block 3 reads the sum
// the loop leaves, which the lowering threads through block 2 (mux_s2).
// Followed back through block 1 the value reaches mux_s, whose loop-entry
// operand is the entry's zero; but mux_s's back edge brings the sum the loop
// computed (acc_s), not mux_s's own value, so what leaves block 1 is not
// that zero: a live-out.
handshake.func @updated_in_the_loop(%arg0: !handshake.control<>, ...) -> (!handshake.channel<i32>, !handshake.control<>) attributes {argNames = ["start"], resNames = ["sum", "end"], handshake.parallel_regions = [{entry = 0 : ui32, regions = [[1], [2]], successor = 3 : ui32}]} {
  %0 = constant %arg0 {handshake.bb = 0 : ui32, handshake.name = "zero", value = 0 : i32} : <>, <i32>
  %1 = br %0 {handshake.bb = 0 : ui32, handshake.name = "br_zero"} : <i32>
  %2 = br %0 {handshake.bb = 0 : ui32, handshake.name = "br_sum"} : <i32>
  %3 = br %arg0 {handshake.bb = 0 : ui32, handshake.name = "br_ctrl"} : <>
  %result, %index = control_merge [%3, %trueResult_0]  {handshake.bb = 1 : ui32, handshake.name = "merge1"} : [<>, <>] to <>, <i1>
  %4 = mux %index [%1, %trueResult] {handshake.bb = 1 : ui32, handshake.name = "mux_i"} : <i1>, [<i32>, <i32>] to <i32>
  // expected-error @below {{region 0's loop updates this value and region 1 uses it}}
  %5 = mux %index [%2, %trueResult_s] {handshake.bb = 1 : ui32, handshake.name = "mux_s"} : <i1>, [<i32>, <i32>] to <i32>
  %6 = constant %result {handshake.bb = 1 : ui32, handshake.name = "one", value = 1 : i32} : <>, <i32>
  %7 = addi %4, %6 {handshake.bb = 1 : ui32, handshake.name = "inc_i"} : <i32>
  %8 = addi %5, %4 {handshake.bb = 1 : ui32, handshake.name = "acc_s"} : <i32>
  %9 = constant %result {handshake.bb = 1 : ui32, handshake.name = "ten1", value = 10 : i32} : <>, <i32>
  %10 = cmpi ult, %7, %9 {handshake.bb = 1 : ui32, handshake.name = "cmp1"} : <i32>
  %trueResult, %falseResult = cond_br %10, %7 {handshake.bb = 1 : ui32, handshake.name = "loop_i"} : <i1>, <i32>
  %trueResult_s, %falseResult_s = cond_br %10, %8 {handshake.bb = 1 : ui32, handshake.name = "loop_s"} : <i1>, <i32>
  %trueResult_x, %falseResult_x = cond_br %10, %5 {handshake.bb = 1 : ui32, handshake.name = "exit_s"} : <i1>, <i32>
  %trueResult_0, %falseResult_1 = cond_br %10, %result {handshake.bb = 1 : ui32, handshake.name = "exit1"} : <i1>, <>
  %11 = constant %result {handshake.bb = 1 : ui32, handshake.name = "zero_for_j", value = 0 : i32} : <>, <i32>
  %trueResult_2, %falseResult_3 = cond_br %10, %11 {handshake.bb = 1 : ui32, handshake.name = "loop_zero"} : <i1>, <i32>
  %result_4, %index_5 = control_merge [%falseResult_1, %trueResult_8]  {handshake.bb = 2 : ui32, handshake.name = "merge2"} : [<>, <>] to <>, <i1>
  %12 = mux %index_5 [%falseResult_3, %trueResult_6] {handshake.bb = 2 : ui32, handshake.name = "mux_j"} : <i1>, [<i32>, <i32>] to <i32>
  %13 = mux %index_5 [%falseResult_x, %trueResult_s2] {handshake.bb = 2 : ui32, handshake.name = "mux_s2"} : <i1>, [<i32>, <i32>] to <i32>
  %14 = constant %result_4 {handshake.bb = 2 : ui32, handshake.name = "one2", value = 1 : i32} : <>, <i32>
  %15 = addi %12, %14 {handshake.bb = 2 : ui32, handshake.name = "inc_j"} : <i32>
  %16 = constant %result_4 {handshake.bb = 2 : ui32, handshake.name = "ten2", value = 10 : i32} : <>, <i32>
  %17 = cmpi ult, %15, %16 {handshake.bb = 2 : ui32, handshake.name = "cmp2"} : <i32>
  %trueResult_6, %falseResult_7 = cond_br %17, %15 {handshake.bb = 2 : ui32, handshake.name = "loop_j"} : <i1>, <i32>
  %trueResult_s2, %falseResult_s2 = cond_br %17, %13 {handshake.bb = 2 : ui32, handshake.name = "loop_s2"} : <i1>, <i32>
  %trueResult_8, %falseResult_9 = cond_br %17, %result_4 {handshake.bb = 2 : ui32, handshake.name = "exit2"} : <i1>, <>
  %result_10, %index_11 = control_merge [%falseResult_9]  {handshake.bb = 3 : ui32, handshake.name = "merge3"} : [<>] to <>, <i1>
  end {handshake.bb = 3 : ui32, handshake.name = "end0"} %falseResult_s2, %result_10 : <i32>, <>
}

// -----

// Region 0 is a loop nest, block 1 the outer loop and block 2 the inner one,
// and k comes from the entry through both into region 1. mux_k1's back edge
// (from block 2) leads to the inner loop's mux_k2, whose operands lead back
// to mux_k1 and to mux_k2 itself: k is carried unchanged, and region 1
// reads it from the entry.
// CHECK-LABEL:   handshake.func @carried_through_an_inner_loop(
// CHECK:           %[[K:.*]] = br %arg0 {handshake.bb = 0 : ui32, handshake.name = "br_k"}
// CHECK:           mux %{{.*}} [%[[K]], %{{.*}}] {handshake.bb = 3 : ui32, handshake.name = "mux_k3"}
// CHECK:           join %{{.*}}, %{{.*}} {handshake.bb = 4 : ui32
handshake.func @carried_through_an_inner_loop(%arg0: !handshake.channel<i32>, %arg1: !handshake.control<>, ...) -> (!handshake.channel<i32>, !handshake.control<>) attributes {argNames = ["k", "start"], resNames = ["out", "end"], handshake.parallel_regions = [{entry = 0 : ui32, regions = [[1, 2], [3]], successor = 4 : ui32}]} {
  %0 = constant %arg1 {handshake.bb = 0 : ui32, handshake.name = "zero", value = 0 : i32} : <>, <i32>
  %1 = br %0 {handshake.bb = 0 : ui32, handshake.name = "br_zero"} : <i32>
  %2 = br %arg0 {handshake.bb = 0 : ui32, handshake.name = "br_k"} : <i32>
  %3 = br %arg1 {handshake.bb = 0 : ui32, handshake.name = "br_ctrl"} : <>
  %c1, %ci1 = control_merge [%3, %f_ctrl2]  {handshake.bb = 1 : ui32, handshake.name = "merge1"} : [<>, <>] to <>, <i1>
  %i1 = mux %ci1 [%1, %f_i2] {handshake.bb = 1 : ui32, handshake.name = "mux_i1"} : <i1>, [<i32>, <i32>] to <i32>
  %k1 = mux %ci1 [%2, %f_k2] {handshake.bb = 1 : ui32, handshake.name = "mux_k1"} : <i1>, [<i32>, <i32>] to <i32>
  %four = constant %c1 {handshake.bb = 1 : ui32, handshake.name = "four", value = 4 : i32} : <>, <i32>
  %lt1 = cmpi ult, %i1, %four {handshake.bb = 1 : ui32, handshake.name = "cmp1"} : <i32>
  %t_ctrl1, %f_ctrl1 = cond_br %lt1, %c1 {handshake.bb = 1 : ui32, handshake.name = "exit1"} : <i1>, <>
  %t_i1, %f_i1 = cond_br %lt1, %i1 {handshake.bb = 1 : ui32, handshake.name = "to_inner_i"} : <i1>, <i32>
  %t_k1, %f_k1 = cond_br %lt1, %k1 {handshake.bb = 1 : ui32, handshake.name = "to_inner_k"} : <i1>, <i32>
  %zj = constant %c1 {handshake.bb = 1 : ui32, handshake.name = "zero_for_j", value = 0 : i32} : <>, <i32>
  %t_zj, %f_zj = cond_br %lt1, %zj {handshake.bb = 1 : ui32, handshake.name = "to_inner_j"} : <i1>, <i32>
  %zx = constant %c1 {handshake.bb = 1 : ui32, handshake.name = "zero_for_x", value = 0 : i32} : <>, <i32>
  %t_zx, %f_zx = cond_br %lt1, %zx {handshake.bb = 1 : ui32, handshake.name = "loop_zero"} : <i1>, <i32>
  %c2, %ci2 = control_merge [%t_ctrl1, %t_ctrl2]  {handshake.bb = 2 : ui32, handshake.name = "merge2"} : [<>, <>] to <>, <i1>
  %j2 = mux %ci2 [%t_zj, %t_j2] {handshake.bb = 2 : ui32, handshake.name = "mux_j2"} : <i1>, [<i32>, <i32>] to <i32>
  %i2 = mux %ci2 [%t_i1, %t_i2] {handshake.bb = 2 : ui32, handshake.name = "mux_i2"} : <i1>, [<i32>, <i32>] to <i32>
  %k2 = mux %ci2 [%t_k1, %t_k2] {handshake.bb = 2 : ui32, handshake.name = "mux_k2"} : <i1>, [<i32>, <i32>] to <i32>
  %one2 = constant %c2 {handshake.bb = 2 : ui32, handshake.name = "one2", value = 1 : i32} : <>, <i32>
  %j2n = addi %j2, %one2 {handshake.bb = 2 : ui32, handshake.name = "inc_j"} : <i32>
  %i2n = addi %i2, %one2 {handshake.bb = 2 : ui32, handshake.name = "inc_i"} : <i32>
  %four2 = constant %c2 {handshake.bb = 2 : ui32, handshake.name = "four2", value = 4 : i32} : <>, <i32>
  %lt2 = cmpi ult, %j2n, %four2 {handshake.bb = 2 : ui32, handshake.name = "cmp2"} : <i32>
  %t_j2, %f_j2 = cond_br %lt2, %j2n {handshake.bb = 2 : ui32, handshake.name = "loop_j"} : <i1>, <i32>
  %t_i2, %f_i2x = cond_br %lt2, %i2 {handshake.bb = 2 : ui32, handshake.name = "loop_i2"} : <i1>, <i32>
  %t_i2x, %f_i2 = cond_br %lt2, %i2n {handshake.bb = 2 : ui32, handshake.name = "exit_i2"} : <i1>, <i32>
  %t_k2, %f_k2 = cond_br %lt2, %k2 {handshake.bb = 2 : ui32, handshake.name = "loop_k2"} : <i1>, <i32>
  %t_ctrl2, %f_ctrl2 = cond_br %lt2, %c2 {handshake.bb = 2 : ui32, handshake.name = "exit2"} : <i1>, <>
  %c3, %ci3 = control_merge [%f_ctrl1, %t_ctrl3]  {handshake.bb = 3 : ui32, handshake.name = "merge3"} : [<>, <>] to <>, <i1>
  %x3 = mux %ci3 [%f_zx, %t_x3] {handshake.bb = 3 : ui32, handshake.name = "mux_x"} : <i1>, [<i32>, <i32>] to <i32>
  %k3 = mux %ci3 [%f_k1, %t_k3] {handshake.bb = 3 : ui32, handshake.name = "mux_k3"} : <i1>, [<i32>, <i32>] to <i32>
  %x3n = addi %x3, %k3 {handshake.bb = 3 : ui32, handshake.name = "add_k"} : <i32>
  %hundred = constant %c3 {handshake.bb = 3 : ui32, handshake.name = "hundred", value = 100 : i32} : <>, <i32>
  %lt3 = cmpi ult, %x3n, %hundred {handshake.bb = 3 : ui32, handshake.name = "cmp3"} : <i32>
  %t_x3, %f_x3 = cond_br %lt3, %x3n {handshake.bb = 3 : ui32, handshake.name = "loop_x"} : <i1>, <i32>
  %t_k3, %f_k3 = cond_br %lt3, %k3 {handshake.bb = 3 : ui32, handshake.name = "loop_k3"} : <i1>, <i32>
  %t_ctrl3, %f_ctrl3 = cond_br %lt3, %c3 {handshake.bb = 3 : ui32, handshake.name = "exit3"} : <i1>, <>
  %c4, %ci4 = control_merge [%f_ctrl3]  {handshake.bb = 4 : ui32, handshake.name = "merge4"} : [<>] to <>, <i1>
  end {handshake.bb = 4 : ui32, handshake.name = "end0"} %f_x3, %c4 : <i32>, <>
}
