// Straight to the queue replaces the merges of the network it builds for the
// LSQ's group allocation by the gates of the GSA analysis
// (replaceMergeToGSA), whose inputs have no senders: their conditions come
// from their producer blocks. The input is the FTD lowering of
//
//   for (int i = 1; i < n; ++i) {
//     int x = a[i - 1];
//     if (x > 5) a[i] = x - 1; else a[i - 1] = x + 2;
//   }
//
// as the dynamatic flow gives it to the pass. The allocation token of the
// group of ^bb1 is a MU in the loop header, and its loop input a gamma at
// ^bb4 taking the token of the group of ^bb3.
//
// RUN: dynamatic-opt %s --handshake-deactivate-mem-dependencies --handshake-replace-memory-interfaces --handshake-straight-to-queue --handshake-combine-steering-logic | FileCheck %s

// CHECK-LABEL: handshake.func @stq_if(
// CHECK-DAG:     %[[MU:[0-9]+]] = mux %{{[0-9]+}} [%{{[a-zA-Z0-9_]+}}, %[[BACK:[a-zA-Z0-9_]+]]] {ftd.MU, {{.*}} : <i1>, [<>, <>] to <>
// CHECK-DAG:     %[[F1:[0-9]+]]:2 = lazy_fork [2] %[[MU]] {
// CHECK-DAG:     %[[BACK]], %{{[a-zA-Z0-9_]+}} = cond_br %{{[0-9]+}}, %[[G:[0-9]+]] {
// CHECK-DAG:     %[[G]] = mux %{{[0-9]+}} [%[[F2:[0-9]+]]#0, %{{[a-zA-Z0-9_]+}}] {ftd.GAMMA, handshake.bb = 4
// CHECK-DAG:     %[[F2]]:2 = lazy_fork [2] %{{[a-zA-Z0-9_]+}} {handshake.bb = 3
// CHECK-DAG:     lsq[MC] (%[[F1]]#1, %{{[a-zA-Z0-9_]+}}, %[[F2]]#1,
// CHECK:         end
module {
  handshake.func @stq_if(%arg0: memref<100xi32>, %arg1: !handshake.channel<i32>, %arg2: !handshake.control<>, %arg3: !handshake.control<>, ...) -> (!handshake.control<>, !handshake.control<>) attributes {argNames = ["a", "n", "a_start", "start"], cfg.edges = "[0,1,5,cmpi0][2,4][4,1,5,cmpi2][1,2,3,cmpi1][3,4]", handshake.mem_interfaces_from_deps, resNames = ["a_end", "end"]} {
    %trueResult, %falseResult = cond_br %13, %12 {ftd.skip, handshake.bb = 1 : ui32, handshake.name = "cond_br3"} : <i1>, <i32>
    %trueResult_0, %falseResult_1 = cond_br %13, %7 {handshake.bb = 1 : ui32, handshake.name = "cond_br14"} : <i1>, <i32>
    %trueResult_2, %falseResult_3 = cond_br %13, %dataResult {handshake.bb = 1 : ui32, handshake.name = "cond_br15"} : <i1>, <i32>
    %trueResult_4, %falseResult_5 = cond_br %27, %26 {handshake.bb = 4 : ui32, handshake.name = "cond_br16"} : <i1>, <i32>
    %trueResult_6, %falseResult_7 = cond_br %5, %4 {handshake.bb = 0 : ui32, handshake.name = "cond_br17"} : <i1>, <i32>
    %trueResult_8, %falseResult_9 = cond_br %27, %1 {handshake.bb = 4 : ui32, handshake.name = "cond_br18"} : <i1>, <i32>
    %trueResult_10, %falseResult_11 = cond_br %5, %arg1 {handshake.bb = 0 : ui32, handshake.name = "cond_br19"} : <i1>, <i32>
    %0 = init %27 {ftd.imerge, handshake.bb = 1 : ui32, handshake.name = "init0"} : <i1>
    %1 = mux %0 [%trueResult_10, %trueResult_8] {ftd.regen, handshake.bb = 1 : ui32, handshake.name = "mux0"} : <i1>, [<i32>, <i32>] to <i32>
    %outputs, %memEnd = mem_controller[%arg0 : memref<100xi32>] %arg2 (%14, %addressResult_18, %dataResult_19, %19, %2#1, %2#2, %2#3) %result_28 {connectedBlocks = [2 : i32, 3 : i32], handshake.name = "mem_controller0"} :    (!handshake.channel<i32>, !handshake.channel<i32>, !handshake.channel<i32>, !handshake.channel<i32>, !handshake.channel<i32>, !handshake.channel<i32>, !handshake.channel<i32>) -> !handshake.channel<i32>
    %2:4 = lsq[MC] (%result, %addressResult, %result_20, %addressResult_22, %dataResult_23, %outputs)  {groupSizes = [1 : i32, 1 : i32], handshake.name = "lsq0"} : (!handshake.control<>, !handshake.channel<i32>, !handshake.control<>, !handshake.channel<i32>, !handshake.channel<i32>, !handshake.channel<i32>) -> (!handshake.channel<i32>, !handshake.channel<i32>, !handshake.channel<i32>, !handshake.channel<i32>)
    %3 = source {handshake.bb = 0 : ui32, handshake.name = "source0"} : <>
    %4 = constant %3 {handshake.bb = 0 : ui32, handshake.name = "constant0", value = 1 : i32} : <>, <i32>
    %5 = cmpi sgt, %arg1, %4 {handshake.bb = 0 : ui32, handshake.name = "cmpi0"} : <i32>
    %trueResult_12, %falseResult_13 = cond_br %5, %arg3 {handshake.bb = 0 : ui32, handshake.name = "cond_br11"} : <i1>, <>
    %result, %index = control_merge [%trueResult_12, %trueResult_26]  {handshake.bb = 1 : ui32, handshake.name = "control_merge0"} : [<>, <>] to <>, <i1>
    %6 = init %27 {ftd.imerge, handshake.bb = 1 : ui32, handshake.name = "init1"} : <i1>
    %7 = mux %6 [%trueResult_6, %trueResult_4] {ftd.MU, handshake.bb = 1 : ui32, handshake.name = "mux1"} : <i1>, [<i32>, <i32>] to <i32>
    %8 = source {handshake.bb = 1 : ui32, handshake.name = "source1"} : <>
    %9 = constant %8 {handshake.bb = 1 : ui32, handshake.name = "constant1", value = 5 : i32} : <>, <i32>
    %10 = source {handshake.bb = 1 : ui32, handshake.name = "source2"} : <>
    %11 = constant %10 {handshake.bb = 1 : ui32, handshake.name = "constant5", value = -1 : i32} : <>, <i32>
    %12 = addi %7, %11 {handshake.bb = 1 : ui32, handshake.name = "addi1"} : <i32>
    %addressResult, %dataResult = load[%12] %2#0 {handshake.bb = 1 : ui32, handshake.deps = #handshake<deps[{dstAccess : "store2", loopDepth : 0, distance : 0, isActive : true}]>, handshake.name = "load0"} : <i32>, <i32>, <i32>, <i32>
    %13 = cmpi sgt, %dataResult, %9 {handshake.bb = 1 : ui32, handshake.name = "cmpi1"} : <i32>
    %trueResult_14, %falseResult_15 = cond_br %13, %result {handshake.bb = 1 : ui32, handshake.name = "cond_br12"} : <i1>, <>
    %14 = constant %result_16 {handshake.bb = 2 : ui32, handshake.name = "constant2", value = 1 : i32} : <>, <i32>
    %result_16, %index_17 = control_merge [%trueResult_14]  {handshake.bb = 2 : ui32, handshake.name = "control_merge1"} : [<>] to <>, <i1>
    %15 = source {handshake.bb = 2 : ui32, handshake.name = "source3"} : <>
    %16 = constant %15 {handshake.bb = 2 : ui32, handshake.name = "constant7", value = -1 : i32} : <>, <i32>
    %17 = addi %trueResult_2, %16 {handshake.bb = 2 : ui32, handshake.name = "addi2"} : <i32>
    %addressResult_18, %dataResult_19 = store[%trueResult_0] %17 {handshake.bb = 2 : ui32, handshake.name = "store1"} : <i32>, <i32>, <i32>, <i32>
    %18 = br %result_16 {handshake.bb = 2 : ui32, handshake.name = "br2"} : <>
    %19 = constant %result_20 {handshake.bb = 3 : ui32, handshake.name = "constant3", value = 1 : i32} : <>, <i32>
    %result_20, %index_21 = control_merge [%falseResult_15]  {handshake.bb = 3 : ui32, handshake.name = "control_merge2"} : [<>] to <>, <i1>
    %20 = source {handshake.bb = 3 : ui32, handshake.name = "source4"} : <>
    %21 = constant %20 {handshake.bb = 3 : ui32, handshake.name = "constant8", value = 2 : i32} : <>, <i32>
    %22 = addi %falseResult_3, %21 {handshake.bb = 3 : ui32, handshake.name = "addi3"} : <i32>
    %addressResult_22, %dataResult_23 = store[%falseResult] %22 {handshake.bb = 3 : ui32, handshake.deps = #handshake<deps[{dstAccess : "load0", loopDepth : 0, distance : 0, isActive : true}]>, handshake.name = "store2"} : <i32>, <i32>, <i32>, <i32>
    %23 = br %result_20 {handshake.bb = 3 : ui32, handshake.name = "br3"} : <>
    %result_24, %index_25 = control_merge [%18, %23]  {handshake.bb = 4 : ui32, handshake.name = "control_merge3"} : [<>, <>] to <>, <i1>
    %24 = source {handshake.bb = 4 : ui32, handshake.name = "source5"} : <>
    %25 = constant %24 {handshake.bb = 4 : ui32, handshake.name = "constant9", value = 1 : i32} : <>, <i32>
    %26 = addi %7, %25 {handshake.bb = 4 : ui32, handshake.name = "addi4"} : <i32>
    %27 = cmpi slt, %26, %1 {handshake.bb = 4 : ui32, handshake.name = "cmpi2"} : <i32>
    %trueResult_26, %falseResult_27 = cond_br %27, %result_24 {handshake.bb = 4 : ui32, handshake.name = "cond_br13"} : <i1>, <>
    %result_28, %index_29 = control_merge [%falseResult_13, %falseResult_27]  {handshake.bb = 5 : ui32, handshake.name = "control_merge4"} : [<>, <>] to <>, <i1>
    end {handshake.bb = 5 : ui32, handshake.name = "end0"} %memEnd, %arg3 : <>, <>
  }
}

