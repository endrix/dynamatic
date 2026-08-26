// RUN: dynamatic-opt %s --lower-handshake-to-hw --split-input-file | FileCheck %s

// Several non-external Handshake functions in one module, with an instance
// between them, so a design can be a HIERARCHY of generated modules rather
// than one flat one. Each function becomes its own `hw.module` and the
// `handshake.instance` becomes an `hw.instance` of it -- which is what makes
// the exported RTL a set of entities that instantiate each other, rather than
// a single entity holding every unit at once.
//
// `handshake.instance` could previously only name an EXTERNAL module: the
// conversion looked the callee up among external modules and asserted when it
// was not there, so a generated sibling could not be instantiated at all.

// CHECK-LABEL: hw.module @doubler(
// CHECK:         hw.instance {{.*}} @handshake_addi

// CHECK-LABEL: hw.module @top(
// The instance names the generated module, and its ports are the callee's own
// with clk and rst appended -- the same list, in the same order, that the
// module was built with.
// CHECK:         hw.instance "instance0" @doubler(in0: %{{.*}}, clk: %{{.*}}, rst: %{{.*}}) -> (out0: !handshake.channel<i32>)

module {
  handshake.func @doubler(%a: !handshake.channel<i32>) -> !handshake.channel<i32>
      attributes {argNames = ["in0"], resNames = ["out0"]} {
    %c = source : <>
    %k = constant %c {value = 2 : i32} : <>, <i32>
    %r = addi %a, %k : <i32>
    end %r : <i32>
  }
  handshake.func @top(%a: !handshake.channel<i32>) -> !handshake.channel<i32>
      attributes {argNames = ["in0"], resNames = ["out0"]} {
    %r = instance @doubler(%a) : (!handshake.channel<i32>) -> !handshake.channel<i32>
    end %r : <i32>
  }
}
