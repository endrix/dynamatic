// RUN: dynamatic-opt %s --handshake-set-unit-impl-attr="impl=vivado timing-models=%dynamatic_src_root/data/components.json" 2>&1 | FileCheck %s

// A latency the operation already carries is its latency when its
// implementation was chosen before placement: a sequential multiplier
// (ceil(BITWIDTH / STEP) + 2 cycles a product) says so on the op, and the
// timing model's entry (4, the pipelined unit's) does not replace it. A
// unit without one gets the model's, and so does a pipelined unit carrying
// a stale latency from an earlier run: the pass is the one that writes it.

// CHECK-LABEL: handshake.func @kept(
// CHECK: muli {{.*}} {hw.parameters = {IMPL = "sequential", STEP = 4 : i64}, latency = 10 : i64} : <i32>
// CHECK: muli {{.*}} {latency = 4 : i64} : <i32>
// CHECK: muli {{.*}} {hw.parameters = {IMPL = "pipelined"}, latency = 4 : i64} : <i32>
handshake.func @kept(%a: !handshake.channel<i32>, %b: !handshake.channel<i32>, %c: !handshake.channel<i32>, %d: !handshake.channel<i32>, %e: !handshake.channel<i32>, %f: !handshake.channel<i32>, %start: !handshake.control<>) -> (!handshake.channel<i32>, !handshake.channel<i32>, !handshake.channel<i32>) {
  %p = muli %a, %b {hw.parameters = {IMPL = "sequential", STEP = 4 : i64}, latency = 10 : i64} : <i32>
  %q = muli %c, %d : <i32>
  %r = muli %e, %f {hw.parameters = {IMPL = "pipelined"}, latency = 9 : i64} : <i32>
  end %p, %q, %r : <i32>, <i32>, <i32>
}
