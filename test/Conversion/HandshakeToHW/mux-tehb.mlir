// RUN: dynamatic-opt %s --lower-handshake-to-hw --split-input-file | FileCheck %s

// The slot behind a mux's select (`TEHB`). A mux keeps it unless the op's
// hw.parameters say 0: a consumer that cuts ready itself, the queue an
// actor's output port pushes into, needs no second one. The parameter
// reaches the generator either way, in the unsigned encoding.

// CHECK-LABEL: hw.module @kept(
// CHECK:         hw.module.extern @handshake_mux_0({{.*}}TEHB = 1 : ui32
handshake.func @kept(%s: !handshake.channel<i1>, %a: !handshake.channel<i10>, %b: !handshake.channel<i10>) -> !handshake.channel<i10>
    attributes {argNames = ["sel", "in0", "in1"], resNames = ["out0"]} {
  %m = mux %s [%a, %b] : <i1>, [<i10>, <i10>] to <i10>
  end %m : <i10>
}

// -----

// CHECK-LABEL: hw.module @dropped(
// CHECK:         hw.module.extern @handshake_mux_0({{.*}}TEHB = 0 : ui32
handshake.func @dropped(%s: !handshake.channel<i1>, %a: !handshake.channel<i10>, %b: !handshake.channel<i10>) -> !handshake.channel<i10>
    attributes {argNames = ["sel", "in0", "in1"], resNames = ["out0"]} {
  %m = mux %s [%a, %b] {hw.parameters = {TEHB = 0 : i64}} : <i1>, [<i10>, <i10>] to <i10>
  end %m : <i10>
}
