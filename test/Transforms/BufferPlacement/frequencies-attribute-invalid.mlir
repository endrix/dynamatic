// A malformed `handshake.frequencies` attribute is an error on the function,
// not a silently empty CFG.
//
// REQUIRES: cbc
// RUN: dynamatic-opt %s --split-input-file --verify-diagnostics --handshake-place-buffers="algorithm=fpga20 solver=cbc timeout=30 timing-models=%dynamatic_src_root/data/components.json spec-timing-models=%dynamatic_src_root/data/spec-timing.json"

// expected-error @below {{'handshake.frequencies' must be an array of [srcBB, dstBB, numTransitions, isBackedge] integer quadruplets}}
handshake.func @three_fields(%arg0: !handshake.channel<i32>, %arg1: !handshake.control<>, ...) -> (!handshake.channel<i32>, !handshake.control<>) attributes {argNames = ["a", "start"], resNames = ["out", "end"], handshake.frequencies = [[0, 1, 1]]} {
  %m = merge %arg0 {handshake.bb = 0 : ui32} : <i32>
  end %m, %arg1 : <i32>, <>
}

// -----

// expected-error @below {{'handshake.frequencies' must be an array of [srcBB, dstBB, numTransitions, isBackedge] integer quadruplets}}
handshake.func @not_integers(%arg0: !handshake.channel<i32>, %arg1: !handshake.control<>, ...) -> (!handshake.channel<i32>, !handshake.control<>) attributes {argNames = ["a", "start"], resNames = ["out", "end"], handshake.frequencies = [["0", 1, 1, 0]]} {
  %m = merge %arg0 {handshake.bb = 0 : ui32} : <i32>
  end %m, %arg1 : <i32>, <>
}

// -----

// No attribute, no CSV, but basic blocks: the pass says what it needs.
// expected-error @below {{no transition frequencies: pass a CSV file with the 'frequencies' option or set the 'handshake.frequencies' attribute on the function}}
handshake.func @nothing(%arg0: !handshake.channel<i32>, %arg1: !handshake.control<>, ...) -> (!handshake.channel<i32>, !handshake.control<>) attributes {argNames = ["a", "start"], resNames = ["out", "end"]} {
  %m = merge %arg0 {handshake.bb = 0 : ui32} : <i32>
  end %m, %arg1 : <i32>, <>
}
