// RUN: dynamatic-opt %s --lower-handshake-to-hw --split-input-file | FileCheck %s

// A module with no function to lower. The pass took the context of its
// first non-external function to build its patterns, so with none it read a
// null one and crashed. An external function still becomes an external
// module; an empty module stays empty.

// CHECK-LABEL: {{^}}module {
// CHECK:         hw.module.extern @ext(in %a : !handshake.channel<i32>, in %start : !handshake.control<>
// CHECK-NOT:     hw.module @
handshake.func private @ext(%a: !handshake.channel<i32>, %start: !handshake.control<>) -> (!handshake.channel<i32>, !handshake.control<>) attributes {argNames = ["a", "start"], resNames = ["out0", "end"]}

// -----

// CHECK-LABEL: {{^}}module {
// CHECK-NOT:     hw.module
module {
}
