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
// The group is declined: the circuit stays sequential (block 1's exit still
// hands the control to block 2's merge, no join) and the group leaves the
// attribute.
// CHECK-LABEL:   handshake.func @live_out(
// CHECK-NOT:       handshake.parallel_regions
// CHECK:           %{{.*}}, %[[EXIT:.*]] = cond_br %{{.*}}, %{{.*}} {handshake.bb = 1 : ui32, handshake.name = "exit1"}
// CHECK:           control_merge [%[[EXIT]], %{{.*}}] {handshake.bb = 2 : ui32, handshake.name = "merge2"}
// CHECK-NOT:       join
// expected-warning @below {{the regions of group 0 of 'handshake.parallel_regions' run one after the other: region 0 computes this value and region 1 uses it}}
handshake.func @live_out(%arg0: !handshake.control<>, ...) -> !handshake.control<> attributes {argNames = ["start"], resNames = ["end"], handshake.parallel_regions = [{entry = 0 : ui32, regions = [[1], [2]], successor = 3 : ui32}]} {
  %0 = constant %arg0 {handshake.bb = 0 : ui32, handshake.name = "zero", value = 0 : i32} : <>, <i32>
  %1 = br %0 {handshake.bb = 0 : ui32, handshake.name = "br_zero"} : <i32>
  %2 = br %arg0 {handshake.bb = 0 : ui32, handshake.name = "br_ctrl"} : <>
  %result, %index = control_merge [%2, %trueResult_0]  {handshake.bb = 1 : ui32, handshake.name = "merge1"} : [<>, <>] to <>, <i1>
  %3 = mux %index [%1, %trueResult] {handshake.bb = 1 : ui32, handshake.name = "mux_i"} : <i1>, [<i32>, <i32>] to <i32>
  %4 = constant %result {handshake.bb = 1 : ui32, handshake.name = "one", value = 1 : i32} : <>, <i32>
  // expected-note @below {{here}}
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
// recorded), and both go through one LSQ. The dependence is found first, and
// the group is declined.
// CHECK-LABEL:   handshake.func @dependence(
// CHECK-NOT:       handshake.parallel_regions
// CHECK:           %{{.*}}, %[[EXIT:.*]] = cond_br %{{.*}}, %{{.*}} {handshake.bb = 1 : ui32, handshake.name = "exit1"}
// CHECK:           control_merge [%[[EXIT]], %{{.*}}] {handshake.bb = 2 : ui32, handshake.name = "merge2"}
// CHECK-NOT:       join
// expected-warning @below {{the regions of group 0 of 'handshake.parallel_regions' run one after the other: a memory dependence with 'store0' crosses from region 0 to region 1}}
handshake.func @dependence(%arg0: memref<8xi32>, %arg1: !handshake.control<>, %arg2: !handshake.control<>, ...) -> (!handshake.control<>, !handshake.control<>) attributes {argNames = ["a", "a_start", "start"], resNames = ["a_end", "end"], handshake.parallel_regions = [{entry = 0 : ui32, regions = [[1], [2]], successor = 3 : ui32}]} {
  %0:2 = lsq[%arg0 : memref<8xi32>] (%arg1, %result, %addressResult, %result_2, %addressResult_4, %dataResult_5, %arg2)  {groupSizes = [1 : i32, 1 : i32], handshake.name = "lsq0"} : (!handshake.control<>, !handshake.control<>, !handshake.channel<i32>, !handshake.control<>, !handshake.channel<i32>, !handshake.channel<i32>, !handshake.control<>) -> (!handshake.channel<i32>, !handshake.control<>)
  %1 = constant %arg2 {handshake.bb = 0 : ui32, handshake.name = "zero", value = 0 : i32} : <>, <i32>
  %2 = br %1 {handshake.bb = 0 : ui32, handshake.name = "br_zero"} : <i32>
  %3 = br %arg2 {handshake.bb = 0 : ui32, handshake.name = "br_ctrl"} : <>
  %result, %index = control_merge [%3, %trueResult_0]  {handshake.bb = 1 : ui32, handshake.name = "merge1"} : [<>, <>] to <>, <i1>
  %4 = mux %index [%2, %trueResult] {handshake.bb = 1 : ui32, handshake.name = "mux_i"} : <i1>, [<i32>, <i32>] to <i32>
  // expected-note @below {{here}}
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

// The same two loops on one LSQ, without a recorded dependence: declined.
// CHECK-LABEL:   handshake.func @shared_lsq(
// CHECK-NOT:       handshake.parallel_regions
// CHECK:           %{{.*}}, %[[EXIT:.*]] = cond_br %{{.*}}, %{{.*}} {handshake.bb = 1 : ui32, handshake.name = "exit1"}
// CHECK:           control_merge [%[[EXIT]], %{{.*}}] {handshake.bb = 2 : ui32, handshake.name = "merge2"}
// CHECK-NOT:       join
// expected-warning @below {{the regions of group 0 of 'handshake.parallel_regions' run one after the other: this LSQ serves both region 0 and region 1}}
handshake.func @shared_lsq(%arg0: memref<8xi32>, %arg1: !handshake.control<>, %arg2: !handshake.control<>, ...) -> (!handshake.control<>, !handshake.control<>) attributes {argNames = ["a", "a_start", "start"], resNames = ["a_end", "end"], handshake.parallel_regions = [{entry = 0 : ui32, regions = [[1], [2]], successor = 3 : ui32}]} {
  // expected-note @below {{here}}
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
// that zero: a live-out, and the group is declined. Block 2 still takes the
// sum from block 1's exit.
// CHECK-LABEL:   handshake.func @updated_in_the_loop(
// CHECK-NOT:       handshake.parallel_regions
// CHECK:           %{{.*}}, %[[SUM:.*]] = cond_br %{{.*}}, %{{.*}} {handshake.bb = 1 : ui32, handshake.name = "exit_s"}
// CHECK:           %{{.*}}, %[[EXIT:.*]] = cond_br %{{.*}}, %{{.*}} {handshake.bb = 1 : ui32, handshake.name = "exit1"}
// CHECK:           control_merge [%[[EXIT]], %{{.*}}] {handshake.bb = 2 : ui32, handshake.name = "merge2"}
// CHECK:           mux %{{.*}} [%[[SUM]], %{{.*}}] {handshake.bb = 2 : ui32, handshake.name = "mux_s2"}
// CHECK-NOT:       join
// expected-warning @below {{the regions of group 0 of 'handshake.parallel_regions' run one after the other: region 0's loop updates this value and region 1 uses it}}
handshake.func @updated_in_the_loop(%arg0: !handshake.control<>, ...) -> (!handshake.channel<i32>, !handshake.control<>) attributes {argNames = ["start"], resNames = ["sum", "end"], handshake.parallel_regions = [{entry = 0 : ui32, regions = [[1], [2]], successor = 3 : ui32}]} {
  %0 = constant %arg0 {handshake.bb = 0 : ui32, handshake.name = "zero", value = 0 : i32} : <>, <i32>
  %1 = br %0 {handshake.bb = 0 : ui32, handshake.name = "br_zero"} : <i32>
  %2 = br %0 {handshake.bb = 0 : ui32, handshake.name = "br_sum"} : <i32>
  %3 = br %arg0 {handshake.bb = 0 : ui32, handshake.name = "br_ctrl"} : <>
  %result, %index = control_merge [%3, %trueResult_0]  {handshake.bb = 1 : ui32, handshake.name = "merge1"} : [<>, <>] to <>, <i1>
  %4 = mux %index [%1, %trueResult] {handshake.bb = 1 : ui32, handshake.name = "mux_i"} : <i1>, [<i32>, <i32>] to <i32>
  // expected-note @below {{here}}
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

// -----

// The nest of @carried_through_an_inner_loop after esa-loop-invariants-as-wires
// took out the inner loop's ring for k: the inner loop reads the entry it
// holds (value_k), and its exit forwards that entry through a blocker
// (exit_k2) onto the outer loop's back edge. Blocker, the held token put
// together again (held) and the arrival fork are wires: mux_k1's back edge
// still leads back to it, and the group lowers.
// CHECK-LABEL:   handshake.func @blocker_on_the_back_edge(
// CHECK:           %[[K:.*]] = br %arg0 {handshake.bb = 0 : ui32, handshake.name = "br_k"}
// CHECK:           mux %{{.*}} [%[[K]], %{{.*}}] {handshake.bb = 3 : ui32, handshake.name = "mux_k3"}
// CHECK:           join %{{.*}}, %{{.*}} {handshake.bb = 4 : ui32
handshake.func @blocker_on_the_back_edge(%arg0: !handshake.channel<i32>, %arg1: !handshake.control<>, ...) -> (!handshake.channel<i32>, !handshake.control<>) attributes {argNames = ["k", "start"], resNames = ["out", "end"], handshake.parallel_regions = [{entry = 0 : ui32, regions = [[1, 2], [3]], successor = 4 : ui32}]} {
  %0 = constant %arg1 {handshake.bb = 0 : ui32, handshake.name = "zero", value = 0 : i32} : <>, <i32>
  %1 = br %0 {handshake.bb = 0 : ui32, handshake.name = "br_zero"} : <i32>
  %2 = br %arg0 {handshake.bb = 0 : ui32, handshake.name = "br_k"} : <i32>
  %3 = br %arg1 {handshake.bb = 0 : ui32, handshake.name = "br_ctrl"} : <>
  %c1, %ci1 = control_merge [%3, %f_ctrl2]  {handshake.bb = 1 : ui32, handshake.name = "merge1"} : [<>, <>] to <>, <i1>
  %i1 = mux %ci1 [%1, %f_i2] {handshake.bb = 1 : ui32, handshake.name = "mux_i1"} : <i1>, [<i32>, <i32>] to <i32>
  %k1 = mux %ci1 [%2, %out] {handshake.bb = 1 : ui32, handshake.name = "mux_k1"} : <i1>, [<i32>, <i32>] to <i32>
  %four = constant %c1 {handshake.bb = 1 : ui32, handshake.name = "four", value = 4 : i32} : <>, <i32>
  %lt1 = cmpi ult, %i1, %four {handshake.bb = 1 : ui32, handshake.name = "cmp1"} : <i32>
  %t_ctrl1, %f_ctrl1 = cond_br %lt1, %c1 {handshake.bb = 1 : ui32, handshake.name = "exit1"} : <i1>, <>
  %t_i1, %f_i1 = cond_br %lt1, %i1 {handshake.bb = 1 : ui32, handshake.name = "to_inner_i"} : <i1>, <i32>
  %t_k1, %f_k1 = cond_br %lt1, %k1 {handshake.bb = 1 : ui32, handshake.name = "to_inner_k"} : <i1>, <i32>
  %zj = constant %c1 {handshake.bb = 1 : ui32, handshake.name = "zero_for_j", value = 0 : i32} : <>, <i32>
  %t_zj, %f_zj = cond_br %lt1, %zj {handshake.bb = 1 : ui32, handshake.name = "to_inner_j"} : <i1>, <i32>
  %zx = constant %c1 {handshake.bb = 1 : ui32, handshake.name = "zero_for_x", value = 0 : i32} : <>, <i32>
  %t_zx, %f_zx = cond_br %lt1, %zx {handshake.bb = 1 : ui32, handshake.name = "loop_zero"} : <i1>, <i32>
  %arr:2 = fork [2] %t_k1 {handshake.bb = 1 : ui32, handshake.name = "arrival"} : <i32>
  %actl, %adata = unbundle %arr#1 {handshake.bb = 1 : ui32, handshake.name = "arrived"} : <i32> to _
  %sctl, %sdata = unbundle %arr#0 {handshake.bb = 1 : ui32, handshake.name = "split"} : <i32> to _
  %held = bundle %sctl, %sdata {handshake.bb = 1 : ui32, handshake.name = "held"} : _ to <i32>
  %first = join %t_ctrl1, %actl {handshake.bb = 2 : ui32, handshake.name = "first"} : <>
  %c2, %ci2 = control_merge [%first, %t_ctrl2]  {handshake.bb = 2 : ui32, handshake.name = "merge2"} : [<>, <>] to <>, <i1>
  %kc = buffer %c2, bufferType = ONE_SLOT_BREAK_R, numSlots = 1, dvLatency = 0 {handshake.bb = 2 : ui32, handshake.name = "slot_k"} : <>
  %kv = bundle %kc, %sdata {handshake.bb = 2 : ui32, handshake.name = "value_k"} : _ to <i32>
  %j2 = mux %ci2 [%t_zj, %t_j2] {handshake.bb = 2 : ui32, handshake.name = "mux_j2"} : <i1>, [<i32>, <i32>] to <i32>
  %i2 = mux %ci2 [%t_i1, %t_i2] {handshake.bb = 2 : ui32, handshake.name = "mux_i2"} : <i1>, [<i32>, <i32>] to <i32>
  %one2 = constant %c2 {handshake.bb = 2 : ui32, handshake.name = "one2", value = 1 : i32} : <>, <i32>
  %j2n = addi %j2, %kv {handshake.bb = 2 : ui32, handshake.name = "add_k"} : <i32>
  %i2n = addi %i2, %one2 {handshake.bb = 2 : ui32, handshake.name = "inc_i"} : <i32>
  %four2 = constant %c2 {handshake.bb = 2 : ui32, handshake.name = "four2", value = 4 : i32} : <>, <i32>
  %lt2 = cmpi ult, %j2n, %four2 {handshake.bb = 2 : ui32, handshake.name = "cmp2"} : <i32>
  %t_j2, %f_j2 = cond_br %lt2, %j2n {handshake.bb = 2 : ui32, handshake.name = "loop_j"} : <i1>, <i32>
  %t_i2, %f_i2x = cond_br %lt2, %i2 {handshake.bb = 2 : ui32, handshake.name = "loop_i2"} : <i1>, <i32>
  %t_i2x, %f_i2 = cond_br %lt2, %i2n {handshake.bb = 2 : ui32, handshake.name = "exit_i2"} : <i1>, <i32>
  %t_kv, %f_kv = cond_br %lt2, %kv {handshake.bb = 2 : ui32, handshake.name = "loop_k2"} : <i1>, <i32>
  sink %t_kv {handshake.bb = 2 : ui32, handshake.name = "sink_k2"} : <i32>
  %out = blocker %held, %f_kv {handshake.bb = 2 : ui32, handshake.name = "exit_k2"} : <i32>
  %t_ctrl2, %f_ctrl2 = cond_br %lt2, %c2 {handshake.bb = 2 : ui32, handshake.name = "exit2"} : <i1>, <>
  %c3, %ci3 = control_merge [%f_ctrl1, %t_ctrl3]  {handshake.bb = 3 : ui32, handshake.name = "merge3"} : [<>, <>] to <>, <i1>
  %x3 = mux %ci3 [%f_zx, %t_x3] {handshake.bb = 3 : ui32, handshake.name = "mux_x"} : <i1>, [<i32>, <i32>] to <i32>
  %k3 = mux %ci3 [%f_k1, %t_k3] {handshake.bb = 3 : ui32, handshake.name = "mux_k3"} : <i1>, [<i32>, <i32>] to <i32>
  %x3n = addi %x3, %k3 {handshake.bb = 3 : ui32, handshake.name = "add_k3"} : <i32>
  %hundred = constant %c3 {handshake.bb = 3 : ui32, handshake.name = "hundred", value = 100 : i32} : <>, <i32>
  %lt3 = cmpi ult, %x3n, %hundred {handshake.bb = 3 : ui32, handshake.name = "cmp3"} : <i32>
  %t_x3, %f_x3 = cond_br %lt3, %x3n {handshake.bb = 3 : ui32, handshake.name = "loop_x"} : <i1>, <i32>
  %t_k3, %f_k3 = cond_br %lt3, %k3 {handshake.bb = 3 : ui32, handshake.name = "loop_k3"} : <i1>, <i32>
  %t_ctrl3, %f_ctrl3 = cond_br %lt3, %c3 {handshake.bb = 3 : ui32, handshake.name = "exit3"} : <i1>, <>
  %c4, %ci4 = control_merge [%f_ctrl3]  {handshake.bb = 4 : ui32, handshake.name = "merge4"} : [<>] to <>, <i1>
  end {handshake.bb = 4 : ui32, handshake.name = "end0"} %f_x3, %c4 : <i32>, <>
}

// -----

// h enters block 1 as x and its back edge hands it x again, which block 1
// carries in a ring of its own (mux_x, entered through a second branch of
// x, br_x). mux_h's back edge leads to mux_x, whose loop entry is the entry's
// x like mux_h's: one value on every path, and block 2 reads it from the
// entry.
// CHECK-LABEL:   handshake.func @two_rings_one_value(
// CHECK:           %[[H:.*]] = br %arg0 {handshake.bb = 0 : ui32, handshake.name = "br_h"}
// CHECK:           mux %{{.*}} [%[[H]], %{{.*}}] {handshake.bb = 2 : ui32, handshake.name = "mux_h2"}
// CHECK:           join %{{.*}}, %{{.*}} {handshake.bb = 3 : ui32
handshake.func @two_rings_one_value(%arg0: !handshake.channel<i32>, %arg1: !handshake.control<>, ...) -> (!handshake.channel<i32>, !handshake.control<>) attributes {argNames = ["x", "start"], resNames = ["out", "end"], handshake.parallel_regions = [{entry = 0 : ui32, regions = [[1], [2]], successor = 3 : ui32}]} {
  %0 = constant %arg1 {handshake.bb = 0 : ui32, handshake.name = "zero", value = 0 : i32} : <>, <i32>
  %1 = br %0 {handshake.bb = 0 : ui32, handshake.name = "br_zero"} : <i32>
  %2 = br %arg0 {handshake.bb = 0 : ui32, handshake.name = "br_h"} : <i32>
  %3 = br %arg0 {handshake.bb = 0 : ui32, handshake.name = "br_x"} : <i32>
  %4 = br %arg1 {handshake.bb = 0 : ui32, handshake.name = "br_ctrl"} : <>
  %c1, %ci1 = control_merge [%4, %t_ctrl1]  {handshake.bb = 1 : ui32, handshake.name = "merge1"} : [<>, <>] to <>, <i1>
  %i = mux %ci1 [%1, %t_i] {handshake.bb = 1 : ui32, handshake.name = "mux_i"} : <i1>, [<i32>, <i32>] to <i32>
  %h = mux %ci1 [%2, %t_h] {handshake.bb = 1 : ui32, handshake.name = "mux_h"} : <i1>, [<i32>, <i32>] to <i32>
  %x = mux %ci1 [%3, %t_x] {handshake.bb = 1 : ui32, handshake.name = "mux_x"} : <i1>, [<i32>, <i32>] to <i32>
  %one = constant %c1 {handshake.bb = 1 : ui32, handshake.name = "one", value = 1 : i32} : <>, <i32>
  %i1 = addi %i, %one {handshake.bb = 1 : ui32, handshake.name = "inc_i"} : <i32>
  %ten = constant %c1 {handshake.bb = 1 : ui32, handshake.name = "ten", value = 10 : i32} : <>, <i32>
  %lt = cmpi ult, %i1, %ten {handshake.bb = 1 : ui32, handshake.name = "cmp1"} : <i32>
  %t_i, %f_i = cond_br %lt, %i1 {handshake.bb = 1 : ui32, handshake.name = "loop_i"} : <i1>, <i32>
  %t_h, %f_hx = cond_br %lt, %x {handshake.bb = 1 : ui32, handshake.name = "loop_h"} : <i1>, <i32>
  %t_x, %f_x = cond_br %lt, %x {handshake.bb = 1 : ui32, handshake.name = "loop_x"} : <i1>, <i32>
  %t_hy, %f_h = cond_br %lt, %h {handshake.bb = 1 : ui32, handshake.name = "exit_h"} : <i1>, <i32>
  %t_ctrl1, %f_ctrl1 = cond_br %lt, %c1 {handshake.bb = 1 : ui32, handshake.name = "exit1"} : <i1>, <>
  %zj = constant %c1 {handshake.bb = 1 : ui32, handshake.name = "zero_for_j", value = 0 : i32} : <>, <i32>
  %t_zj, %f_zj = cond_br %lt, %zj {handshake.bb = 1 : ui32, handshake.name = "loop_zero"} : <i1>, <i32>
  %c2, %ci2 = control_merge [%f_ctrl1, %t_ctrl2]  {handshake.bb = 2 : ui32, handshake.name = "merge2"} : [<>, <>] to <>, <i1>
  %j = mux %ci2 [%f_zj, %t_j] {handshake.bb = 2 : ui32, handshake.name = "mux_j"} : <i1>, [<i32>, <i32>] to <i32>
  %h2 = mux %ci2 [%f_h, %t_h2] {handshake.bb = 2 : ui32, handshake.name = "mux_h2"} : <i1>, [<i32>, <i32>] to <i32>
  %j1 = addi %j, %h2 {handshake.bb = 2 : ui32, handshake.name = "add_h"} : <i32>
  %hundred = constant %c2 {handshake.bb = 2 : ui32, handshake.name = "hundred", value = 100 : i32} : <>, <i32>
  %lt2 = cmpi ult, %j1, %hundred {handshake.bb = 2 : ui32, handshake.name = "cmp2"} : <i32>
  %t_j, %f_j = cond_br %lt2, %j1 {handshake.bb = 2 : ui32, handshake.name = "loop_j"} : <i1>, <i32>
  %t_h2, %f_h2 = cond_br %lt2, %h2 {handshake.bb = 2 : ui32, handshake.name = "loop_h2"} : <i1>, <i32>
  %t_ctrl2, %f_ctrl2 = cond_br %lt2, %c2 {handshake.bb = 2 : ui32, handshake.name = "exit2"} : <i1>, <>
  %c3, %ci3 = control_merge [%f_ctrl2]  {handshake.bb = 3 : ui32, handshake.name = "merge3"} : [<>] to <>, <i1>
  end {handshake.bb = 3 : ui32, handshake.name = "end0"} %f_j, %c3 : <i32>, <>
}

// -----

// A flag that enters block 1 as 0 and that the loop sets to 0 again on every
// iteration, through a copy of the literal of its own (zero_f): one value on
// every path, and block 2 reads the entry's.
// CHECK-LABEL:   handshake.func @reset_to_the_same_constant(
// CHECK:           %[[F:.*]] = br %{{.*}} {handshake.bb = 0 : ui32, handshake.name = "br_f"}
// CHECK:           mux %{{.*}} [%[[F]], %{{.*}}] {handshake.bb = 2 : ui32, handshake.name = "mux_f2"}
// CHECK:           join %{{.*}}, %{{.*}} {handshake.bb = 3 : ui32
handshake.func @reset_to_the_same_constant(%arg0: !handshake.control<>, ...) -> (!handshake.channel<i32>, !handshake.control<>) attributes {argNames = ["start"], resNames = ["out", "end"], handshake.parallel_regions = [{entry = 0 : ui32, regions = [[1], [2]], successor = 3 : ui32}]} {
  %0 = constant %arg0 {handshake.bb = 0 : ui32, handshake.name = "zero", value = 0 : i32} : <>, <i32>
  %1 = br %0 {handshake.bb = 0 : ui32, handshake.name = "br_zero"} : <i32>
  %2 = br %0 {handshake.bb = 0 : ui32, handshake.name = "br_f"} : <i32>
  %3 = br %arg0 {handshake.bb = 0 : ui32, handshake.name = "br_ctrl"} : <>
  %c1, %ci1 = control_merge [%3, %t_ctrl1]  {handshake.bb = 1 : ui32, handshake.name = "merge1"} : [<>, <>] to <>, <i1>
  %i = mux %ci1 [%1, %t_i] {handshake.bb = 1 : ui32, handshake.name = "mux_i"} : <i1>, [<i32>, <i32>] to <i32>
  %f = mux %ci1 [%2, %t_f] {handshake.bb = 1 : ui32, handshake.name = "mux_f"} : <i1>, [<i32>, <i32>] to <i32>
  %one = constant %c1 {handshake.bb = 1 : ui32, handshake.name = "one", value = 1 : i32} : <>, <i32>
  %i1 = addi %i, %one {handshake.bb = 1 : ui32, handshake.name = "inc_i"} : <i32>
  %ten = constant %c1 {handshake.bb = 1 : ui32, handshake.name = "ten", value = 10 : i32} : <>, <i32>
  %lt = cmpi ult, %i1, %ten {handshake.bb = 1 : ui32, handshake.name = "cmp1"} : <i32>
  %zf = constant %c1 {handshake.bb = 1 : ui32, handshake.name = "zero_f", value = 0 : i32} : <>, <i32>
  %t_i, %f_i = cond_br %lt, %i1 {handshake.bb = 1 : ui32, handshake.name = "loop_i"} : <i1>, <i32>
  %t_f, %f_fx = cond_br %lt, %zf {handshake.bb = 1 : ui32, handshake.name = "loop_f"} : <i1>, <i32>
  %t_fy, %f_f = cond_br %lt, %f {handshake.bb = 1 : ui32, handshake.name = "exit_f"} : <i1>, <i32>
  %t_ctrl1, %f_ctrl1 = cond_br %lt, %c1 {handshake.bb = 1 : ui32, handshake.name = "exit1"} : <i1>, <>
  %zj = constant %c1 {handshake.bb = 1 : ui32, handshake.name = "zero_for_j", value = 0 : i32} : <>, <i32>
  %t_zj, %f_zj = cond_br %lt, %zj {handshake.bb = 1 : ui32, handshake.name = "loop_zero"} : <i1>, <i32>
  %c2, %ci2 = control_merge [%f_ctrl1, %t_ctrl2]  {handshake.bb = 2 : ui32, handshake.name = "merge2"} : [<>, <>] to <>, <i1>
  %j = mux %ci2 [%f_zj, %t_j] {handshake.bb = 2 : ui32, handshake.name = "mux_j"} : <i1>, [<i32>, <i32>] to <i32>
  %f2 = mux %ci2 [%f_f, %t_f2] {handshake.bb = 2 : ui32, handshake.name = "mux_f2"} : <i1>, [<i32>, <i32>] to <i32>
  %j1 = addi %j, %f2 {handshake.bb = 2 : ui32, handshake.name = "add_f"} : <i32>
  %hundred = constant %c2 {handshake.bb = 2 : ui32, handshake.name = "hundred", value = 100 : i32} : <>, <i32>
  %lt2 = cmpi ult, %j1, %hundred {handshake.bb = 2 : ui32, handshake.name = "cmp2"} : <i32>
  %t_j, %f_j = cond_br %lt2, %j1 {handshake.bb = 2 : ui32, handshake.name = "loop_j"} : <i1>, <i32>
  %t_f2, %f_f2 = cond_br %lt2, %f2 {handshake.bb = 2 : ui32, handshake.name = "loop_f2"} : <i1>, <i32>
  %t_ctrl2, %f_ctrl2 = cond_br %lt2, %c2 {handshake.bb = 2 : ui32, handshake.name = "exit2"} : <i1>, <>
  %c3, %ci3 = control_merge [%f_ctrl2]  {handshake.bb = 3 : ui32, handshake.name = "merge3"} : [<>] to <>, <i1>
  end {handshake.bb = 3 : ui32, handshake.name = "end0"} %f_j, %c3 : <i32>, <>
}

// -----

// The constant block 1 makes for block 2 reaches block 2 through one branch
// whose exit feeds two muxes: two crossings from one operation. Both are
// re-made in the entry, and the branch and the constant, unused, are erased
// once.
// CHECK-LABEL:   handshake.func @one_branch_two_crossings(
// CHECK:           %[[ZERO:.*]] = constant %arg0 {handshake.bb = 0 : ui32, {{.*}}value = 0 : i32}
// CHECK-NOT:       loop_zero
// CHECK:           mux %{{.*}} [%[[ZERO]], %{{.*}}] {handshake.bb = 2 : ui32, handshake.name = "mux_j"}
// CHECK:           mux %{{.*}} [%[[ZERO]], %{{.*}}] {handshake.bb = 2 : ui32, handshake.name = "mux_m"}
// CHECK:           join
handshake.func @one_branch_two_crossings(%arg0: !handshake.control<>, ...) -> (!handshake.channel<i32>, !handshake.control<>) attributes {argNames = ["start"], resNames = ["out", "end"], handshake.parallel_regions = [{entry = 0 : ui32, regions = [[1], [2]], successor = 3 : ui32}]} {
  %0 = constant %arg0 {handshake.bb = 0 : ui32, handshake.name = "zero", value = 0 : i32} : <>, <i32>
  %1 = br %0 {handshake.bb = 0 : ui32, handshake.name = "br_zero"} : <i32>
  %2 = br %arg0 {handshake.bb = 0 : ui32, handshake.name = "br_ctrl"} : <>
  %result, %index = control_merge [%2, %t_c1]  {handshake.bb = 1 : ui32, handshake.name = "merge1"} : [<>, <>] to <>, <i1>
  %i = mux %index [%1, %t_i] {handshake.bb = 1 : ui32, handshake.name = "mux_i"} : <i1>, [<i32>, <i32>] to <i32>
  %one = constant %result {handshake.bb = 1 : ui32, handshake.name = "one", value = 1 : i32} : <>, <i32>
  %i1 = addi %i, %one {handshake.bb = 1 : ui32, handshake.name = "inc_i"} : <i32>
  %ten = constant %result {handshake.bb = 1 : ui32, handshake.name = "ten", value = 10 : i32} : <>, <i32>
  %lt = cmpi ult, %i1, %ten {handshake.bb = 1 : ui32, handshake.name = "cmp1"} : <i32>
  %t_i, %f_i = cond_br %lt, %i1 {handshake.bb = 1 : ui32, handshake.name = "loop_i"} : <i1>, <i32>
  %t_c1, %f_c1 = cond_br %lt, %result {handshake.bb = 1 : ui32, handshake.name = "exit1"} : <i1>, <>
  %z = constant %result {handshake.bb = 1 : ui32, handshake.name = "zero_for_j", value = 0 : i32} : <>, <i32>
  %t_z, %f_z = cond_br %lt, %z {handshake.bb = 1 : ui32, handshake.name = "loop_zero"} : <i1>, <i32>
  %result_2, %index_2 = control_merge [%f_c1, %t_c2]  {handshake.bb = 2 : ui32, handshake.name = "merge2"} : [<>, <>] to <>, <i1>
  %j = mux %index_2 [%f_z, %t_j] {handshake.bb = 2 : ui32, handshake.name = "mux_j"} : <i1>, [<i32>, <i32>] to <i32>
  %m = mux %index_2 [%f_z, %t_m] {handshake.bb = 2 : ui32, handshake.name = "mux_m"} : <i1>, [<i32>, <i32>] to <i32>
  %one2 = constant %result_2 {handshake.bb = 2 : ui32, handshake.name = "one2", value = 1 : i32} : <>, <i32>
  %j1 = addi %j, %one2 {handshake.bb = 2 : ui32, handshake.name = "inc_j"} : <i32>
  %m1 = addi %m, %j {handshake.bb = 2 : ui32, handshake.name = "acc_m"} : <i32>
  %ten2 = constant %result_2 {handshake.bb = 2 : ui32, handshake.name = "ten2", value = 10 : i32} : <>, <i32>
  %lt2 = cmpi ult, %j1, %ten2 {handshake.bb = 2 : ui32, handshake.name = "cmp2"} : <i32>
  %t_j, %f_j = cond_br %lt2, %j1 {handshake.bb = 2 : ui32, handshake.name = "loop_j"} : <i1>, <i32>
  %t_m, %f_m = cond_br %lt2, %m1 {handshake.bb = 2 : ui32, handshake.name = "loop_m"} : <i1>, <i32>
  %t_c2, %f_c2 = cond_br %lt2, %result_2 {handshake.bb = 2 : ui32, handshake.name = "exit2"} : <i1>, <>
  %result_3, %index_3 = control_merge [%f_c2]  {handshake.bb = 3 : ui32, handshake.name = "merge3"} : [<>] to <>, <i1>
  end {handshake.bb = 3 : ui32, handshake.name = "end0"} %f_m, %result_3 : <i32>, <>
}

// -----

// v comes from block 0, before the group, and block 2's loop hands it on
// through a branch of its own (filter_v), which chooses which of v's tokens
// block 3 receives. Taking v from block 0 would drop that choice: declined.
// CHECK-LABEL:   handshake.func @before_the_group_filtered(
// CHECK-NOT:       handshake.parallel_regions
// CHECK:           %{{.*}}, %[[V:.*]] = cond_br %{{.*}}, %{{.*}} {handshake.bb = 2 : ui32, handshake.name = "filter_v"}
// CHECK:           mux %{{.*}} [%[[V]], %{{.*}}] {handshake.bb = 3 : ui32, handshake.name = "mux_v"}
// CHECK-NOT:       join
// expected-warning @below {{the regions of group 0 of 'handshake.parallel_regions' run one after the other: region 1 would take a value of a block before the group past the branches and muxes of a region that choose its tokens}}
handshake.func @before_the_group_filtered(%arg0: !handshake.channel<i32>, %arg1: !handshake.control<>, ...) -> (!handshake.channel<i32>, !handshake.control<>) attributes {argNames = ["n", "start"], resNames = ["out", "end"], handshake.parallel_regions = [{entry = 1 : ui32, regions = [[2], [3]], successor = 4 : ui32}]} {
  // expected-note @below {{here}}
  %v = addi %arg0, %arg0 {handshake.bb = 0 : ui32, handshake.name = "v"} : <i32>
  %c0 = br %arg1 {handshake.bb = 0 : ui32, handshake.name = "br_ctrl0"} : <>
  %e, %ei = control_merge [%c0]  {handshake.bb = 1 : ui32, handshake.name = "merge1"} : [<>] to <>, <i1>
  %zero = constant %e {handshake.bb = 1 : ui32, handshake.name = "zero", value = 0 : i32} : <>, <i32>
  %bz = br %zero {handshake.bb = 1 : ui32, handshake.name = "br_zero"} : <i32>
  %c1 = br %e {handshake.bb = 1 : ui32, handshake.name = "br_ctrl1"} : <>
  %result, %index = control_merge [%c1, %t_c2]  {handshake.bb = 2 : ui32, handshake.name = "merge2"} : [<>, <>] to <>, <i1>
  %i = mux %index [%bz, %t_i] {handshake.bb = 2 : ui32, handshake.name = "mux_i"} : <i1>, [<i32>, <i32>] to <i32>
  %one = constant %result {handshake.bb = 2 : ui32, handshake.name = "one", value = 1 : i32} : <>, <i32>
  %i1 = addi %i, %one {handshake.bb = 2 : ui32, handshake.name = "inc_i"} : <i32>
  %ten = constant %result {handshake.bb = 2 : ui32, handshake.name = "ten", value = 10 : i32} : <>, <i32>
  %lt = cmpi ult, %i1, %ten {handshake.bb = 2 : ui32, handshake.name = "cmp1"} : <i32>
  %t_i, %f_i = cond_br %lt, %i1 {handshake.bb = 2 : ui32, handshake.name = "loop_i"} : <i1>, <i32>
  %t_v, %f_v = cond_br %lt, %v {handshake.bb = 2 : ui32, handshake.name = "filter_v"} : <i1>, <i32>
  sink %t_v {handshake.bb = 2 : ui32, handshake.name = "sink_v"} : <i32>
  %t_c2, %f_c2 = cond_br %lt, %result {handshake.bb = 2 : ui32, handshake.name = "exit2"} : <i1>, <>
  %result_3, %index_3 = control_merge [%f_c2, %t_c3]  {handshake.bb = 3 : ui32, handshake.name = "merge3"} : [<>, <>] to <>, <i1>
  %w = mux %index_3 [%f_v, %t_w] {handshake.bb = 3 : ui32, handshake.name = "mux_v"} : <i1>, [<i32>, <i32>] to <i32>
  %w1 = addi %w, %w {handshake.bb = 3 : ui32, handshake.name = "dbl"} : <i32>
  %hundred = constant %result_3 {handshake.bb = 3 : ui32, handshake.name = "hundred", value = 100 : i32} : <>, <i32>
  %lt3 = cmpi ult, %w1, %hundred {handshake.bb = 3 : ui32, handshake.name = "cmp3"} : <i32>
  %t_w, %f_w = cond_br %lt3, %w1 {handshake.bb = 3 : ui32, handshake.name = "loop_w"} : <i1>, <i32>
  %t_c3, %f_c3 = cond_br %lt3, %result_3 {handshake.bb = 3 : ui32, handshake.name = "exit3"} : <i1>, <>
  %result_4, %index_4 = control_merge [%f_c3]  {handshake.bb = 4 : ui32, handshake.name = "merge4"} : [<>] to <>, <i1>
  end {handshake.bb = 4 : ui32, handshake.name = "end0"} %f_w, %result_4 : <i32>, <>
}

// -----

// Block 2 receives k through a blocker that also waits for block 1's last
// induction value (hold_k): block 2 waits for block 1 there. Taking k from
// the entry would take it past that wait: declined.
// CHECK-LABEL:   handshake.func @blocker_on_the_crossing(
// CHECK-NOT:       handshake.parallel_regions
// CHECK:           %[[HELD:.*]] = blocker %{{.*}}, %{{.*}} {handshake.bb = 1 : ui32, handshake.name = "hold_k"}
// CHECK:           mux %{{.*}} [%[[HELD]], %{{.*}}] {handshake.bb = 2 : ui32, handshake.name = "mux_k2"}
// CHECK-NOT:       join
// expected-warning @below {{the regions of group 0 of 'handshake.parallel_regions' run one after the other: region 1 would take this value past a blocker of region 0, which also waits for its other inputs}}
handshake.func @blocker_on_the_crossing(%arg0: !handshake.channel<i32>, %arg1: !handshake.control<>, ...) -> (!handshake.channel<i32>, !handshake.control<>) attributes {argNames = ["k", "start"], resNames = ["out", "end"], handshake.parallel_regions = [{entry = 0 : ui32, regions = [[1], [2]], successor = 3 : ui32}]} {
  %0 = constant %arg1 {handshake.bb = 0 : ui32, handshake.name = "zero", value = 0 : i32} : <>, <i32>
  %1 = br %0 {handshake.bb = 0 : ui32, handshake.name = "br_zero"} : <i32>
  %2 = br %arg0 {handshake.bb = 0 : ui32, handshake.name = "br_k"} : <i32>
  %3 = br %arg1 {handshake.bb = 0 : ui32, handshake.name = "br_ctrl"} : <>
  %result, %index = control_merge [%3, %t_c1]  {handshake.bb = 1 : ui32, handshake.name = "merge1"} : [<>, <>] to <>, <i1>
  %i = mux %index [%1, %t_i] {handshake.bb = 1 : ui32, handshake.name = "mux_i"} : <i1>, [<i32>, <i32>] to <i32>
  %k = mux %index [%2, %t_k] {handshake.bb = 1 : ui32, handshake.name = "mux_k1"} : <i1>, [<i32>, <i32>] to <i32>
  %one = constant %result {handshake.bb = 1 : ui32, handshake.name = "one", value = 1 : i32} : <>, <i32>
  %i1 = addi %i, %one {handshake.bb = 1 : ui32, handshake.name = "inc_i"} : <i32>
  %ten = constant %result {handshake.bb = 1 : ui32, handshake.name = "ten", value = 10 : i32} : <>, <i32>
  %lt = cmpi ult, %i1, %ten {handshake.bb = 1 : ui32, handshake.name = "cmp1"} : <i32>
  %t_i, %f_i = cond_br %lt, %i1 {handshake.bb = 1 : ui32, handshake.name = "loop_i"} : <i1>, <i32>
  %t_k, %f_k = cond_br %lt, %k {handshake.bb = 1 : ui32, handshake.name = "loop_k1"} : <i1>, <i32>
  // expected-note @below {{here}}
  %held = blocker %f_k, %f_i {handshake.bb = 1 : ui32, handshake.name = "hold_k"} : <i32>
  %t_c1, %f_c1 = cond_br %lt, %result {handshake.bb = 1 : ui32, handshake.name = "exit1"} : <i1>, <>
  %result_2, %index_2 = control_merge [%f_c1, %t_c2]  {handshake.bb = 2 : ui32, handshake.name = "merge2"} : [<>, <>] to <>, <i1>
  %k2 = mux %index_2 [%held, %t_k2] {handshake.bb = 2 : ui32, handshake.name = "mux_k2"} : <i1>, [<i32>, <i32>] to <i32>
  %k3 = addi %k2, %k2 {handshake.bb = 2 : ui32, handshake.name = "dbl"} : <i32>
  %hundred = constant %result_2 {handshake.bb = 2 : ui32, handshake.name = "hundred", value = 100 : i32} : <>, <i32>
  %lt2 = cmpi ult, %k3, %hundred {handshake.bb = 2 : ui32, handshake.name = "cmp2"} : <i32>
  %t_k2, %f_k2 = cond_br %lt2, %k3 {handshake.bb = 2 : ui32, handshake.name = "loop_k2"} : <i1>, <i32>
  %t_c2, %f_c2 = cond_br %lt2, %result_2 {handshake.bb = 2 : ui32, handshake.name = "exit2"} : <i1>, <>
  %result_3, %index_3 = control_merge [%f_c2]  {handshake.bb = 3 : ui32, handshake.name = "merge3"} : [<>] to <>, <i1>
  end {handshake.bb = 3 : ui32, handshake.name = "end0"} %f_k2, %result_3 : <i32>, <>
}

// -----

// The constant block 1 makes for block 2 leaves through a lazy fork (one
// output sunk). Re-made in the entry, it leaves the fork, the branch and the
// constant unused, and they go.
// CHECK-LABEL:   handshake.func @lazy_fork_on_the_crossing(
// CHECK-NOT:       lazy_fork
// CHECK-NOT:       loop_zero
// CHECK:           join
handshake.func @lazy_fork_on_the_crossing(%arg0: !handshake.control<>, ...) -> (!handshake.channel<i32>, !handshake.control<>) attributes {argNames = ["start"], resNames = ["out", "end"], handshake.parallel_regions = [{entry = 0 : ui32, regions = [[1], [2]], successor = 3 : ui32}]} {
  %0 = constant %arg0 {handshake.bb = 0 : ui32, handshake.name = "zero", value = 0 : i32} : <>, <i32>
  %1 = br %0 {handshake.bb = 0 : ui32, handshake.name = "br_zero"} : <i32>
  %2 = br %arg0 {handshake.bb = 0 : ui32, handshake.name = "br_ctrl"} : <>
  %result, %index = control_merge [%2, %t_c1]  {handshake.bb = 1 : ui32, handshake.name = "merge1"} : [<>, <>] to <>, <i1>
  %i = mux %index [%1, %t_i] {handshake.bb = 1 : ui32, handshake.name = "mux_i"} : <i1>, [<i32>, <i32>] to <i32>
  %one = constant %result {handshake.bb = 1 : ui32, handshake.name = "one", value = 1 : i32} : <>, <i32>
  %i1 = addi %i, %one {handshake.bb = 1 : ui32, handshake.name = "inc_i"} : <i32>
  %ten = constant %result {handshake.bb = 1 : ui32, handshake.name = "ten", value = 10 : i32} : <>, <i32>
  %lt = cmpi ult, %i1, %ten {handshake.bb = 1 : ui32, handshake.name = "cmp1"} : <i32>
  %t_i, %f_i = cond_br %lt, %i1 {handshake.bb = 1 : ui32, handshake.name = "loop_i"} : <i1>, <i32>
  %t_c1, %f_c1 = cond_br %lt, %result {handshake.bb = 1 : ui32, handshake.name = "exit1"} : <i1>, <>
  %z = constant %result {handshake.bb = 1 : ui32, handshake.name = "zero_for_j", value = 0 : i32} : <>, <i32>
  %t_z, %f_z = cond_br %lt, %z {handshake.bb = 1 : ui32, handshake.name = "loop_zero"} : <i1>, <i32>
  %lz:2 = lazy_fork [2] %f_z {handshake.bb = 1 : ui32, handshake.name = "lazy_zero"} : <i32>
  sink %lz#1 {handshake.bb = 1 : ui32, handshake.name = "sink_zero"} : <i32>
  %result_2, %index_2 = control_merge [%f_c1, %t_c2]  {handshake.bb = 2 : ui32, handshake.name = "merge2"} : [<>, <>] to <>, <i1>
  %j = mux %index_2 [%lz#0, %t_j] {handshake.bb = 2 : ui32, handshake.name = "mux_j"} : <i1>, [<i32>, <i32>] to <i32>
  %one2 = constant %result_2 {handshake.bb = 2 : ui32, handshake.name = "one2", value = 1 : i32} : <>, <i32>
  %j1 = addi %j, %one2 {handshake.bb = 2 : ui32, handshake.name = "inc_j"} : <i32>
  %ten2 = constant %result_2 {handshake.bb = 2 : ui32, handshake.name = "ten2", value = 10 : i32} : <>, <i32>
  %lt2 = cmpi ult, %j1, %ten2 {handshake.bb = 2 : ui32, handshake.name = "cmp2"} : <i32>
  %t_j, %f_j = cond_br %lt2, %j1 {handshake.bb = 2 : ui32, handshake.name = "loop_j"} : <i1>, <i32>
  %t_c2, %f_c2 = cond_br %lt2, %result_2 {handshake.bb = 2 : ui32, handshake.name = "exit2"} : <i1>, <>
  %result_3, %index_3 = control_merge [%f_c2]  {handshake.bb = 3 : ui32, handshake.name = "merge3"} : [<>] to <>, <i1>
  end {handshake.bb = 3 : ui32, handshake.name = "end0"} %f_j, %result_3 : <i32>, <>
}

// -----

// Block 2 receives a value that, followed back, only goes round a ring of
// wires in block 1 (a one-input merge and its branch): declined, rather
// than followed forever.
// CHECK-LABEL:   handshake.func @ring_of_wires(
// CHECK-NOT:       handshake.parallel_regions
// CHECK-NOT:       join
// expected-warning @below {{the regions of group 0 of 'handshake.parallel_regions' run one after the other: this value only goes round a ring of wires in region 0, and region 1 uses it}}
handshake.func @ring_of_wires(%arg0: !handshake.control<>, ...) -> (!handshake.channel<i32>, !handshake.control<>) attributes {argNames = ["start"], resNames = ["out", "end"], handshake.parallel_regions = [{entry = 0 : ui32, regions = [[1], [2]], successor = 3 : ui32}]} {
  %0 = constant %arg0 {handshake.bb = 0 : ui32, handshake.name = "zero", value = 0 : i32} : <>, <i32>
  %1 = br %0 {handshake.bb = 0 : ui32, handshake.name = "br_zero"} : <i32>
  %2 = br %arg0 {handshake.bb = 0 : ui32, handshake.name = "br_ctrl"} : <>
  %result, %index = control_merge [%2, %t_c1]  {handshake.bb = 1 : ui32, handshake.name = "merge1"} : [<>, <>] to <>, <i1>
  %i = mux %index [%1, %t_i] {handshake.bb = 1 : ui32, handshake.name = "mux_i"} : <i1>, [<i32>, <i32>] to <i32>
  %one = constant %result {handshake.bb = 1 : ui32, handshake.name = "one", value = 1 : i32} : <>, <i32>
  %i1 = addi %i, %one {handshake.bb = 1 : ui32, handshake.name = "inc_i"} : <i32>
  %ten = constant %result {handshake.bb = 1 : ui32, handshake.name = "ten", value = 10 : i32} : <>, <i32>
  %lt = cmpi ult, %i1, %ten {handshake.bb = 1 : ui32, handshake.name = "cmp1"} : <i32>
  %t_i, %f_i = cond_br %lt, %i1 {handshake.bb = 1 : ui32, handshake.name = "loop_i"} : <i1>, <i32>
  %r = merge %t_r {handshake.bb = 1 : ui32, handshake.name = "ring"} : <i32>
  // expected-note @below {{here}}
  %t_r, %f_r = cond_br %lt, %r {handshake.bb = 1 : ui32, handshake.name = "loop_r"} : <i1>, <i32>
  %t_c1, %f_c1 = cond_br %lt, %result {handshake.bb = 1 : ui32, handshake.name = "exit1"} : <i1>, <>
  %result_2, %index_2 = control_merge [%f_c1, %t_c2]  {handshake.bb = 2 : ui32, handshake.name = "merge2"} : [<>, <>] to <>, <i1>
  %j = mux %index_2 [%f_r, %t_j] {handshake.bb = 2 : ui32, handshake.name = "mux_j"} : <i1>, [<i32>, <i32>] to <i32>
  %one2 = constant %result_2 {handshake.bb = 2 : ui32, handshake.name = "one2", value = 1 : i32} : <>, <i32>
  %j1 = addi %j, %one2 {handshake.bb = 2 : ui32, handshake.name = "inc_j"} : <i32>
  %ten2 = constant %result_2 {handshake.bb = 2 : ui32, handshake.name = "ten2", value = 10 : i32} : <>, <i32>
  %lt2 = cmpi ult, %j1, %ten2 {handshake.bb = 2 : ui32, handshake.name = "cmp2"} : <i32>
  %t_j, %f_j = cond_br %lt2, %j1 {handshake.bb = 2 : ui32, handshake.name = "loop_j"} : <i1>, <i32>
  %t_c2, %f_c2 = cond_br %lt2, %result_2 {handshake.bb = 2 : ui32, handshake.name = "exit2"} : <i1>, <>
  %result_3, %index_3 = control_merge [%f_c2]  {handshake.bb = 3 : ui32, handshake.name = "merge3"} : [<>] to <>, <i1>
  end {handshake.bb = 3 : ui32, handshake.name = "end0"} %f_j, %result_3 : <i32>, <>
}

// -----

// Three regions; block 1 sums into mux_s, block 2 carries the sum on
// (mux_s1) and block 3 reads it (mux_s2). Block 3's ops come first, so its
// crossing, from region 1, is followed first: through region 1 into region 0,
// whose loop updates the sum. The warning names the crossing's region, 2,
// not the region the walk got to.
// CHECK-LABEL:   handshake.func @names_the_crossing(
// CHECK-NOT:       handshake.parallel_regions
// CHECK-NOT:       join
// expected-warning @below {{the regions of group 0 of 'handshake.parallel_regions' run one after the other: region 0's loop updates this value and region 2 uses it}}
handshake.func @names_the_crossing(%arg0: !handshake.control<>, ...) -> (!handshake.channel<i32>, !handshake.control<>) attributes {argNames = ["start"], resNames = ["sum", "end"], handshake.parallel_regions = [{entry = 0 : ui32, regions = [[1], [2], [3]], successor = 4 : ui32}]} {
  %r3, %i3 = control_merge [%f_c2, %t_c3]  {handshake.bb = 3 : ui32, handshake.name = "merge3"} : [<>, <>] to <>, <i1>
  %s2 = mux %i3 [%f_s1, %t_s2] {handshake.bb = 3 : ui32, handshake.name = "mux_s2"} : <i1>, [<i32>, <i32>] to <i32>
  %s2n = addi %s2, %s2 {handshake.bb = 3 : ui32, handshake.name = "dbl"} : <i32>
  %h3 = constant %r3 {handshake.bb = 3 : ui32, handshake.name = "hundred", value = 100 : i32} : <>, <i32>
  %lt3 = cmpi ult, %s2n, %h3 {handshake.bb = 3 : ui32, handshake.name = "cmp3"} : <i32>
  %t_s2, %f_s2 = cond_br %lt3, %s2n {handshake.bb = 3 : ui32, handshake.name = "loop_s2"} : <i1>, <i32>
  %t_c3, %f_c3 = cond_br %lt3, %r3 {handshake.bb = 3 : ui32, handshake.name = "exit3"} : <i1>, <>
  %0 = constant %arg0 {handshake.bb = 0 : ui32, handshake.name = "zero", value = 0 : i32} : <>, <i32>
  %1 = br %0 {handshake.bb = 0 : ui32, handshake.name = "br_zero"} : <i32>
  %2 = br %0 {handshake.bb = 0 : ui32, handshake.name = "br_sum"} : <i32>
  %3 = br %arg0 {handshake.bb = 0 : ui32, handshake.name = "br_ctrl"} : <>
  %r1, %i1 = control_merge [%3, %t_c1]  {handshake.bb = 1 : ui32, handshake.name = "merge1"} : [<>, <>] to <>, <i1>
  %i = mux %i1 [%1, %t_i] {handshake.bb = 1 : ui32, handshake.name = "mux_i"} : <i1>, [<i32>, <i32>] to <i32>
  // expected-note @below {{here}}
  %s = mux %i1 [%2, %t_s] {handshake.bb = 1 : ui32, handshake.name = "mux_s"} : <i1>, [<i32>, <i32>] to <i32>
  %one = constant %r1 {handshake.bb = 1 : ui32, handshake.name = "one", value = 1 : i32} : <>, <i32>
  %in = addi %i, %one {handshake.bb = 1 : ui32, handshake.name = "inc_i"} : <i32>
  %sn = addi %s, %i {handshake.bb = 1 : ui32, handshake.name = "acc_s"} : <i32>
  %ten = constant %r1 {handshake.bb = 1 : ui32, handshake.name = "ten", value = 10 : i32} : <>, <i32>
  %lt = cmpi ult, %in, %ten {handshake.bb = 1 : ui32, handshake.name = "cmp1"} : <i32>
  %t_i, %f_i = cond_br %lt, %in {handshake.bb = 1 : ui32, handshake.name = "loop_i"} : <i1>, <i32>
  %t_s, %f_sx = cond_br %lt, %sn {handshake.bb = 1 : ui32, handshake.name = "loop_s"} : <i1>, <i32>
  %t_sy, %f_s = cond_br %lt, %s {handshake.bb = 1 : ui32, handshake.name = "exit_s"} : <i1>, <i32>
  %t_c1, %f_c1 = cond_br %lt, %r1 {handshake.bb = 1 : ui32, handshake.name = "exit1"} : <i1>, <>
  %z = constant %r1 {handshake.bb = 1 : ui32, handshake.name = "zero_for_j", value = 0 : i32} : <>, <i32>
  %t_z, %f_z = cond_br %lt, %z {handshake.bb = 1 : ui32, handshake.name = "loop_zero"} : <i1>, <i32>
  %r2, %i2 = control_merge [%f_c1, %t_c2]  {handshake.bb = 2 : ui32, handshake.name = "merge2"} : [<>, <>] to <>, <i1>
  %j = mux %i2 [%f_z, %t_j] {handshake.bb = 2 : ui32, handshake.name = "mux_j"} : <i1>, [<i32>, <i32>] to <i32>
  %s1 = mux %i2 [%f_s, %t_s1] {handshake.bb = 2 : ui32, handshake.name = "mux_s1"} : <i1>, [<i32>, <i32>] to <i32>
  %one2 = constant %r2 {handshake.bb = 2 : ui32, handshake.name = "one2", value = 1 : i32} : <>, <i32>
  %jn = addi %j, %one2 {handshake.bb = 2 : ui32, handshake.name = "inc_j"} : <i32>
  %ten2 = constant %r2 {handshake.bb = 2 : ui32, handshake.name = "ten2", value = 10 : i32} : <>, <i32>
  %lt2 = cmpi ult, %jn, %ten2 {handshake.bb = 2 : ui32, handshake.name = "cmp2"} : <i32>
  %t_j, %f_j = cond_br %lt2, %jn {handshake.bb = 2 : ui32, handshake.name = "loop_j"} : <i1>, <i32>
  %t_s1, %f_s1 = cond_br %lt2, %s1 {handshake.bb = 2 : ui32, handshake.name = "loop_s1"} : <i1>, <i32>
  %t_c2, %f_c2 = cond_br %lt2, %r2 {handshake.bb = 2 : ui32, handshake.name = "exit2"} : <i1>, <>
  %r4, %i4 = control_merge [%f_c3]  {handshake.bb = 4 : ui32, handshake.name = "merge4"} : [<>] to <>, <i1>
  end {handshake.bb = 4 : ui32, handshake.name = "end0"} %f_s2, %r4 : <i32>, <>
}

// -----

// The group names block 7, which holds no operation: an attribute that does
// not fit the function is an error.
// expected-error @below {{block 7 named in 'handshake.parallel_regions' has no operation}}
handshake.func @no_such_block(%arg0: !handshake.control<>, ...) -> !handshake.control<> attributes {argNames = ["start"], resNames = ["end"], handshake.parallel_regions = [{entry = 0 : ui32, regions = [[1], [7]], successor = 2 : ui32}]} {
  %0 = br %arg0 {handshake.bb = 0 : ui32, handshake.name = "br_ctrl"} : <>
  %result, %index = control_merge [%0]  {handshake.bb = 1 : ui32, handshake.name = "merge1"} : [<>] to <>, <i1>
  %1 = br %result {handshake.bb = 1 : ui32, handshake.name = "br1"} : <>
  %result_2, %index_2 = control_merge [%1]  {handshake.bb = 2 : ui32, handshake.name = "merge2"} : [<>] to <>, <i1>
  end {handshake.bb = 2 : ui32, handshake.name = "end0"} %result_2 : <>
}
