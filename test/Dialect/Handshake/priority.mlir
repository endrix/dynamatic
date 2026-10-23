// RUN: dynamatic-opt %s | dynamatic-opt | FileCheck %s

// A priority of two one-hot vectors prints and parses back as itself.

// CHECK-LABEL: handshake.func @prio
// CHECK: %[[P:.*]] = priority %arg0, %arg1 : <i4>
// CHECK: end %[[P]] : <i4>
handshake.func @prio(%hi: !handshake.channel<i4>, %lo: !handshake.channel<i4>, ...)
    -> !handshake.channel<i4>
    attributes {argNames = ["hi", "lo"], resNames = ["out0"]} {
  %0 = priority %hi, %lo : <i4>
  end %0 : <i4>
}
