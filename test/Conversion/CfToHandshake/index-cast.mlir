// RUN: dynamatic-opt --lower-cf-to-handshake --remove-operation-names %s --split-input-file | FileCheck %s

// An index is 32 bits wide in the handshake world, so an index_cast between
// an index and an i32 changes no bit: the cast is its operand. It used to
// fall to the truncation branch, and a trunci from i32 to i32 is refused by
// the verifier ("cast incompatible") -- MPEG-4 SP's parser writes exactly
// this, an i4 through an index into an i32.

// CHECK-LABEL: handshake.func @same_width(
// CHECK-SAME:      %[[X:.*]]: !handshake.channel<i4>
// CHECK:         %[[WIDE:.*]] = extsi %[[X]] {{.*}}: <i4> to <i32>
// CHECK-NOT:     trunci
// CHECK:         end {{.*}}%[[WIDE]]
func.func @same_width(%x: i4) -> i32 {
  %i = arith.index_cast %x : i4 to index
  %y = arith.index_cast %i : index to i32
  return %y : i32
}

// -----

// And the two that change width keep their units.
// CHECK-LABEL: handshake.func @narrow_and_wide(
// CHECK:         extsi {{.*}}: <i8> to <i32>
// CHECK:         trunci {{.*}}: <i32> to <i16>
func.func @narrow_and_wide(%x: i8) -> i16 {
  %i = arith.index_cast %x : i8 to index
  %y = arith.index_cast %i : index to i16
  return %y : i16
}
