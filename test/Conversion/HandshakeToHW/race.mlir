// RUN: dynamatic-opt %s --lower-handshake-to-hw | FileCheck %s

// A race lowers to an instance of an extern module named by its kind, its
// inputs `tokens_<i>` then `flags_<i>` -- indexed even when there is one, the
// arrays `tokens` and `flags` of its RTL -- and its structure in the
// parameters: the inputs of each kind, the decision's type, and the
// candidates as the generators read them (RaceOp::getCandidatesEncoding).
// Two races of one structure share a module; another structure is another.

// CHECK-LABEL: hw.module @rc(
// CHECK: hw.instance "race0" @handshake_race_0(tokens_0: %{{.*}}: !handshake.channel<i3>, flags_0: %{{.*}}: !handshake.channel<i1>, flags_1: %{{.*}}: !handshake.channel<i1>, flags_2: %{{.*}}: !handshake.channel<i1>, clk: %{{.*}}: i1, rst: %{{.*}}: i1) -> (outs: !handshake.channel<i3>)
// CHECK: hw.instance "race1" @handshake_race_0(
// CHECK: hw.instance "race2" @handshake_race_1(flags_0: %{{.*}}: !handshake.channel<i1>, flags_1: %{{.*}}: !handshake.channel<i1>, clk: %{{.*}}: i1, rst: %{{.*}}: i1) -> (outs: !handshake.channel<i3>)
// CHECK-DAG: hw.module.extern @handshake_race_0({{.*}}) attributes {hw.name = "handshake.race", hw.parameters = {CANDIDATES = "t0/p2:f0:u1/p4:f2:a0,1", DATA_TYPE = !handshake.channel<i3>, SIZE_FLAGS = 3 : ui32, SIZE_TOKENS = 1 : ui32}}
// CHECK-DAG: hw.module.extern @handshake_race_1({{.*}}) attributes {hw.name = "handshake.race", hw.parameters = {CANDIDATES = "p1:f0/p2:f1:a0", DATA_TYPE = !handshake.channel<i3>, SIZE_FLAGS = 2 : ui32, SIZE_TOKENS = 0 : ui32}}
handshake.func @rc(%t: !handshake.channel<i3>, %a: !handshake.channel<i1>,
                   %b: !handshake.channel<i1>, %c: !handshake.channel<i1>,
                   %u: !handshake.channel<i3>, %d: !handshake.channel<i1>,
                   %e: !handshake.channel<i1>, %f: !handshake.channel<i1>,
                   %g: !handshake.channel<i1>, %h: !handshake.channel<i1>, ...)
    -> (!handshake.channel<i3>, !handshake.channel<i3>, !handshake.channel<i3>)
    attributes {argNames = ["t", "a", "b", "c", "u", "d", "e", "f", "g", "h"],
                resNames = ["out0", "out1", "out2"]} {
  %0 = race [%t] [%a, %b, %c] {candidates = [
         {token = 0 : i64},
         {payload = 2 : ui3, flags = array<i64: 0>, unless = array<i64: 1>},
         {payload = 4 : ui3, flags = array<i64: 2>, after = array<i64: 0, 1>}
       ]} : <i3>
  %1 = race [%u] [%d, %e, %f] {candidates = [
         {token = 0 : i64},
         {payload = 2 : ui3, flags = array<i64: 0>, unless = array<i64: 1>},
         {payload = 4 : ui3, flags = array<i64: 2>, after = array<i64: 0, 1>}
       ]} : <i3>
  %2 = race [] [%g, %h] {candidates = [
         {payload = 1 : ui3, flags = array<i64: 0>},
         {payload = 2 : ui3, flags = array<i64: 1>, after = array<i64: 0>}
       ]} : <i3>
  end %0, %1, %2 : <i3>, <i3>, <i3>
}
