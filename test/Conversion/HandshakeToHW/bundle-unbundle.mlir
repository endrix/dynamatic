// RUN: dynamatic-opt %s --lower-handshake-to-hw --split-input-file | FileCheck %s

// bundle/unbundle reaching hardware. They are the only way a circuit can
// OBSERVE a channel's protocol signals -- reading a channel consumes it, so
// "is a token available?" is otherwise inexpressible.

// A transparent tap: split the channel, read its valid, put it back together.
// The ready flows backwards from the bundle into the unbundle, which is a
// cycle in SSA -- legal because a handshake.func is a graph region.

// Ports are named individually, never ins_0/ins_1: the netlist printer reads
// that suffix as 2D vector packing, which would be wrong for a port list
// mixing a control with a bare signal.
// CHECK-LABEL: hw.module @tap(
// CHECK:         hw.instance "unbundle0" @handshake_unbundle_0(ins: %L
// CHECK:         hw.instance "bundle1" @handshake_bundle_1(ctrl:

// Both forms of each op share an op name but have incompatible port lists, so
// FORM has to reach the discriminator or the two would collide on a single
// external module.
// CHECK-DAG: hw.module.extern @handshake_unbundle_0(in %ins : !handshake.channel<i32>{{.*}}out ctrl : !handshake.control<>, out data : i32){{.*}}DATA_WIDTH = 32 : ui32, FORM = "channel"
// CHECK-DAG: hw.module.extern @handshake_unbundle_1(in %ins : !handshake.control<>, in %ready : i1{{.*}}out valid : i1){{.*}}DATA_WIDTH = 0 : ui32, FORM = "control"
// CHECK-DAG: hw.module.extern @handshake_bundle_0(in %valid : i1{{.*}}out ctrl : !handshake.control<>, out ready : i1){{.*}}DATA_WIDTH = 0 : ui32, FORM = "control"
// CHECK-DAG: hw.module.extern @handshake_bundle_1(in %ctrl : !handshake.control<>, in %data : i32{{.*}}out outs : !handshake.channel<i32>){{.*}}DATA_WIDTH = 32 : ui32, FORM = "channel"
handshake.func @tap(%L: !handshake.channel<i32>, ...) -> !handshake.channel<i32>
    attributes {argNames = ["L"], resNames = ["out0"]} {
  %ctrl, %data = unbundle %L : <i32> to _
  %valid = unbundle %ctrl [%ready] : <> to _
  %ctrl2, %ready = bundle %valid : _ to <>
  %out = bundle %ctrl2, %data : _ to <i32>
  end %out : <i32>
}

// -----

// A control-only channel has no data signal, so DATA_WIDTH is 0 and the
// generators emit no data port at all.
// CHECK-LABEL: hw.module @tapControl(
// CHECK-DAG: hw.module.extern @handshake_unbundle_0(in %ins : !handshake.control<>, in %ready : i1{{.*}}out valid : i1){{.*}}DATA_WIDTH = 0 : ui32, FORM = "control"
// CHECK-DAG: hw.module.extern @handshake_bundle_0(in %valid : i1{{.*}}out ctrl : !handshake.control<>, out ready : i1){{.*}}DATA_WIDTH = 0 : ui32, FORM = "control"
handshake.func @tapControl(%C: !handshake.control<>, ...) -> !handshake.control<>
    attributes {argNames = ["C"], resNames = ["out0"]} {
  %valid = unbundle %C [%ready] : <> to _
  %ctrl, %ready = bundle %valid : _ to <>
  end %ctrl : <>
}

// NOTE: `unbundle` on a channel WITH extra signals is rejected by the module
// discriminator -- each extra would need its own wire in every form, and
// dropping them silently would corrupt the channel. That path is not covered
// here: such IR does not currently survive parsing, which is a pre-existing
// UnbundleOp issue unrelated to this lowering.
