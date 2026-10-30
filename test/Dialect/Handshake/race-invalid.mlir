// RUN: dynamatic-opt %s --split-input-file --verify-diagnostics

// What handshake.race refuses. Each case breaks one rule of its verifier
// (RaceOp::verify): the decision is an integer payload with nothing beside
// it; tokens are of its type and flags one bit; a candidate is a payload or
// a token, never both and never neither, reads inputs that exist and at
// least one, and its predecessors are a strict partial order written out in
// full; a token input is one candidate and a flag input read by one.

// A dataless race would decide nothing: zero is "nothing selected" (its
// result is a channel by its type).
handshake.func @dataless(%a: !handshake.channel<i1>, ...) -> !handshake.control<>
    attributes {argNames = ["a"], resNames = ["out0"]} {
  // expected-error @below {{result #0 must be a dataflow channel}}
  %0 = "handshake.race"(%a) {operandSegmentSizes = array<i32: 0, 1>, candidates = [{payload = 1 : ui1, flags = array<i64: 0>}]} : (!handshake.channel<i1>) -> !handshake.control<>
  end %0 : <>
}

// -----

handshake.func @float(%a: !handshake.channel<i1>, ...) -> !handshake.channel<f32>
    attributes {argNames = ["a"], resNames = ["out0"]} {
  // expected-error @below {{the payload is an integer, not 'f32'}}
  %0 = "handshake.race"(%a) {operandSegmentSizes = array<i32: 0, 1>, candidates = [{payload = 1 : ui2, flags = array<i64: 0>}]} : (!handshake.channel<i1>) -> !handshake.channel<f32>
  end %0 : <f32>
}

// -----

handshake.func @extras(%a: !handshake.channel<i1>, ...) -> !handshake.channel<i2, [e: i1]>
    attributes {argNames = ["a"], resNames = ["out0"]} {
  // expected-error @below {{holds payloads alone}}
  %0 = "handshake.race"(%a) {operandSegmentSizes = array<i32: 0, 1>, candidates = [{payload = 1 : ui2, flags = array<i64: 0>}]} : (!handshake.channel<i1>) -> !handshake.channel<i2, [e: i1]>
  end %0 : <i2, [e: i1]>
}

// -----

handshake.func @tokenwidth(%t: !handshake.channel<i3>, %a: !handshake.channel<i1>, ...) -> !handshake.channel<i2>
    attributes {argNames = ["t", "a"], resNames = ["out0"]} {
  // expected-error @below {{takes tokens of its result's type}}
  %0 = "handshake.race"(%t, %a) {operandSegmentSizes = array<i32: 1, 1>, candidates = [{token = 0 : i64}, {payload = 1 : ui2, flags = array<i64: 0>}]} : (!handshake.channel<i3>, !handshake.channel<i1>) -> !handshake.channel<i2>
  end %0 : <i2>
}

// -----

handshake.func @flagwidth(%a: !handshake.channel<i2>, ...) -> !handshake.channel<i2>
    attributes {argNames = ["a"], resNames = ["out0"]} {
  // expected-error @below {{takes flags of type}}
  %0 = "handshake.race"(%a) {operandSegmentSizes = array<i32: 0, 1>, candidates = [{payload = 1 : ui2, flags = array<i64: 0>}]} : (!handshake.channel<i2>) -> !handshake.channel<i2>
  end %0 : <i2>
}

// -----

handshake.func @zero(%a: !handshake.channel<i1>, ...) -> !handshake.channel<i2>
    attributes {argNames = ["a"], resNames = ["out0"]} {
  // expected-error @below {{payload is zero, the reserved 'nothing selected'}}
  %0 = race [] [%a] {candidates = [{payload = 0 : ui2, flags = array<i64: 0>}]} : <i2>
  end %0 : <i2>
}

// -----

handshake.func @wide(%a: !handshake.channel<i1>, ...) -> !handshake.channel<i2>
    attributes {argNames = ["a"], resNames = ["out0"]} {
  // expected-error @below {{payload 4 does not fit the result's 2 bits}}
  %0 = race [] [%a] {candidates = [{payload = 4 : ui3, flags = array<i64: 0>}]} : <i2>
  end %0 : <i2>
}

// -----

handshake.func @both(%t: !handshake.channel<i2>, %a: !handshake.channel<i1>, ...) -> !handshake.channel<i2>
    attributes {argNames = ["t", "a"], resNames = ["out0"]} {
  // expected-error @below {{exactly one of a payload and a token}}
  %0 = race [%t] [%a] {candidates = [{token = 0 : i64, payload = 1 : ui2}, {payload = 2 : ui2, flags = array<i64: 0>}]} : <i2>
  end %0 : <i2>
}

// -----

handshake.func @neither(%a: !handshake.channel<i1>, ...) -> !handshake.channel<i2>
    attributes {argNames = ["a"], resNames = ["out0"]} {
  // expected-error @below {{exactly one of a payload and a token}}
  %0 = race [] [%a] {candidates = [{flags = array<i64: 0>}]} : <i2>
  end %0 : <i2>
}

// -----

handshake.func @field(%a: !handshake.channel<i1>, ...) -> !handshake.channel<i2>
    attributes {argNames = ["a"], resNames = ["out0"]} {
  // expected-error @below {{has a field 'before'}}
  %0 = race [] [%a] {candidates = [{payload = 1 : ui2, flags = array<i64: 0>, before = array<i64>}]} : <i2>
  end %0 : <i2>
}

// -----

handshake.func @twice(%a: !handshake.channel<i1>, %b: !handshake.channel<i1>, ...) -> !handshake.channel<i2>
    attributes {argNames = ["a", "b"], resNames = ["out0"]} {
  // expected-error @below {{candidate 1's payload 1 is another candidate's}}
  %0 = race [] [%a, %b] {candidates = [{payload = 1 : ui2, flags = array<i64: 0>}, {payload = 1 : ui2, flags = array<i64: 1>}]} : <i2>
  end %0 : <i2>
}

// -----

handshake.func @noflag(%a: !handshake.channel<i1>, ...) -> !handshake.channel<i2>
    attributes {argNames = ["a"], resNames = ["out0"]} {
  // expected-error @below {{candidate 0 reads flag 1 of 1}}
  %0 = race [] [%a] {candidates = [{payload = 1 : ui2, flags = array<i64: 1>}]} : <i2>
  end %0 : <i2>
}

// -----

handshake.func @contradiction(%a: !handshake.channel<i1>, ...) -> !handshake.channel<i2>
    attributes {argNames = ["a"], resNames = ["out0"]} {
  // expected-error @below {{requires flag 0 both true and false}}
  %0 = race [] [%a] {candidates = [{payload = 1 : ui2, flags = array<i64: 0>, unless = array<i64: 0>}]} : <i2>
  end %0 : <i2>
}

// -----

handshake.func @unconditional(%a: !handshake.channel<i1>, ...) -> !handshake.channel<i2>
    attributes {argNames = ["a"], resNames = ["out0"]} {
  // expected-error @below {{candidate 1 reads no input}}
  %0 = race [] [%a] {candidates = [{payload = 1 : ui2, flags = array<i64: 0>}, {payload = 2 : ui2, after = array<i64: 0>}]} : <i2>
  end %0 : <i2>
}

// -----

handshake.func @notoken(%t: !handshake.channel<i2>, %a: !handshake.channel<i1>, ...) -> !handshake.channel<i2>
    attributes {argNames = ["t", "a"], resNames = ["out0"]} {
  // expected-error @below {{candidate 0 is token 1 of 1}}
  %0 = race [%t] [%a] {candidates = [{token = 1 : i64}, {payload = 1 : ui2, flags = array<i64: 0>}]} : <i2>
  end %0 : <i2>
}

// -----

handshake.func @tokentwice(%t: !handshake.channel<i2>, %a: !handshake.channel<i1>, ...) -> !handshake.channel<i2>
    attributes {argNames = ["t", "a"], resNames = ["out0"]} {
  // expected-error @below {{token 0 is 2 candidates}}
  %0 = race [%t] [%a] {candidates = [{token = 0 : i64}, {token = 0 : i64, flags = array<i64: 0>}]} : <i2>
  end %0 : <i2>
}

// -----

handshake.func @tokenunread(%t: !handshake.channel<i2>, %a: !handshake.channel<i1>, ...) -> !handshake.channel<i2>
    attributes {argNames = ["t", "a"], resNames = ["out0"]} {
  // expected-error @below {{token 0 is 0 candidates}}
  %0 = race [%t] [%a] {candidates = [{payload = 1 : ui2, flags = array<i64: 0>}]} : <i2>
  end %0 : <i2>
}

// -----

handshake.func @flagunread(%a: !handshake.channel<i1>, %b: !handshake.channel<i1>, ...) -> !handshake.channel<i2>
    attributes {argNames = ["a", "b"], resNames = ["out0"]} {
  // expected-error @below {{flag 1 is read by no candidate}}
  %0 = race [] [%a, %b] {candidates = [{payload = 1 : ui2, flags = array<i64: 0>}]} : <i2>
  end %0 : <i2>
}

// -----

handshake.func @self(%a: !handshake.channel<i1>, ...) -> !handshake.channel<i2>
    attributes {argNames = ["a"], resNames = ["out0"]} {
  // expected-error @below {{candidate 0 is after itself}}
  %0 = race [] [%a] {candidates = [{payload = 1 : ui2, flags = array<i64: 0>, after = array<i64: 0>}]} : <i2>
  end %0 : <i2>
}

// -----

handshake.func @outside(%a: !handshake.channel<i1>, ...) -> !handshake.channel<i2>
    attributes {argNames = ["a"], resNames = ["out0"]} {
  // expected-error @below {{candidate 0 is after candidate 2 of 1}}
  %0 = race [] [%a] {candidates = [{payload = 1 : ui2, flags = array<i64: 0>, after = array<i64: 2>}]} : <i2>
  end %0 : <i2>
}

// -----

// P(a, P(b, c)): c is after b and, through it, after a.
handshake.func @transitive(%a: !handshake.channel<i1>, %b: !handshake.channel<i1>, %c: !handshake.channel<i1>, ...) -> !handshake.channel<i3>
    attributes {argNames = ["a", "b", "c"], resNames = ["out0"]} {
  // expected-error @below {{candidate 2 is after candidate 1, which is after candidate 0, but candidate 2 is not after 0}}
  %0 = race [] [%a, %b, %c] {candidates = [{payload = 1 : ui3, flags = array<i64: 0>}, {payload = 2 : ui3, flags = array<i64: 1>, after = array<i64: 0>}, {payload = 4 : ui3, flags = array<i64: 2>, after = array<i64: 1>}]} : <i3>
  end %0 : <i3>
}

// -----

// Two candidates each after the other: a cycle, which the closure puts each
// after itself.
handshake.func @cycle(%a: !handshake.channel<i1>, %b: !handshake.channel<i1>, ...) -> !handshake.channel<i2>
    attributes {argNames = ["a", "b"], resNames = ["out0"]} {
  // expected-error @below {{candidate 0 is after candidate 1, which is after candidate 0, but candidate 0 is not after 0}}
  %0 = race [] [%a, %b] {candidates = [{payload = 1 : ui2, flags = array<i64: 0>, after = array<i64: 1>}, {payload = 2 : ui2, flags = array<i64: 1>, after = array<i64: 0>}]} : <i2>
  end %0 : <i2>
}

// -----

handshake.func @wire(%t: !handshake.channel<i2>, ...) -> !handshake.channel<i2>
    attributes {argNames = ["t"], resNames = ["out0"]} {
  // expected-error @below {{is one token and nothing else: a wire}}
  %0 = race [%t] [] {candidates = [{token = 0 : i64}]} : <i2>
  end %0 : <i2>
}

// -----

handshake.func @empty(%a: !handshake.channel<i1>, ...) -> !handshake.channel<i2>
    attributes {argNames = ["a"], resNames = ["out0"]} {
  // expected-error @below {{has no candidate}}
  %0 = race [] [%a] {candidates = []} : <i2>
  end %0 : <i2>
}
