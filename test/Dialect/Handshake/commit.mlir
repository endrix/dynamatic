// RUN: dynamatic-opt %s | dynamatic-opt | FileCheck %s

// A commit on a decision, one on a control token, and a stand-in on a flag
// print and parse back as themselves; the commit's kill is a raw wire, and
// one wire serves every stand-in of its domain.

// CHECK-LABEL: handshake.func @commit
// CHECK: %[[OUT:.*]], %[[KILL:.*]] = commit %arg0 : <i3>
// CHECK: %[[CTRL:.*]], %[[CKILL:.*]] = commit %arg2 {domain = 1 : ui32} : <>
// CHECK: %[[F:.*]] = stand_in %arg1, %[[KILL]] : <i1>
// CHECK: %[[G:.*]] = stand_in %arg3, %[[KILL]] : <i2>
// CHECK: end %[[OUT]], %[[F]], %[[CTRL]], %[[G]] : <i3>, <i1>, <>, <i2>
handshake.func @commit(%d: !handshake.channel<i3>, %f: !handshake.channel<i1>,
                       %c: !handshake.control<>, %g: !handshake.channel<i2>, ...)
    -> (!handshake.channel<i3>, !handshake.channel<i1>, !handshake.control<>,
        !handshake.channel<i2>)
    attributes {argNames = ["d", "f", "c", "g"],
                resNames = ["d_out", "f_out", "c_out", "g_out"]} {
  %out, %kill = commit %d : <i3>
  %ctrl, %ckill = commit %c {domain = 1 : ui32} : <>
  %0 = stand_in %f, %kill : <i1>
  %1 = stand_in %g, %kill : <i2>
  end %out, %0, %ctrl, %1 : <i3>, <i1>, <>, <i2>
}
