// RUN: dynamatic-opt %s --lower-handshake-to-hw --split-input-file | FileCheck %s

// handshake.queue publishes how full it is: `size` downstream on its output
// channel, `space` upstream on its input. That is what lets a consumer ask
// whether k tokens are available -- a bare `valid` is one bit and can only
// answer "is there one?".

// Occupancy is optional, so the generator is told which signals to publish
// rather than assuming both. Both share a width: they count over the same
// span, 0 to numSlots inclusive.
// CHECK-LABEL: hw.module @both(
// CHECK-DAG: hw.module.extern @handshake_queue_0(in %ins : !handshake.channel<i32, [space: i3 (U)]>{{.*}}out outs : !handshake.channel<i32, [size: i3]>){{.*}}NUM_SLOTS = 4 : ui32, SIZE_WIDTH = 3 : ui32, SPACE_WIDTH = 3 : ui32
handshake.func @both(%src: !handshake.channel<i32, [space: i3 (U)]>, ...)
    -> !handshake.channel<i32, [size: i3]>
    attributes {argNames = ["src"], resNames = ["out0"]} {
  %out = handshake.queue %src {numSlots = 4 : i64}
    : !handshake.channel<i32, [space: i3 (U)]> to !handshake.channel<i32, [size: i3]>
  end %out : <i32, [size: i3]>
}

// -----

// A queue nobody queries is a FIFO and carries no occupancy wires.
// CHECK-LABEL: hw.module @neither(
// CHECK-DAG: {{.*}}NUM_SLOTS = 8 : ui32, SIZE_WIDTH = 0 : ui32, SPACE_WIDTH = 0 : ui32
handshake.func @neither(%src: !handshake.channel<i32>, ...)
    -> !handshake.channel<i32>
    attributes {argNames = ["src"], resNames = ["out0"]} {
  %out = handshake.queue %src {numSlots = 8 : i64}
    : !handshake.channel<i32> to !handshake.channel<i32>
  end %out : <i32>
}

// -----

// Just one side: a consumer that tests availability but a producer that does
// not test room.
// CHECK-LABEL: hw.module @sizeOnly(
// CHECK-DAG: {{.*}}NUM_SLOTS = 2 : ui32, SIZE_WIDTH = 2 : ui32, SPACE_WIDTH = 0 : ui32
handshake.func @sizeOnly(%src: !handshake.channel<i32>, ...)
    -> !handshake.channel<i32, [size: i2]>
    attributes {argNames = ["src"], resNames = ["out0"]} {
  %out = handshake.queue %src {numSlots = 2 : i64}
    : !handshake.channel<i32> to !handshake.channel<i32, [size: i2]>
  end %out : <i32, [size: i2]>
}

// -----

// A queue holding tokens at reset: the generator is told their bits at the
// channel's width, first out first -- -3 and 7 on 16 bits, a float as its
// IEEE bits -- and a queue that starts empty is told "none" (the RTL matcher
// refuses an empty parameter).
// CHECK-LABEL: hw.module @initial(
// CHECK-DAG: hw.module.extern @handshake_queue_0({{.*}}INITIAL_TOKENS = "1111111111111101,0000000000000111", NUM_SLOTS = 2 : ui32, SIZE_WIDTH = 2 : ui32, SPACE_WIDTH = 0 : ui32
// CHECK-DAG: hw.module.extern @handshake_queue_1({{.*}}INITIAL_TOKENS = "00111111110000000000000000000000", NUM_SLOTS = 1 : ui32
// CHECK-DAG: hw.module.extern @handshake_queue_2({{.*}}INITIAL_TOKENS = "none", NUM_SLOTS = 1 : ui32
handshake.func @initial(%a: !handshake.channel<i16>, %b: !handshake.channel<f32>, %c: !handshake.channel<i16>, ...)
    -> (!handshake.channel<i16, [size: i2]>, !handshake.channel<f32>, !handshake.channel<i16>)
    attributes {argNames = ["a", "b", "c"], resNames = ["out0", "out1", "out2"]} {
  %qa = handshake.queue %a {numSlots = 2 : i64, initialTokens = [-3 : i16, 7 : i16]}
    : !handshake.channel<i16> to !handshake.channel<i16, [size: i2]>
  %qb = handshake.queue %b {numSlots = 1 : i64, initialTokens = [1.5 : f32]}
    : !handshake.channel<f32> to !handshake.channel<f32>
  %qc = handshake.queue %c {numSlots = 1 : i64}
    : !handshake.channel<i16> to !handshake.channel<i16>
  end %qa, %qb, %qc : <i16, [size: i2]>, <f32>, <i16>
}
