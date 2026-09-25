// RUN: dynamatic-opt %s --lower-handshake-to-hw --split-input-file | FileCheck %s

// The token an `init` holds at reset. `INIT_TOKEN` is a boolean, 0 or 1, the
// control token the unit was made for; `INIT_VALUE` is an integer, for a
// channel that starts at a value -- an actor's state variable declared
// `State[Int(10)] = 4` has its ring start at 4. Both reach the generator as
// `INITIAL_VALUE`, the value's bits at the channel's width: a negative value in
// two's complement, a 64-bit channel's whole value (a 32-bit parameter cut it).

// CHECK-LABEL: hw.module @value(
// CHECK:         hw.module.extern @handshake_init_0({{.*}}INITIAL_VALUE = 4 : ui64
handshake.func @value(%a: !handshake.channel<i10>) -> !handshake.channel<i10>
    attributes {argNames = ["in0"], resNames = ["out0"]} {
  %i = init %a {hw.parameters = {INIT_VALUE = 4 : i64}} : <i10>
  end %i : <i10>
}

// -----

// CHECK-LABEL: hw.module @token(
// CHECK:         hw.module.extern @handshake_init_0({{.*}}INITIAL_VALUE = 1 : ui64
handshake.func @token(%a: !handshake.channel<i1>) -> !handshake.channel<i1>
    attributes {argNames = ["in0"], resNames = ["out0"]} {
  %i = init %a {hw.parameters = {INIT_TOKEN = true}} : <i1>
  end %i : <i1>
}

// -----

// CHECK-LABEL: hw.module @none(
// CHECK:         hw.module.extern @handshake_init_0({{.*}}INITIAL_VALUE = 0 : ui64
handshake.func @none(%a: !handshake.channel<i1>) -> !handshake.channel<i1>
    attributes {argNames = ["in0"], resNames = ["out0"]} {
  %i = init %a : <i1>
  end %i : <i1>
}

// -----

// CHECK-LABEL: hw.module @one(
// CHECK:         hw.module.extern @handshake_init_0({{.*}}INITIAL_VALUE = 1 : ui64
handshake.func @one(%a: !handshake.channel<i8>) -> !handshake.channel<i8>
    attributes {argNames = ["in0"], resNames = ["out0"]} {
  %i = init %a {hw.parameters = {INIT_VALUE = 1 : i64}} : <i8>
  end %i : <i8>
}

// -----

// CHECK-LABEL: hw.module @negative(
// CHECK:         hw.module.extern @handshake_init_0({{.*}}INITIAL_VALUE = 255 : ui64
handshake.func @negative(%a: !handshake.channel<i8>) -> !handshake.channel<i8>
    attributes {argNames = ["in0"], resNames = ["out0"]} {
  %i = init %a {hw.parameters = {INIT_VALUE = -1 : i64}} : <i8>
  end %i : <i8>
}

// -----

// CHECK-LABEL: hw.module @wide(
// CHECK:         hw.module.extern @handshake_init_0({{.*}}INITIAL_VALUE = 1099511627781 : ui64
handshake.func @wide(%a: !handshake.channel<i64>) -> !handshake.channel<i64>
    attributes {argNames = ["in0"], resNames = ["out0"]} {
  %i = init %a {hw.parameters = {INIT_VALUE = 1099511627781 : i64}} : <i64>
  end %i : <i64>
}
