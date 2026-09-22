// RUN: dynamatic-opt --lower-handshake-to-hw %s | FileCheck %s

// Which unit a signed division and the two remainders lower to: the
// pipelined Vitis IP unless the op's hw.parameters name the sequential one,
// the iteration a sequential divui already runs. The parameter reaches the
// RTL config as IMPL, a string, on every one of them.

// CHECK: hw.module.extern @handshake_divsi_0({{.*}}) attributes {hw.name = "handshake.divsi", hw.parameters = {DATA_TYPE = !handshake.channel<i32>, IMPL = "sequential", LATENCY = 33 : ui32}}
// CHECK: hw.module.extern @handshake_divsi_1({{.*}}) attributes {hw.name = "handshake.divsi", hw.parameters = {DATA_TYPE = !handshake.channel<i32>, IMPL = "pipelined", LATENCY = 35 : ui32}}
// CHECK: hw.module.extern @handshake_remui_0({{.*}}) attributes {hw.name = "handshake.remui", hw.parameters = {DATA_TYPE = !handshake.channel<i32>, IMPL = "sequential", LATENCY = 33 : ui32}}
// CHECK: hw.module.extern @handshake_remui_1({{.*}}) attributes {hw.name = "handshake.remui", hw.parameters = {DATA_TYPE = !handshake.channel<i32>, IMPL = "pipelined", LATENCY = 35 : ui32}}
// CHECK: hw.module.extern @handshake_remsi_0({{.*}}) attributes {hw.name = "handshake.remsi", hw.parameters = {DATA_TYPE = !handshake.channel<i32>, IMPL = "sequential", LATENCY = 33 : ui32}}
// CHECK: hw.module.extern @handshake_remsi_1({{.*}}) attributes {hw.name = "handshake.remsi", hw.parameters = {DATA_TYPE = !handshake.channel<i32>, IMPL = "pipelined", LATENCY = 35 : ui32}}
handshake.func @divs(%a0: !handshake.channel<i32>, %b0: !handshake.channel<i32>, %a1: !handshake.channel<i32>, %b1: !handshake.channel<i32>, %a2: !handshake.channel<i32>, %b2: !handshake.channel<i32>, %a3: !handshake.channel<i32>, %b3: !handshake.channel<i32>, %a4: !handshake.channel<i32>, %b4: !handshake.channel<i32>, %a5: !handshake.channel<i32>, %b5: !handshake.channel<i32>, %start: !handshake.control<>, ...) -> (!handshake.channel<i32>, !handshake.channel<i32>, !handshake.channel<i32>, !handshake.channel<i32>, !handshake.channel<i32>, !handshake.channel<i32>, !handshake.control<>) attributes {argNames = ["a0", "b0", "a1", "b1", "a2", "b2", "a3", "b3", "a4", "b4", "a5", "b5", "start"], resNames = ["q0", "q1", "r0", "r1", "r2", "r3", "end"]} {
  %q0 = divsi %a0, %b0 {handshake.name = "div0", latency = 33, hw.parameters = {IMPL = "sequential"}} : <i32>
  %q1 = divsi %a1, %b1 {handshake.name = "div1", latency = 35} : <i32>
  %r0 = remui %a2, %b2 {handshake.name = "rem0", latency = 33, hw.parameters = {IMPL = "sequential"}} : <i32>
  %r1 = remui %a3, %b3 {handshake.name = "rem1", latency = 35} : <i32>
  %r2 = remsi %a4, %b4 {handshake.name = "rem2", latency = 33, hw.parameters = {IMPL = "sequential"}} : <i32>
  %r3 = remsi %a5, %b5 {handshake.name = "rem3", latency = 35} : <i32>
  end {handshake.name = "end0"} %q0, %q1, %r0, %r1, %r2, %r3, %start : <i32>, <i32>, <i32>, <i32>, <i32>, <i32>, <>
}
