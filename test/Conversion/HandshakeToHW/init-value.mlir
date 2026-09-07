// RUN: dynamatic-opt %s --lower-handshake-to-hw --split-input-file | FileCheck %s

// The token an `init` holds at reset. `INIT_TOKEN` is a boolean, 0 or 1, the
// control token the unit was made for; `INIT_VALUE` is an integer, for a
// channel that starts at a value -- an actor's state variable declared
// `State[Int(10)] = 4` has its ring start at 4. Both reach the generator as
// `INITIAL_VALUE`.

// CHECK-LABEL: hw.module @value(
// CHECK:         hw.module.extern @handshake_init_0({{.*}}INITIAL_VALUE = 4 : ui32
handshake.func @value(%a: !handshake.channel<i10>) -> !handshake.channel<i10>
    attributes {argNames = ["in0"], resNames = ["out0"]} {
  %i = init %a {hw.parameters = {INIT_VALUE = 4 : i64}} : <i10>
  end %i : <i10>
}

// -----

// CHECK-LABEL: hw.module @token(
// CHECK:         hw.module.extern @handshake_init_0({{.*}}INITIAL_VALUE = 1 : ui32
handshake.func @token(%a: !handshake.channel<i1>) -> !handshake.channel<i1>
    attributes {argNames = ["in0"], resNames = ["out0"]} {
  %i = init %a {hw.parameters = {INIT_TOKEN = true}} : <i1>
  end %i : <i1>
}

// -----

// CHECK-LABEL: hw.module @none(
// CHECK:         hw.module.extern @handshake_init_0({{.*}}INITIAL_VALUE = 0 : ui32
handshake.func @none(%a: !handshake.channel<i1>) -> !handshake.channel<i1>
    attributes {argNames = ["in0"], resNames = ["out0"]} {
  %i = init %a : <i1>
  end %i : <i1>
}
