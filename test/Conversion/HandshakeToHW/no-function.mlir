// RUN: dynamatic-opt %s --lower-handshake-to-hw --split-input-file | FileCheck %s --implicit-check-not="hw.module @" --implicit-check-not=handshake.func
// RUN: dynamatic-opt %s --lower-handshake-to-hw=instrument-ii --split-input-file | FileCheck %s --implicit-check-not="hw.module @" --implicit-check-not=handshake.func

// A module with no function to lower. The pass took the context of its
// first non-external function to build its patterns, so with none it read a
// null one and crashed. An external function still becomes an external
// module, with the clock and the reset every module is given, and nothing
// else is created (no module, no wrapper); an empty module stays empty. The
// same holds when the pass is asked to instrument loops, which it does on
// its first non-external function.

// CHECK-LABEL: {{^}}module {
// CHECK-NEXT:    hw.module.extern @ext(in %a : !handshake.channel<i32>, in %start : !handshake.control<>, in %clk : i1, in %rst : i1, out out0 : !handshake.channel<i32>, out end : !handshake.control<>) attributes {hw.name = "ext"}
// CHECK-NEXT:  }
handshake.func private @ext(%a: !handshake.channel<i32>, %start: !handshake.control<>) -> (!handshake.channel<i32>, !handshake.control<>) attributes {argNames = ["a", "start"], resNames = ["out0", "end"]}

// -----

// CHECK-LABEL: {{^}}module {
// CHECK-NEXT:  }
module {
}
