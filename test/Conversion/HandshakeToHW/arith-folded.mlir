// An arith operation on raw wires that folds. The conversion driver folds an
// illegal operation before it tries a pattern, and the arith dialect
// materializes the folded result as a fresh `arith.constant`, created after the
// pass named every operation. The instance it becomes still gets a name: one
// with none exported as a signal named `_outs`, which GHDL and yosys refuse.
//
// RUN: dynamatic-opt %s --lower-handshake-to-hw --split-input-file | FileCheck %s

// CHECK-LABEL: hw.module @folded(
// CHECK-NOT:     hw.instance ""
// CHECK:         hw.instance "constant0" @arith_constant_0(
// CHECK-NOT:     hw.instance ""
// CHECK:         %[[F:.*]] = hw.instance "constant1" @arith_constant_1(clk: %clk: i1, rst: %rst: i1) -> (outs: i1)
// CHECK-NOT:     hw.instance ""
// CHECK:         hw.instance "bundle0" @handshake_bundle_0(ctrl: %unbundle0.ctrl: !handshake.control<>, data: %[[F]]: i1,
// CHECK:       hw.module.extern @arith_constant_1(in %clk : i1, in %rst : i1, out outs : i1) attributes {hw.name = "arith.constant", hw.parameters = {DATA_WIDTH = 1 : ui32, VALUE = "0"}}
handshake.func @folded(%a: !handshake.channel<i8>, %start: !handshake.control<>) -> (!handshake.channel<i1>, !handshake.control<>) attributes {argNames = ["a", "start"], resNames = ["flag", "end"]} {
  %true = arith.constant {handshake.name = "constant0"} true
  %ctrlA, %dataA = unbundle %a {handshake.name = "unbundle0"} : <i8> to _
  // true xor true: folds to a `false` no pass named
  %x = arith.xori %true, %true {handshake.name = "xori0"} : i1
  %out = bundle %ctrlA, %x {handshake.name = "bundle0"} : _ to <i1>
  end {handshake.name = "end0"} %out, %start : <i1>, <>
}

// -----

// Several folds in one function, the IDCT's shape among them: an extsi of a
// constant folds to a wider constant. Every folded constant gets a name of
// its own, and none takes a name already given: "constant1" is a bundle
// here and "constant2" a constant, so the folds land on constant3 and
// constant4.
// CHECK-LABEL: hw.module @several(
// CHECK-NOT:     hw.instance ""
// CHECK:         hw.instance "constant0" @arith_constant_0(
// CHECK:         hw.instance "constant2" @arith_constant_1(
// CHECK-NOT:     hw.instance ""
// CHECK:         %[[X:.*]] = hw.instance "constant3" @arith_constant_2(clk: %clk: i1, rst: %rst: i1) -> (outs: i1)
// CHECK:         hw.instance "extui0" @arith_extui_0(ins: %[[X]]: i1,
// CHECK:         %[[S:.*]] = hw.instance "constant4" @arith_constant_3(clk: %clk: i1, rst: %rst: i1) -> (outs: i8)
// CHECK-NOT:     hw.instance ""
// CHECK:         hw.instance "xori1" @arith_xori_0(lhs: %{{.*}}: i8, rhs: %[[S]]: i8,
// CHECK:         hw.instance "constant1" @handshake_bundle_0(
// CHECK-DAG:   hw.module.extern @arith_constant_2(in %clk : i1, in %rst : i1, out outs : i1) attributes {hw.name = "arith.constant", hw.parameters = {DATA_WIDTH = 1 : ui32, VALUE = "0"}}
// CHECK-DAG:   hw.module.extern @arith_constant_3(in %clk : i1, in %rst : i1, out outs : i8) attributes {hw.name = "arith.constant", hw.parameters = {DATA_WIDTH = 8 : ui32, VALUE = "00000101"}}
handshake.func @several(%a: !handshake.channel<i8>, %start: !handshake.control<>) -> (!handshake.channel<i8>, !handshake.control<>) attributes {argNames = ["a", "start"], resNames = ["r", "end"]} {
  %true = arith.constant {handshake.name = "constant0"} true
  %c5 = arith.constant {handshake.name = "constant2"} 5 : i4
  %ctrlA, %dataA = unbundle %a {handshake.name = "unbundle0"} : <i8> to _
  %x = arith.xori %true, %true {handshake.name = "xori0"} : i1
  %e = arith.extui %x {handshake.name = "extui0"} : i1 to i8
  %s = arith.extsi %c5 {handshake.name = "extsi0"} : i4 to i8
  %o0 = arith.ori %dataA, %e {handshake.name = "ori0"} : i8
  %o1 = arith.xori %o0, %s {handshake.name = "xori1"} : i8
  %out = bundle %ctrlA, %o1 {handshake.name = "constant1"} : _ to <i8>
  end {handshake.name = "end0"} %out, %start : <i8>, <>
}
