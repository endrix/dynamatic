// RUN: dynamatic-opt %s --split-input-file --verify-diagnostics

// The commit passes the payload alone.
handshake.func @commit_extras(%d: !handshake.channel<i2, [e: i1]>, ...)
    -> !handshake.channel<i2, [e: i1]>
    attributes {argNames = ["d"], resNames = ["out0"]} {
  // expected-error @below {{passes its payload alone}}
  %out, %kill = commit %d : <i2, [e: i1]>
  end %out : <i2, [e: i1]>
}

// -----

// A stand-in answers zero: a dataless one would send a token nobody asked for.
handshake.func @stand_in_dataless(%d: !handshake.channel<i3>, %c: !handshake.control<>, ...)
    -> (!handshake.channel<i3>, !handshake.control<>)
    attributes {argNames = ["d", "c"], resNames = ["out0", "out1"]} {
  %out, %kill = commit %d : <i3>
  // expected-error @below {{answers zero for a stopped producer}}
  %0 = stand_in %c, %kill : <>
  end %out, %0 : <i3>, <>
}

// -----

// ... the zero of an integer.
handshake.func @stand_in_float(%d: !handshake.channel<i3>, %f: !handshake.channel<f32>, ...)
    -> (!handshake.channel<i3>, !handshake.channel<f32>)
    attributes {argNames = ["d", "f"], resNames = ["out0", "out1"]} {
  %out, %kill = commit %d : <i3>
  // expected-error @below {{answers the zero of an integer, not of 'f32'}}
  %0 = stand_in %f, %kill : <f32>
  end %out, %0 : <i3>, <f32>
}

// -----

// ... with the payload alone.
handshake.func @stand_in_extras(%d: !handshake.channel<i3>, %f: !handshake.channel<i1, [e: i1]>, ...)
    -> (!handshake.channel<i3>, !handshake.channel<i1, [e: i1]>)
    attributes {argNames = ["d", "f"], resNames = ["out0", "out1"]} {
  %out, %kill = commit %d : <i3>
  // expected-error @below {{passes its payload alone}}
  %0 = stand_in %f, %kill : <i1, [e: i1]>
  end %out, %0 : <i3>, <i1, [e: i1]>
}

// -----

// A stand-in is told when its producer was stopped: at least one kill.
handshake.func @stand_in_no_kill(%d: !handshake.channel<i3>, %f: !handshake.channel<i1>, ...)
    -> (!handshake.channel<i3>, !handshake.channel<i1>)
    attributes {argNames = ["d", "f"], resNames = ["out0", "out1"]} {
  %out, %kill = commit %d : <i3>
  // expected-error @below {{answers for a producer a commit stops, so it takes at least one kill (a commit's); it takes none}}
  %0 = stand_in %f, : <i1>
  end %out, %0 : <i3>, <i1>
}

// -----

// ... in the generic form as well.
handshake.func @stand_in_no_kill_generic(%d: !handshake.channel<i3>, %f: !handshake.channel<i1>, ...)
    -> (!handshake.channel<i3>, !handshake.channel<i1>)
    attributes {argNames = ["d", "f"], resNames = ["out0", "out1"]} {
  %out, %kill = commit %d : <i3>
  // expected-error @below {{takes at least one kill}}
  %0 = "handshake.stand_in"(%f) : (!handshake.channel<i1>) -> !handshake.channel<i1>
  end %out, %0 : <i3>, <i1>
}
