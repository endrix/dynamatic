// RUN: dynamatic-opt --exp-test-ftd-exit-merges --split-input-file --verify-diagnostics %s | FileCheck %s

// The exit merges of a function of several returns, as the fast token
// delivery branches them (ftd::branchExitMergeOperands). The lowering always
// builds them itself, one per result with one operand per return, so a cf
// function cannot reach the refusals below; they are pinned on handshake
// functions written by hand. Left unrefused, a result of another shape would
// be delivered from every return.

// Each operand of a result's merge passes through a branch tagged with its
// return block; the end-control merge after the results is left as it is.

// CHECK-LABEL:   handshake.func @twoReturns(
// CHECK:           %[[X:.*]] = br %{{.*}} {handshake.bb = 1 : ui32} : <i32>
// CHECK:           %[[Y:.*]] = br %{{.*}} {handshake.bb = 2 : ui32} : <i32>
// CHECK:           %[[R:.*]] = merge %[[X]], %[[Y]] {handshake.bb = 3 : ui32} : <i32>
// CHECK-NOT:       br
// CHECK:           end {handshake.bb = 3 : ui32} %[[R]], %{{.*}} : <i32>, <>
handshake.func @twoReturns(%a: !handshake.channel<i32>, %b: !handshake.channel<i32>, %start: !handshake.control<>) -> (!handshake.channel<i32>, !handshake.control<>) attributes {test.ftd_num_results = 1 : i32, test.ftd_return_blocks = array<i32: 1, 2>} {
  %r = merge %a, %b {handshake.bb = 3 : ui32} : <i32>
  %c = merge %start, %start {handshake.bb = 3 : ui32} : <>
  end {handshake.bb = 3 : ui32} %r, %c : <i32>, <>
}

// -----

// A result computed from the returns' values instead of merged from them.

handshake.func @notAMerge(%a: !handshake.channel<i32>, %b: !handshake.channel<i32>, %start: !handshake.control<>) -> !handshake.channel<i32> attributes {test.ftd_num_results = 1 : i32, test.ftd_return_blocks = array<i32: 1, 2>} {
  // expected-error @below {{a result of a function of 2 returns must be a merge of one operand per return, which the fast token delivery steers by return block; left as it is, every return's value would be delivered}}
  %r = addi %a, %b {handshake.bb = 3 : ui32} : <i32>
  end {handshake.bb = 3 : ui32} %r : <i32>
}

// -----

// A merge of one operand more than there are returns.

handshake.func @mergeOfThree(%a: !handshake.channel<i32>, %b: !handshake.channel<i32>, %c: !handshake.channel<i32>, %start: !handshake.control<>) -> !handshake.channel<i32> attributes {test.ftd_num_results = 1 : i32, test.ftd_return_blocks = array<i32: 1, 2>} {
  // expected-error @below {{a result of a function of 2 returns must be a merge of one operand per return}}
  %r = merge %a, %b, %c {handshake.bb = 3 : ui32} : <i32>
  end {handshake.bb = 3 : ui32} %r : <i32>
}

// -----

// A result that no operation produces: the error is on the end.

handshake.func @argument(%a: !handshake.channel<i32>, %start: !handshake.control<>) -> !handshake.channel<i32> attributes {test.ftd_num_results = 1 : i32, test.ftd_return_blocks = array<i32: 1, 2>} {
  // expected-error @below {{a result of a function of 2 returns must be a merge of one operand per return}}
  end {handshake.bb = 3 : ui32} %a : <i32>
}

// -----

// An end with fewer operands than the original function had results.

handshake.func @fewerOperands(%a: !handshake.channel<i32>, %b: !handshake.channel<i32>, %start: !handshake.control<>) -> !handshake.channel<i32> attributes {test.ftd_num_results = 2 : i32, test.ftd_return_blocks = array<i32: 1, 2>} {
  %r = merge %a, %b {handshake.bb = 3 : ui32} : <i32>
  // expected-error @below {{the end has 1 operands, fewer than the function's 2 results}}
  end {handshake.bb = 3 : ui32} %r : <i32>
}
