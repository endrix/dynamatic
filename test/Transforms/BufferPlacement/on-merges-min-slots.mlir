// on-merges places what the buffering properties demand: opaque and
// transparent minimums, and now also a minimum on the total number of slots,
// made up with transparent ones. That third minimum is what
// set-buffering-properties puts in front of every LSQ access; dropping it
// left the LSQ's allocation-to-access lag on the loop's recurrence.
//
// RUN: dynamatic-opt %s --handshake-place-buffers="algorithm=on-merges timing-models=%dynamatic_src_root/data/components.json" --remove-operation-names | FileCheck %s

// CHECK-LABEL: handshake.func @slots
// One slot of any kind: a transparent one.
// CHECK:       %[[A:.*]] = buffer %arg0, bufferType = ONE_SLOT_BREAK_R, numSlots = 1
// CHECK:       addi %[[A]], %
// One opaque slot and two slots in total: both.
// CHECK:       %[[B1:.*]] = buffer %arg1, bufferType = ONE_SLOT_BREAK_DV, numSlots = 1
// CHECK-NEXT:  %[[B2:.*]] = buffer %[[B1]], bufferType = ONE_SLOT_BREAK_R, numSlots = 1
// CHECK:       addi %[[B2]], %
// An opaque minimum that already meets the total: nothing extra.
// CHECK:       %[[C:.*]] = buffer %arg2, bufferType = ONE_SLOT_BREAK_DV, numSlots = 1
// CHECK-NEXT:  addi %[[C]], %
handshake.func @slots(%arg0: !handshake.channel<i32>, %arg1: !handshake.channel<i32>, %arg2: !handshake.channel<i32>, %arg3: !handshake.control<>, ...) -> (!handshake.channel<i32>, !handshake.channel<i32>, !handshake.channel<i32>, !handshake.control<>) attributes {argNames = ["a", "b", "c", "start"], resNames = ["a1", "b1", "c1", "end"]} {
  %s = source : <>
  %k:3 = fork [3] %s : <>
  %one = constant %k#0 {value = 1 : i32} : <>, <i32>
  %two = constant %k#1 {value = 2 : i32} : <>, <i32>
  %three = constant %k#2 {value = 3 : i32} : <>, <i32>
  %a = addi %arg0, %one {handshake.bufProps = #handshake<bufProps{"0": [0,inf], [0,inf], 1, 0.000000e+00, 0.000000e+00, 0.000000e+00}>} : <i32>
  %b = addi %arg1, %two {handshake.bufProps = #handshake<bufProps{"0": [0,inf], [1,inf], 2, 0.000000e+00, 0.000000e+00, 0.000000e+00}>} : <i32>
  %c = addi %arg2, %three {handshake.bufProps = #handshake<bufProps{"0": [0,inf], [1,inf], 1, 0.000000e+00, 0.000000e+00, 0.000000e+00}>} : <i32>
  end %a, %b, %c, %arg3 : <i32>, <i32>, <i32>, <>
}
