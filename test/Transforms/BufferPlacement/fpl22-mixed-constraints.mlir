// FPL22's mixed-domain path constraints of a unit (a condition's data into
// a valid or a ready, a valid into a ready or a data), kept where both of
// their channels are in the CFDFC union. One whose channel is out of it is
// skipped, and the unit's next ones are still added. The loop's header mux
// leads with its select's data into each operand's ready, and its first data
// operand is the loop's entry, outside the union; each branch leads with its
// condition's data into each result's valid, and its false result leaves the
// loop. So the mux kept 2 of the 9 it has in the union, and each branch 1
// of its 5.
// The constraints are read off the MILP's model as dumped, before the
// solver runs (CBC writes them unnamed, so by the two pins they relate).
//
// REQUIRES: cbc
// RUN: rm -rf %t && mkdir -p %t && cd %t && dynamatic-opt %s --handshake-place-buffers="algorithm=fpl22 solver=cbc timeout=30 dump-milp-models=true timing-models=%dynamatic_src_root/data/components.json spec-timing-models=%dynamatic_src_root/data/spec-timing.json" -o /dev/null
// RUN: FileCheck %s < %t/buffer-placement/loop-cfunion0_model.lp

// The mux's select's data into the back edge's ready, and the back edge's
// valid into the result's data, the select's ready and its own ready.
// CHECK-DAG: dataPathOut_cmerge_index_index_header - readyPathIn_br_i_trueOut_ins_1_header <=
// CHECK-DAG: - dataPathIn_header_outs_ins_fork_i + validPathOut_br_i_trueOut_ins_1_header <=
// CHECK-DAG: - readyPathIn_cmerge_index_index_header + validPathOut_br_i_trueOut_ins_1_header <=
// CHECK-DAG: - readyPathIn_br_i_trueOut_ins_1_header + validPathOut_br_i_trueOut_ins_1_header <=
// The branch's condition's data into its operands' readies, and its two
// operands' valids into each other's ready (they are joined).
// CHECK-DAG: dataPathOut_fork_c_outs_0_condition_br_i - readyPathIn_next_result_data_br_i <=
// CHECK-DAG: dataPathOut_fork_c_outs_0_condition_br_i - readyPathIn_fork_c_outs_0_condition_br_i <=
// CHECK-DAG: - readyPathIn_next_result_data_br_i + validPathOut_fork_c_outs_0_condition_br_i <=
// CHECK-DAG: - readyPathIn_fork_c_outs_0_condition_br_i + validPathOut_next_result_data_br_i <=

handshake.func @loop(%arg0: !handshake.channel<i32>, %arg1: !handshake.control<>, ...) -> (!handshake.channel<i32>, !handshake.control<>) attributes {argNames = ["i0", "start"], resNames = ["out", "end"], handshake.frequencies = [[0, 1, 1, 0], [1, 1, 63, 1], [1, 2, 1, 0]]} {
  %i0 = br %arg0 {handshake.bb = 0 : ui32, handshake.name = "entry"} : <i32>
  %c0 = br %arg1 {handshake.bb = 0 : ui32, handshake.name = "entry_ctrl"} : <>
  %i = mux %index [%i0, %ti] {handshake.bb = 1 : ui32, handshake.name = "header"} : <i1>, [<i32>, <i32>] to <i32>
  %ctrl, %index = control_merge [%c0, %tc] {handshake.bb = 1 : ui32, handshake.name = "cmerge"} : [<>, <>] to <>, <i1>
  %i2:2 = fork [2] %i {handshake.bb = 1 : ui32, handshake.name = "fork_i"} : <i32>
  %s = source {handshake.bb = 1 : ui32, handshake.name = "src_n"} : <>
  %n = constant %s {handshake.bb = 1 : ui32, handshake.name = "n", value = 64 : i32} : <>, <i32>
  %cond = cmpi slt, %i2#0, %n {handshake.bb = 1 : ui32, handshake.name = "cmp"} : <i32>
  %cond2:2 = fork [2] %cond {handshake.bb = 1 : ui32, handshake.name = "fork_c"} : <i1>
  %s2 = source {handshake.bb = 1 : ui32, handshake.name = "src_one"} : <>
  %one = constant %s2 {handshake.bb = 1 : ui32, handshake.name = "one", value = 1 : i32} : <>, <i32>
  %next = addi %i2#1, %one {handshake.bb = 1 : ui32, handshake.name = "next"} : <i32>
  %ti, %fi = cond_br %cond2#0, %next {handshake.bb = 1 : ui32, handshake.name = "br_i"} : <i1>, <i32>
  %tc, %fc = cond_br %cond2#1, %ctrl {handshake.bb = 1 : ui32, handshake.name = "br_c"} : <i1>, <>
  %out = br %fi {handshake.bb = 2 : ui32, handshake.name = "exit"} : <i32>
  %done = br %fc {handshake.bb = 2 : ui32, handshake.name = "exit_ctrl"} : <>
  end {handshake.bb = 2 : ui32, handshake.name = "end0"} %out, %done : <i32>, <>
}
