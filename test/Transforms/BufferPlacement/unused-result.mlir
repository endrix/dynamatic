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
// skipped with a warning (@unread_extra). A raw wire read in two places --
// a data wire unbundled once and bundled again in two blocks -- made fpga20's
// throughput objective abort, asking which edge of the CFG the wire is (an
// edge has one reader); it is no channel the placer can cut, and it now
// counts as a forward edge (@read_twice).
//
// REQUIRES: cbc
// RUN: dynamatic-opt %s --handshake-place-buffers="algorithm=fpga20 solver=cbc timeout=30 timing-models=%dynamatic_src_root/data/components.json spec-timing-models=%dynamatic_src_root/data/spec-timing.json" -o /dev/null 2>&1 | FileCheck %s
// RUN: dynamatic-opt %s --handshake-place-buffers="algorithm=fpga20 solver=cbc timeout=30 timing-models=%dynamatic_src_root/data/components.json spec-timing-models=%dynamatic_src_root/data/spec-timing.json" 2>/dev/null | FileCheck %s --check-prefix=PLACED

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

// PLACED-LABEL: handshake.func @read_twice
// PLACED:         bundle %{{[^,]+}}, %[[D:[^ ]+]] {{.*}}handshake.bb = 0 : ui32
// PLACED:         bundle %{{[^,]+}}, %[[D]] {{.*}}handshake.bb = 1 : ui32
// PLACED:         end
handshake.func @read_twice(%arg0: !handshake.channel<i32>, %arg1: !handshake.control<>, ...) -> (!handshake.channel<i32>, !handshake.channel<i32>, !handshake.control<>) attributes {argNames = ["a", "start"], resNames = ["out0", "out1", "end"], handshake.frequencies = [[0, 1, 1, 0]]} {
  %c1, %d1 = unbundle %arg0 {handshake.bb = 0 : ui32} : <i32> to _
  %f:2 = fork [2] %arg1 {handshake.bb = 0 : ui32} : <>
  %r0 = bundle %c1, %d1 {handshake.bb = 0 : ui32} : _ to <i32>
  %b = br %f#0 {handshake.bb = 0 : ui32} : <>
  %r1 = bundle %b, %d1 {handshake.bb = 1 : ui32} : _ to <i32>
  %e = br %f#1 {handshake.bb = 0 : ui32} : <>
  end {handshake.bb = 1 : ui32} %r0, %r1, %e : <i32>, <i32>, <>
}
