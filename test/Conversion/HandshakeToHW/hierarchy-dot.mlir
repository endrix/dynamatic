// RUN: export-dot %s --function top | FileCheck %s
// RUN: not export-dot %s 2>&1 | FileCheck %s --check-prefix=AMBIGUOUS

// A DOT graph draws one function, so once a module holds several -- which it
// does as soon as a design is a hierarchy rather than one flat entity -- which
// one to draw has to be said. Naming none is an error that lists the choices
// rather than a guess.

// AMBIGUOUS: the module holds 2 Handshake functions; name the one to export with --function. Available: doubler top

// The instance is a node like any other. It does not implement
// NamedIOInterface -- its ports are the callee's -- and asking it for port
// names by interface used to abort, so the edges fall back to positions.
// CHECK: "instance0" [{{.*}}"mlir_op"="handshake.instance"{{.*}}]
// CHECK: "in0" -> "instance0"

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
