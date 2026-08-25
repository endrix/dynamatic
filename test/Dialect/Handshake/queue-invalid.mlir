// RUN: dynamatic-opt %s --split-input-file --verify-diagnostics

// A queue passes tokens through unchanged; only the occupancy signals differ
// between its two sides.
handshake.func @dataMismatch(%src: !handshake.channel<i32>, ...)
    -> !handshake.channel<i16>
    attributes {argNames = ["src"], resNames = ["out0"]} {
  // expected-error @below {{passes tokens through unchanged}}
  %out = handshake.queue %src {numSlots = 4 : i64}
    : !handshake.channel<i32> to !handshake.channel<i16>
  end %out : <i16>
}

// -----

// The count runs 0..numSlots INCLUSIVE, so four slots need three bits, not two.
handshake.func @tooNarrow(%src: !handshake.channel<i32>, ...)
    -> !handshake.channel<i32, [size: i2]>
    attributes {argNames = ["src"], resNames = ["out0"]} {
  // expected-error @below {{'size' counts from 0 to 4 inclusive, which needs 3 bits, but it is 2 wide}}
  %out = handshake.queue %src {numSlots = 4 : i64}
    : !handshake.channel<i32> to !handshake.channel<i32, [size: i2]>
  end %out : <i32, [size: i2]>
}

// -----

// The two are published in opposite directions -- `size` to whoever reads from
// the queue, `space` back to whoever writes -- so a signal on the wrong side
// is a mistake rather than an unrelated signal sharing a name.
handshake.func @wrongSide(%src: !handshake.channel<i32, [size: i3]>, ...)
    -> !handshake.channel<i32>
    attributes {argNames = ["src"], resNames = ["out0"]} {
  // expected-error @below {{'size' belongs on the output channel and 'space' on the input channel}}
  %out = handshake.queue %src {numSlots = 4 : i64}
    : !handshake.channel<i32, [size: i3]> to !handshake.channel<i32>
  end %out : <i32>
}
