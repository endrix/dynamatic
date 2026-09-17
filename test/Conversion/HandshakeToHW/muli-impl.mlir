// RUN: dynamatic-opt --lower-handshake-to-hw %s | FileCheck %s

// Which multiplier a muli lowers to, and how many multiplier bits a cycle
// the sequential one takes: the one-cycle product behind delay registers
// unless the op's hw.parameters say otherwise. Both reach the RTL config on
// every muli.

// CHECK: hw.module.extern @handshake_muli_0({{.*}}) attributes {hw.name = "handshake.muli", hw.parameters = {DATA_TYPE = !handshake.channel<i32>, IMPL = "sequential", LATENCY = 9 : ui32, STEP = 4 : ui32}}
// CHECK: hw.module.extern @handshake_muli_1({{.*}}) attributes {hw.name = "handshake.muli", hw.parameters = {DATA_TYPE = !handshake.channel<i32>, IMPL = "pipelined", LATENCY = 4 : ui32, STEP = 1 : ui32}}
handshake.func @muls(%a: !handshake.channel<i32>, %b: !handshake.channel<i32>, %c: !handshake.channel<i32>, %d: !handshake.channel<i32>, %start: !handshake.control<>, ...) -> (!handshake.channel<i32>, !handshake.channel<i32>, !handshake.control<>) attributes {argNames = ["a", "b", "c", "d", "start"], resNames = ["p0", "p1", "end"]} {
  %p0 = muli %a, %b {handshake.name = "mul0", latency = 9, hw.parameters = {IMPL = "sequential", STEP = 4 : i64}} : <i32>
  %p1 = muli %c, %d {handshake.name = "mul1", latency = 4} : <i32>
  end {handshake.name = "end0"} %p0, %p1, %start : <i32>, <i32>, <>
}
