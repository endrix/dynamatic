// RUN: dynamatic-opt %s --lower-handshake-to-hw --split-input-file | FileCheck %s

// The slot behind a merge's arbiter (`TEHB`). A merge keeps it unless the
// op's hw.parameters say 0: a consumer that cuts ready itself, an actor's
// state ring whose init is a transparent slot, needs no second one. The
// parameter reaches the generator either way, in the unsigned encoding.

// CHECK-LABEL: hw.module @kept(
// CHECK:         hw.module.extern @handshake_merge_0({{.*}}TEHB = 1 : ui32
handshake.func @kept(%a: !handshake.channel<i10>, %b: !handshake.channel<i10>) -> !handshake.channel<i10>
    attributes {argNames = ["in0", "in1"], resNames = ["out0"]} {
  %m = merge %a, %b : <i10>
  end %m : <i10>
}

// -----

// CHECK-LABEL: hw.module @dropped(
// CHECK:         hw.module.extern @handshake_merge_0({{.*}}TEHB = 0 : ui32
handshake.func @dropped(%a: !handshake.channel<i10>, %b: !handshake.channel<i10>) -> !handshake.channel<i10>
    attributes {argNames = ["in0", "in1"], resNames = ["out0"]} {
  %m = merge %a, %b {hw.parameters = {TEHB = 0 : i64}} : <i10>
  end %m : <i10>
}
