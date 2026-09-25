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

// -----

// The tokens a queue holds at reset are its contents: no more than its slots.
handshake.func @tooManyInitial(%src: !handshake.channel<i16>, ...)
    -> !handshake.channel<i16>
    attributes {argNames = ["src"], resNames = ["out0"]} {
  // expected-error @below {{holds 3 initial tokens but has 2 slots}}
  %out = handshake.queue %src {numSlots = 2 : i64, initialTokens = [1 : i16, 2 : i16, 3 : i16]}
    : !handshake.channel<i16> to !handshake.channel<i16>
  end %out : <i16>
}

// -----

// Each is of the channel's data type exactly: no conversion is guessed here.
handshake.func @initialWidth(%src: !handshake.channel<i16>, ...)
    -> !handshake.channel<i16>
    attributes {argNames = ["src"], resNames = ["out0"]} {
  // expected-error @below {{initial token #1 (7 : i32) is not an integer or float attribute of the channel's data type 'i16'}}
  %out = handshake.queue %src {numSlots = 2 : i64, initialTokens = [1 : i16, 7 : i32]}
    : !handshake.channel<i16> to !handshake.channel<i16>
  end %out : <i16>
}

// -----

handshake.func @initialKind(%src: !handshake.channel<f32>, ...)
    -> !handshake.channel<f32>
    attributes {argNames = ["src"], resNames = ["out0"]} {
  // expected-error @below {{initial token #0 ("one") is not an integer or float attribute of the channel's data type 'f32'}}
  %out = handshake.queue %src {numSlots = 2 : i64, initialTokens = ["one"]}
    : !handshake.channel<f32> to !handshake.channel<f32>
  end %out : <f32>
}
