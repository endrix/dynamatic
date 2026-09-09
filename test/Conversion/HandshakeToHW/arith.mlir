// arith on raw wires: the logic a handshake function holds between an
// unbundle and a bundle. Each operation becomes an instance of a unit of the
// same name whose ports carry the wires and nothing else, parameterized by
// width, plus a comparison's predicate and a constant's value. Two operations
// of one shape share one external module.
//
// RUN: dynamatic-opt %s --lower-handshake-to-hw | FileCheck %s

// CHECK-LABEL: hw.module @raw(
// CHECK:  %[[C3:.*]] = hw.instance "constant0" @arith_constant_0(clk: %clk: i1, rst: %rst: i1) -> (outs: i8)
// CHECK:  %[[C5:.*]] = hw.instance "constant1" @arith_constant_1(clk: %clk: i1, rst: %rst: i1) -> (outs: i8)
// CHECK:  hw.instance "unbundle0"
// CHECK:  hw.instance "unbundle1"
// CHECK:  %[[EQ:.*]] = hw.instance "cmpi0" @arith_cmpi_0(lhs: %unbundle0.data: i8, rhs: %[[C3]]: i8, clk: %clk: i1, rst: %rst: i1) -> (result: i1)
// CHECK:  %[[SEL:.*]] = hw.instance "select0" @arith_select_0(condition: %[[EQ]]: i1, true_value: %unbundle1.data: i8, false_value: %unbundle0.data: i8, clk: %clk: i1, rst: %rst: i1) -> (result: i8)
// CHECK:  %[[LT:.*]] = hw.instance "cmpi1" @arith_cmpi_1(lhs: %[[SEL]]: i8, rhs: %[[C5]]: i8, clk: %clk: i1, rst: %rst: i1) -> (result: i1)
// CHECK:  %[[WIDE:.*]] = hw.instance "extui0" @arith_extui_0(ins: %[[LT]]: i1, clk: %clk: i1, rst: %rst: i1) -> (outs: i8)
// CHECK:  %[[AND:.*]] = hw.instance "andi0" @arith_andi_0(lhs: %[[WIDE]]: i8, rhs: %[[SEL]]: i8, clk: %clk: i1, rst: %rst: i1) -> (result: i8)
// CHECK:  %[[BIT:.*]] = hw.instance "trunci0" @arith_trunci_0(ins: %[[AND]]: i8, clk: %clk: i1, rst: %rst: i1) -> (outs: i1)
// CHECK:  hw.instance "join0"
// CHECK:  hw.instance "bundle0" @handshake_bundle_0(ctrl: %join0.outs: !handshake.control<>, data: %[[BIT]]: i1,

// CHECK: hw.module.extern @arith_constant_0(in %clk : i1, in %rst : i1, out outs : i8) attributes {hw.name = "arith.constant", hw.parameters = {DATA_WIDTH = 8 : ui32, VALUE = "00000011"}}
// CHECK: hw.module.extern @arith_cmpi_0(in %lhs : i8, in %rhs : i8, in %clk : i1, in %rst : i1, out result : i1) attributes {hw.name = "arith.cmpi", hw.parameters = {DATA_WIDTH = 8 : ui32, PREDICATE = "eq"}}
// CHECK: hw.module.extern @arith_select_0(in %condition : i1, in %true_value : i8, in %false_value : i8, in %clk : i1, in %rst : i1, out result : i8) attributes {hw.name = "arith.select", hw.parameters = {DATA_WIDTH = 8 : ui32}}
// CHECK: hw.module.extern @arith_cmpi_1(in %lhs : i8, in %rhs : i8, in %clk : i1, in %rst : i1, out result : i1) attributes {hw.name = "arith.cmpi", hw.parameters = {DATA_WIDTH = 8 : ui32, PREDICATE = "ult"}}
// CHECK: hw.module.extern @arith_extui_0(in %ins : i1, in %clk : i1, in %rst : i1, out outs : i8) attributes {hw.name = "arith.extui", hw.parameters = {INPUT_WIDTH = 1 : ui32, OUTPUT_WIDTH = 8 : ui32}}
// CHECK: hw.module.extern @arith_andi_0(in %lhs : i8, in %rhs : i8, in %clk : i1, in %rst : i1, out result : i8) attributes {hw.name = "arith.andi", hw.parameters = {DATA_WIDTH = 8 : ui32}}
// CHECK: hw.module.extern @arith_trunci_0(in %ins : i8, in %clk : i1, in %rst : i1, out outs : i1) attributes {hw.name = "arith.trunci", hw.parameters = {INPUT_WIDTH = 8 : ui32, OUTPUT_WIDTH = 1 : ui32}}
handshake.func @raw(%a: !handshake.channel<i8>, %b: !handshake.channel<i8>, %start: !handshake.control<>) -> (!handshake.channel<i1>, !handshake.control<>) attributes {argNames = ["a", "b", "start"], resNames = ["flag", "end"]} {
  %c3 = arith.constant {handshake.name = "constant0"} 3 : i8
  %c5 = arith.constant {handshake.name = "constant1"} 5 : i8
  %ctrlA, %dataA = unbundle %a {handshake.name = "unbundle0"} : <i8> to _
  %ctrlB, %dataB = unbundle %b {handshake.name = "unbundle1"} : <i8> to _
  %eq = arith.cmpi eq, %dataA, %c3 {handshake.name = "cmpi0"} : i8
  %sel = arith.select %eq, %dataB, %dataA {handshake.name = "select0"} : i8
  %lt = arith.cmpi ult, %sel, %c5 {handshake.name = "cmpi1"} : i8
  %wide = arith.extui %lt {handshake.name = "extui0"} : i1 to i8
  %and = arith.andi %wide, %sel {handshake.name = "andi0"} : i8
  %bit = arith.trunci %and {handshake.name = "trunci0"} : i8 to i1
  %j = join %ctrlA, %ctrlB {handshake.name = "join0"} : <>
  %out = bundle %j, %bit {handshake.name = "bundle0"} : _ to <i1>
  end {handshake.name = "end0"} %out, %start : <i1>, <>
}
