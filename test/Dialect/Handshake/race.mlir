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

// A guard over P and not P (formation shares one flag between the two
// predicates): its candidate lists flag 0 both in `flags` and in `unless`.
// It is never enabled and is refused once the flag arrives -- the nest's
// guard that can never pass -- so the second candidate, after it, waits for
// that flag.
// CHECK-LABEL: handshake.func @dead
// CHECK: race [] [%arg0, %arg1] {candidates = [{flags = array<i64: 0>, payload = 1 : ui2, unless = array<i64: 0>}, {after = array<i64: 0>, flags = array<i64: 1>, payload = 2 : ui2}]} : <i2>
handshake.func @dead(%a: !handshake.channel<i1>, %b: !handshake.channel<i1>, ...)
    -> !handshake.channel<i2>
    attributes {argNames = ["a", "b"], resNames = ["out0"]} {
  %0 = race [] [%a, %b] {candidates = [
         {payload = 1 : ui2, flags = array<i64: 0>, unless = array<i64: 0>},
         {payload = 2 : ui2, flags = array<i64: 1>, after = array<i64: 0>}
       ]} : <i2>
  end %0 : <i2>
}

// A token's index is read unsigned, whatever the attribute's type: `1 : ui1`
// (the sign bit of its own type set) is token input 1.
// CHECK-LABEL: handshake.func @narrow
// CHECK: race [%arg0, %arg1] [%arg2] {candidates = [{token = 0 : i64}, {after = array<i64: 0>, token = 1 : ui1}, {after = array<i64: 0, 1>, flags = array<i64: 0>, payload = 1 : ui2}]} : <i2>
handshake.func @narrow(%t: !handshake.channel<i2>, %u: !handshake.channel<i2>,
                       %a: !handshake.channel<i1>, ...)
    -> !handshake.channel<i2>
    attributes {argNames = ["t", "u", "a"], resNames = ["out0"]} {
  %0 = race [%t, %u] [%a] {candidates = [
         {token = 0 : i64},
         {token = 1 : ui1, after = array<i64: 0>},
         {payload = 1 : ui2, flags = array<i64: 0>, after = array<i64: 0, 1>}
       ]} : <i2>
  end %0 : <i2>
}

// ALTERNATIVES: F(P(h, S), P(k, S)) with S = P(t, g(a)) taken in once for
// each place that reads it (a shared subtree). The token t is read by two
// candidates (1 after h, 4 after k) and g's payload 1 is two (2 after h and
// t, 5 after k and t): S's answer wins once h or k is refused. Candidates of
// one answer differ in `after`.
// CHECK-LABEL: handshake.func @alternatives
// CHECK: race [%arg0] [%arg1, %arg2, %arg3, %arg4] {candidates = [{flags = array<i64: 1>, payload = 16 : ui5, unless = array<i64: 2>}, {after = array<i64: 0>, token = 0 : i64}, {after = array<i64: 0, 1>, flags = array<i64: 0>, payload = 1 : ui5}, {flags = array<i64: 2, 3>, payload = 2 : ui5}, {after = array<i64: 3>, token = 0 : i64}, {after = array<i64: 3, 4>, flags = array<i64: 0>, payload = 1 : ui5}]} : <i5>
handshake.func @alternatives(%t: !handshake.channel<i5>, %a: !handshake.channel<i1>,
                             %b: !handshake.channel<i1>, %c: !handshake.channel<i1>,
                             %d: !handshake.channel<i1>, ...)
    -> !handshake.channel<i5>
    attributes {argNames = ["t", "a", "b", "c", "d"], resNames = ["out0"]} {
  %0 = race [%t] [%a, %b, %c, %d] {candidates = [
         {payload = 16 : ui5, flags = array<i64: 1>, unless = array<i64: 2>},
         {token = 0 : i64, after = array<i64: 0>},
         {payload = 1 : ui5, flags = array<i64: 0>, after = array<i64: 0, 1>},
         {payload = 2 : ui5, flags = array<i64: 2, 3>},
         {token = 0 : i64, after = array<i64: 3>},
         {payload = 1 : ui5, flags = array<i64: 0>, after = array<i64: 3, 4>}
       ]} : <i5>
  end %0 : <i5>
}

// Alternatives of one payload need not read the same flags: payload 1 when
// a holds, or b once c is refused. (The lowering makes them of one guard,
// but the op asks only that they differ in `after`.)
// CHECK-LABEL: handshake.func @either
// CHECK: race [] [%arg0, %arg1, %arg2] {candidates = [{flags = array<i64: 0>, payload = 1 : ui2}, {flags = array<i64: 2>, payload = 2 : ui2}, {after = array<i64: 1>, flags = array<i64: 1>, payload = 1 : ui2}]} : <i2>
handshake.func @either(%a: !handshake.channel<i1>, %b: !handshake.channel<i1>,
                       %c: !handshake.channel<i1>, ...)
    -> !handshake.channel<i2>
    attributes {argNames = ["a", "b", "c"], resNames = ["out0"]} {
  %0 = race [] [%a, %b, %c] {candidates = [
         {payload = 1 : ui2, flags = array<i64: 0>},
         {payload = 2 : ui2, flags = array<i64: 2>},
         {payload = 1 : ui2, flags = array<i64: 1>, after = array<i64: 1>}
       ]} : <i2>
  end %0 : <i2>
}
