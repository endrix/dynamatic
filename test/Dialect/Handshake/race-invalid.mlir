// RUN: dynamatic-opt %s --split-input-file --verify-diagnostics

// What handshake.race refuses. Each case breaks one rule of its verifier
// (RaceOp::verify): the decision is an integer payload with nothing beside
// it; tokens are of its type and flags one bit; a candidate is a payload or
// a token, never both and never neither, reads inputs that exist and at
// least one, and its predecessors are a strict partial order written out in
// full; every input is read by a candidate, and candidates of one answer (a
// payload, or a token input) -- its alternatives -- read the same flags and
// differ in `after`.

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

// Two candidates of payload 1 over other flags (1 when a holds, or b): two
// guards of one answer, not one candidate under two sets of predecessors.
// Alternatives read the same flags (race.mlir's @alternatives, @sets).
handshake.func @twice(%a: !handshake.channel<i1>, %b: !handshake.channel<i1>, ...) -> !handshake.channel<i2>
    attributes {argNames = ["a", "b"], resNames = ["out0"]} {
  // expected-error @below {{candidates 0 and 1 are payload 1 over other flags: the alternatives of one answer read the same flags}}
  %0 = race [] [%a, %b] {candidates = [{payload = 1 : ui2, flags = array<i64: 0>}, {payload = 1 : ui2, flags = array<i64: 1>}]} : <i2>
  end %0 : <i2>
}

// -----

// The same over other flags and after other candidates (payload 1 when a
// holds, or b once c is refused): differing in `after` does not make them
// alternatives.
handshake.func @either(%a: !handshake.channel<i1>, %b: !handshake.channel<i1>, %c: !handshake.channel<i1>, ...) -> !handshake.channel<i2>
    attributes {argNames = ["a", "b", "c"], resNames = ["out0"]} {
  // expected-error @below {{candidates 0 and 2 are payload 1 over other flags}}
  %0 = race [] [%a, %b, %c] {candidates = [{payload = 1 : ui2, flags = array<i64: 0>}, {payload = 2 : ui2, flags = array<i64: 2>}, {payload = 1 : ui2, flags = array<i64: 1>, after = array<i64: 1>}]} : <i2>
  end %0 : <i2>
}

// -----

// The same flags required true, another required false: `unless` is read as
// `flags` is.
handshake.func @unlessother(%a: !handshake.channel<i1>, %b: !handshake.channel<i1>, %c: !handshake.channel<i1>, ...) -> !handshake.channel<i2>
    attributes {argNames = ["a", "b", "c"], resNames = ["out0"]} {
  // expected-error @below {{candidates 0 and 2 are payload 1 over other flags}}
  %0 = race [] [%a, %b, %c] {candidates = [{payload = 1 : ui2, flags = array<i64: 0>, unless = array<i64: 1>}, {payload = 2 : ui2, flags = array<i64: 2>}, {payload = 1 : ui2, flags = array<i64: 0>, unless = array<i64: 2>, after = array<i64: 1>}]} : <i2>
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

// A list names a flag once (the same flag in `flags` and `unless` is
// allowed: race.mlir's @dead).
handshake.func @flagtwice(%a: !handshake.channel<i1>, ...) -> !handshake.channel<i2>
    attributes {argNames = ["a"], resNames = ["out0"]} {
  // expected-error @below {{candidate 0 lists flag 0 twice in its flags}}
  %0 = race [] [%a] {candidates = [{payload = 1 : ui2, flags = array<i64: 0, 0>}]} : <i2>
  end %0 : <i2>
}

// -----

handshake.func @unlesstwice(%a: !handshake.channel<i1>, ...) -> !handshake.channel<i2>
    attributes {argNames = ["a"], resNames = ["out0"]} {
  // expected-error @below {{candidate 0 lists flag 0 twice in its unless}}
  %0 = race [] [%a] {candidates = [{payload = 1 : ui2, flags = array<i64: 0>, unless = array<i64: 0, 0>}]} : <i2>
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

// A token's index is read unsigned (race.mlir's @narrow): -1 is no input's.
handshake.func @negtoken(%t: !handshake.channel<i2>, %a: !handshake.channel<i1>, ...) -> !handshake.channel<i2>
    attributes {argNames = ["t", "a"], resNames = ["out0"]} {
  // expected-error @below {{candidate 0's token is not an input's index}}
  %0 = race [%t] [%a] {candidates = [{token = -1 : i64}, {payload = 1 : ui2, flags = array<i64: 0>}]} : <i2>
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

// A token read by two candidates over other flags (t, and t when a); read
// twice over the same flags after different candidates, it is two
// alternatives (race.mlir's @alternatives).
handshake.func @tokentwice(%t: !handshake.channel<i2>, %a: !handshake.channel<i1>, ...) -> !handshake.channel<i2>
    attributes {argNames = ["t", "a"], resNames = ["out0"]} {
  // expected-error @below {{candidates 0 and 1 are token 0 over other flags}}
  %0 = race [%t] [%a] {candidates = [{token = 0 : i64}, {token = 0 : i64, flags = array<i64: 0>}]} : <i2>
  end %0 : <i2>
}

// -----

// A token read twice over the same flags after the same candidates: one
// candidate written twice.
handshake.func @tokenduplicate(%t: !handshake.channel<i2>, %a: !handshake.channel<i1>, ...) -> !handshake.channel<i2>
    attributes {argNames = ["t", "a"], resNames = ["out0"]} {
  // expected-error @below {{candidates 1 and 2 are token 0 after the same candidates: the alternatives of one answer differ in their `after`}}
  %0 = race [%t] [%a] {candidates = [{payload = 1 : ui2, flags = array<i64: 0>}, {token = 0 : i64, after = array<i64: 0>}, {token = 0 : i64, after = array<i64: 0>}]} : <i2>
  end %0 : <i2>
}

// -----

// A TRUE DUPLICATE: S = P(t, g(a)) taken in twice under the same
// predecessors gives g's candidate twice, alike in everything; the lowering
// takes it in once.
handshake.func @duplicate(%t: !handshake.channel<i2>, %a: !handshake.channel<i1>, ...) -> !handshake.channel<i2>
    attributes {argNames = ["t", "a"], resNames = ["out0"]} {
  // expected-error @below {{candidates 1 and 2 are payload 1 after the same candidates}}
  %0 = race [%t] [%a] {candidates = [{token = 0 : i64}, {payload = 1 : ui2, flags = array<i64: 0>, after = array<i64: 0>}, {payload = 1 : ui2, flags = array<i64: 0>, after = array<i64: 0>}]} : <i2>
  end %0 : <i2>
}

// -----

// `after` is a set: the same candidates in another order are the same.
handshake.func @sameset(%a: !handshake.channel<i1>, %b: !handshake.channel<i1>, %c: !handshake.channel<i1>, ...) -> !handshake.channel<i3>
    attributes {argNames = ["a", "b", "c"], resNames = ["out0"]} {
  // expected-error @below {{candidates 2 and 3 are payload 4 after the same candidates}}
  %0 = race [] [%a, %b, %c] {candidates = [{payload = 1 : ui3, flags = array<i64: 0>}, {payload = 2 : ui3, flags = array<i64: 1>}, {payload = 4 : ui3, flags = array<i64: 2>, after = array<i64: 0, 1>}, {payload = 4 : ui3, flags = array<i64: 2>, after = array<i64: 1, 0>}]} : <i3>
  end %0 : <i3>
}

// -----

handshake.func @tokenunread(%t: !handshake.channel<i2>, %a: !handshake.channel<i1>, ...) -> !handshake.channel<i2>
    attributes {argNames = ["t", "a"], resNames = ["out0"]} {
  // expected-error @below {{token 0 is read by no candidate}}
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
