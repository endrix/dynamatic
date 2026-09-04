// RUN: dynamatic-opt --handshake-optimize-bitwidths --remove-operation-names %s | FileCheck %s

// A result whose only user is a sink still travels on a channel, which has to
// be at least one bit wide. The backward pass used to ask for zero bits here
// and build an `i0` channel, which the type refuses.
// CHECK-LABEL:   handshake.func @sunk(
// CHECK-NOT:       i0
// CHECK:           %[[R:.*]] = addi %{{.*}}, %{{.*}} {{.*}}: <i1>
// CHECK:           %[[W:.*]] = extui %[[R]] : <i1> to <i32>
// CHECK:           sink %[[W]] {{.*}}: <i32>
// CHECK:           end
handshake.func @sunk(%a: !handshake.channel<i32>, %b: !handshake.channel<i32>, %start: !handshake.control<>, ...) -> !handshake.control<> attributes {argNames = ["a", "b", "start"], resNames = ["end"]} {
  %r = addi %a, %b {handshake.bb = 0 : ui32} : <i32>
  sink %r {handshake.bb = 0 : ui32} : <i32>
  end {handshake.bb = 0 : ui32} %start : <>
}
