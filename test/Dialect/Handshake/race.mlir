// RUN: dynamatic-opt %s | dynamatic-opt | FileCheck %s

// A race prints and parses back as itself: its tokens and flags in brackets,
// their types the result's and one bit, its candidates a dictionary each
// (payloads unsigned, as wide as the decision).

// P(F(t, g(a, not b)), h(c)): the settled token t, the guard g over a and not
// b, and the guard h after both.
// CHECK-LABEL: handshake.func @nest
// CHECK: %[[R:.*]] = race [%arg0] [%arg1, %arg2, %arg3] {candidates = [{token = 0 : i64}, {flags = array<i64: 0>, payload = 2 : ui3, unless = array<i64: 1>}, {after = array<i64: 0, 1>, flags = array<i64: 2>, payload = 4 : ui3}]} : <i3>
// CHECK: end %[[R]] : <i3>
handshake.func @nest(%t: !handshake.channel<i3>, %a: !handshake.channel<i1>,
                     %b: !handshake.channel<i1>, %c: !handshake.channel<i1>, ...)
    -> !handshake.channel<i3>
    attributes {argNames = ["t", "a", "b", "c"], resNames = ["out0"]} {
  %0 = race [%t] [%a, %b, %c] {candidates = [
         {token = 0 : i64},
         {payload = 2 : ui3, flags = array<i64: 0>, unless = array<i64: 1>},
         {payload = 4 : ui3, flags = array<i64: 2>, after = array<i64: 0, 1>}
       ]} : <i3>
  end %0 : <i3>
}

// No token input: two guards over flags, the second after the first.
// CHECK-LABEL: handshake.func @flags
// CHECK: race [] [%arg0, %arg1] {candidates = [{flags = array<i64: 0>, payload = 1 : ui2}, {after = array<i64: 0>, flags = array<i64: 1>, payload = 2 : ui2}]} : <i2>
handshake.func @flags(%a: !handshake.channel<i1>, %b: !handshake.channel<i1>, ...)
    -> !handshake.channel<i2>
    attributes {argNames = ["a", "b"], resNames = ["out0"]} {
  %0 = race [] [%a, %b] {candidates = [
         {payload = 1 : ui2, flags = array<i64: 0>},
         {payload = 2 : ui2, flags = array<i64: 1>, after = array<i64: 0>}
       ]} : <i2>
  end %0 : <i2>
}
