// RUN: dynamatic-opt %s --split-input-file --verify-diagnostics

// The two inputs and the answer are one vector: a priority of vectors of two
// widths would answer in neither.
handshake.func @widths(%hi: !handshake.channel<i4>, %lo: !handshake.channel<i3>, ...)
    -> !handshake.channel<i4>
    attributes {argNames = ["hi", "lo"], resNames = ["out0"]} {
  // expected-error @below {{all of {hi, lo, result} have same type}}
  %0 = "handshake.priority"(%hi, %lo) : (!handshake.channel<i4>, !handshake.channel<i3>) -> !handshake.channel<i4>
  end %0 : <i4>
}

// -----

// Zero is "nothing selected": a dataless priority would decide nothing.
handshake.func @dataless(%hi: !handshake.control<>, %lo: !handshake.control<>, ...)
    -> !handshake.control<>
    attributes {argNames = ["hi", "lo"], resNames = ["out0"]} {
  // expected-error @below {{decides on its payload}}
  %0 = priority %hi, %lo : <>
  end %0 : <>
}

// -----

// The unit holds the payload alone.
handshake.func @extras(%hi: !handshake.channel<i2, [e: i1]>, %lo: !handshake.channel<i2, [e: i1]>, ...)
    -> !handshake.channel<i2, [e: i1]>
    attributes {argNames = ["hi", "lo"], resNames = ["out0"]} {
  // expected-error @below {{holds the payload alone}}
  %0 = priority %hi, %lo : <i2, [e: i1]>
  end %0 : <i2, [e: i1]>
}
