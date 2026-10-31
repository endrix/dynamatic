// RUN: dynamatic-opt %s | dynamatic-opt | FileCheck %s

// A commit on a decision, one on a control token, and a stand-in on a flag
// print and parse back as themselves; the commit's kill is a raw wire, and
// one wire serves every stand-in of its domain. A domain with two commits
// (here domain 1, its second commit in series after a commit of domain 2 on
// one decision) and a stand-in on both kills print and parse back too.

// CHECK-LABEL: handshake.func @commit
// CHECK: %[[OUT:.*]], %[[KILL:.*]] = commit %arg0 : <i3>
// CHECK: %[[CTRL:.*]], %[[CKILL:.*]] = commit %arg2 {domain = 1 : ui32} : <>
// CHECK: %[[F:.*]] = stand_in %arg1, %[[KILL]] : <i1>
// CHECK: %[[G:.*]] = stand_in %arg3, %[[KILL]] : <i2>
// CHECK: %[[E2:.*]], %[[EKILL2:.*]] = commit %arg4 {domain = 2 : ui32} : <i3>
// CHECK: %[[E1:.*]], %[[EKILL1:.*]] = commit %[[E2]] {domain = 1 : ui32} : <i3>
// CHECK: %[[H:.*]] = stand_in %arg5, %[[CKILL]], %[[EKILL1]] : <i1>
// CHECK: end %[[OUT]], %[[F]], %[[CTRL]], %[[G]], %[[E1]], %[[H]] : <i3>, <i1>, <>, <i2>, <i3>, <i1>
handshake.func @commit(%d: !handshake.channel<i3>, %f: !handshake.channel<i1>,
                       %c: !handshake.control<>, %g: !handshake.channel<i2>,
                       %e: !handshake.channel<i3>, %h: !handshake.channel<i1>, ...)
    -> (!handshake.channel<i3>, !handshake.channel<i1>, !handshake.control<>,
        !handshake.channel<i2>, !handshake.channel<i3>, !handshake.channel<i1>)
    attributes {argNames = ["d", "f", "c", "g", "e", "h"],
                resNames = ["d_out", "f_out", "c_out", "g_out", "e_out", "h_out"]} {
  %out, %kill = commit %d : <i3>
  %ctrl, %ckill = commit %c {domain = 1 : ui32} : <>
  %0 = stand_in %f, %kill : <i1>
  %1 = stand_in %g, %kill : <i2>
  %e2, %ekill2 = commit %e {domain = 2 : ui32} : <i3>
  %e1, %ekill1 = commit %e2 {domain = 1 : ui32} : <i3>
  %2 = stand_in %h, %ckill, %ekill1 : <i1>
  end %out, %0, %ctrl, %1, %e1, %2 : <i3>, <i1>, <>, <i2>, <i3>, <i1>
}

// A commit whose kill comes when its token is first offered prints its
// `kill_at_valid` and parses back.
// CHECK-LABEL: handshake.func @at_valid
// CHECK: %[[O:.*]], %[[K:.*]] = commit %arg0 {domain = 3 : ui32, kill_at_valid} : <i3>
// CHECK: %[[S:.*]] = stand_in %arg1, %[[K]] : <i1>
handshake.func @at_valid(%d: !handshake.channel<i3>, %f: !handshake.channel<i1>, ...)
    -> (!handshake.channel<i3>, !handshake.channel<i1>)
    attributes {argNames = ["d", "f"], resNames = ["d_out", "f_out"]} {
  %out, %kill = commit %d {domain = 3 : ui32, kill_at_valid} : <i3>
  %0 = stand_in %f, %kill : <i1>
  end %out, %0 : <i3>, <i1>
}
