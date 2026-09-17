// RUN: dynamatic-opt --lower-handshake-to-hw %s | FileCheck %s

// Which divider a divui lowers to: the pipelined Vitis IP unless the op's
// hw.parameters name the sequential one. The parameter reaches the RTL
// config as IMPL, a string, on every divui.

// CHECK: hw.module.extern @handshake_divui_0({{.*}}) attributes {hw.name = "handshake.divui", hw.parameters = {DATA_TYPE = !handshake.channel<i32>, IMPL = "sequential", LATENCY = 35 : ui32}}
// CHECK: hw.module.extern @handshake_divui_1({{.*}}) attributes {hw.name = "handshake.divui", hw.parameters = {DATA_TYPE = !handshake.channel<i32>, IMPL = "pipelined", LATENCY = 35 : ui32}}
handshake.func @divs(%a: !handshake.channel<i32>, %b: !handshake.channel<i32>, %c: !handshake.channel<i32>, %d: !handshake.channel<i32>, %start: !handshake.control<>, ...) -> (!handshake.channel<i32>, !handshake.channel<i32>, !handshake.control<>) attributes {argNames = ["a", "b", "c", "d", "start"], resNames = ["q0", "q1", "end"]} {
  %q0 = divui %a, %b {handshake.name = "div0", latency = 35, hw.parameters = {IMPL = "sequential"}} : <i32>
  %q1 = divui %c, %d {handshake.name = "div1", latency = 35} : <i32>
  end {handshake.name = "end0"} %q0, %q1, %start : <i32>, <i32>, <>
}
