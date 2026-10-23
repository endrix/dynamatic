// RUN: dynamatic-opt %s --lower-handshake-to-hw --split-input-file --verify-diagnostics

// A unit in a kill domain no commit of the module defines has no reset to
// take.
handshake.func @no_commit(%a: !handshake.channel<i2>, %d: !handshake.channel<i3>, ...)
    -> !handshake.channel<i3>
    attributes {argNames = ["a", "d"], resNames = ["out0"]} {
  // expected-error @below {{is in kill domain 3 and no commit of this module has that domain}}
  %b = buffer %a, bufferType = ONE_SLOT_BREAK_R, numSlots = 1, dvLatency = 0 {handshake.kill_domain = 3 : ui32} : <i2>
  sink %b {handshake.kill_domain = 3 : ui32} : <i2>
  %out, %kill = commit %d : <i3>
  end %out : <i3>
}

// -----

// A channel leaves a domain through a stand-in, or as a load's address: the
// domain's reset would withdraw a token offered anywhere else.
handshake.func @leaks(%a: !handshake.channel<i2>, %d: !handshake.channel<i3>, ...)
    -> (!handshake.channel<i2>, !handshake.channel<i3>)
    attributes {argNames = ["a", "d"], resNames = ["out0", "out1"]} {
  // expected-error @below {{is in kill domain 0 and hands a channel to 'handshake.end' outside it}}
  %b = buffer %a, bufferType = ONE_SLOT_BREAK_R, numSlots = 1, dvLatency = 0 {handshake.kill_domain = 0 : ui32} : <i2>
  %out, %kill = commit %d : <i3>
  end %b, %out : <i2>, <i3>
}

// -----

// A stand-in answers for a producer of its domain: a token from elsewhere,
// which the reset cannot take back, would be taken for the round's.
handshake.func @foreign(%a: !handshake.channel<i1>, %d: !handshake.channel<i3>, ...)
    -> (!handshake.channel<i1>, !handshake.channel<i3>)
    attributes {argNames = ["a", "d"], resNames = ["out0", "out1"]} {
  %out, %kill = commit %d : <i3>
  // expected-error @below {{stands in for kill domain 0, and its input does not come from a unit of it}}
  %f = stand_in %a, %kill : <i1>
  end %f, %out : <i1>, <i3>
}

// -----

// A load that drops on a domain's kill delivers its words into the domain
// only: a word it drops would never reach a reader outside.
handshake.func @word_out(%a: !handshake.channel<i2>, %d: !handshake.channel<i3>,
                         %mem: memref<4xi8>, %memStart: !handshake.control<>,
                         %ctrlEnd: !handshake.control<>, ...)
    -> (!handshake.channel<i8>, !handshake.channel<i3>, !handshake.control<>)
    attributes {argNames = ["a", "d", "mem", "memStart", "ctrlEnd"], resNames = ["out0", "out1", "memEnd"]} {
  %addr = buffer %a, bufferType = ONE_SLOT_BREAK_R, numSlots = 1, dvLatency = 0 {handshake.kill_domain = 0 : ui32} : <i2>
  // expected-error @below {{drops on kill domain 0's kill, and its word goes to 'handshake.end' outside it}}
  %ldAddr, %ldData = load [%addr] %memData {handshake.bb = 0 : ui32, handshake.kill_domain = 0 : ui32} : <i2>, <i8>, <i2>, <i8>
  %memData, %memEnd = mem_controller [%mem : memref<4xi8>] %memStart (%ldAddr) %ctrlEnd {connectedBlocks = [0 : i32]} : (!handshake.channel<i2>) -> !handshake.channel<i8>
  %out, %kill = commit %d : <i3>
  end %ldData, %out, %memEnd : <i8>, <i3>, <>
}

// -----

// One transfer resets a domain: two commits of one domain in a module would
// leave its units with two resets.
handshake.func @two_commits(%a: !handshake.channel<i2>, %d: !handshake.channel<i3>,
                            %e: !handshake.channel<i3>, ...)
    -> (!handshake.channel<i3>, !handshake.channel<i3>)
    attributes {argNames = ["a", "d", "e"], resNames = ["out0", "out1"]} {
  %b = buffer %a, bufferType = ONE_SLOT_BREAK_R, numSlots = 1, dvLatency = 0 {handshake.kill_domain = 0 : ui32} : <i2>
  sink %b {handshake.kill_domain = 0 : ui32} : <i2>
  %out, %kill = commit %d : <i3>
  // expected-error @below {{two commits for kill domain 0 in one module}}
  %out2, %kill2 = commit %e : <i3>
  end %out, %out2 : <i3>, <i3>
}
