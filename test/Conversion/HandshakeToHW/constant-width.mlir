// A constant's VHDL literal is a bit string of the channel's width, whatever
// that width is. 65 bits is what the frontend's i64 * i64 -> i65 arithmetic
// produces once canonicalization folds a constant's extension into it.
//
// RUN: dynamatic-opt %s --lower-handshake-to-hw | FileCheck %s

// 4096 in 65 bits: 52 zeros, a one, 12 zeros.
// CHECK: hw.module.extern @handshake_constant_0(in %ctrl : !handshake.control<>, in %clk : i1, in %rst : i1, out outs : !handshake.channel<i65>) attributes {hw.name = "handshake.constant", hw.parameters = {DATA_WIDTH = 65 : ui32, VALUE = "00000000000000000000000000000000000000000000000000001000000000000"}}
// -1 in 65 bits, sign-extended: all ones.
// CHECK: hw.parameters = {DATA_WIDTH = 65 : ui32, VALUE = "11111111111111111111111111111111111111111111111111111111111111111"}
// And the width that always worked.
// CHECK: hw.parameters = {DATA_WIDTH = 8 : ui32, VALUE = "00101010"}
handshake.func @wide(%start: !handshake.control<>, ...) -> (!handshake.channel<i65>, !handshake.channel<i65>, !handshake.channel<i8>, !handshake.control<>) attributes {argNames = ["start"], resNames = ["a", "b", "c", "end"]} {
  %f:4 = fork [4] %start : <>
  %a = constant %f#0 {value = 4096 : i65} : <>, <i65>
  %b = constant %f#1 {value = -1 : i65} : <>, <i65>
  %c = constant %f#2 {value = 42 : i8} : <>, <i8>
  end %a, %b, %c, %f#3 : <i65>, <i65>, <i8>, <>
}
