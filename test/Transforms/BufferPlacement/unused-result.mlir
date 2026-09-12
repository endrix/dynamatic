// A function whose only block-annotated operations are the kinds the
// invariant check exempts -- sinks, memory accesses -- has no control-flow
// graph for the MILP: an esa actor's round holds its memory controller's
// accesses, tagged with the block of the action that issues them, among
// hundreds of untagged operations and raw wires the MILP has no variables
// for. It used to go in; now it is left as it is, like a function with no
// annotation at all (@tagged_sink_only). A function that does go in with a
// raw wire nobody reads -- an unbundled extra signal -- used to crash twice,
// on the result with no users in the invariant check and on that wire's
// timing constraint; now the result is passed over and the constraint is
// skipped with a warning (@unread_extra).
//
// REQUIRES: cbc
// RUN: dynamatic-opt %s --handshake-place-buffers="algorithm=fpga20 solver=cbc timeout=30 timing-models=%dynamatic_src_root/data/components.json spec-timing-models=%dynamatic_src_root/data/spec-timing.json" -o /dev/null 2>&1 | FileCheck %s

// CHECK: remark: function has no basic-block annotations, so the MILP has nothing to optimize; its buffers are left as they are
handshake.func @tagged_sink_only(%arg0: !handshake.channel<i32>, %arg1: !handshake.channel<i1>, %arg2: !handshake.control<>, ...) -> (!handshake.channel<i32>, !handshake.control<>) attributes {argNames = ["a", "c", "start"], resNames = ["out", "end"], handshake.frequencies = []} {
  %t, %f = cond_br %arg1, %arg0 : <i1>, <i32>
  sink %f {handshake.bb = 0 : ui32} : <i32>
  %c1, %d1 = unbundle %t : <i32> to _
  %r = bundle %c1, %d1 : _ to <i32>
  end %r, %arg2 : <i32>, <>
}

// CHECK: warning: a port of this unit has no MILP variables; its path constraint is skipped
handshake.func @unread_extra(%arg0: !handshake.channel<i32, [extraDown: i4]>, %arg1: !handshake.control<>, ...) -> (!handshake.channel<i32>, !handshake.control<>) attributes {argNames = ["a", "start"], resNames = ["out", "end"], handshake.frequencies = []} {
  %c1, %d1, %e1 = unbundle %arg0 : <i32, [extraDown: i4]> to _
  %r = bundle %c1, %d1 : _ to <i32>
  end {handshake.bb = 0 : ui32} %r, %arg1 : <i32>, <>
}
