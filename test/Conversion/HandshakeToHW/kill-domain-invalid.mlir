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

// -----

// A stand-in answers for the domain whose commit's kill it takes: a kill from
// anywhere else names no domain.
handshake.func @kill_arg(%a: !handshake.channel<i1>, %k: i1, ...)
    -> (!handshake.channel<i1>)
    attributes {argNames = ["a", "k"], resNames = ["out0"]} {
  // expected-error @below {{stands in for a producer, and its kill is no commit's}}
  %f = stand_in %a, %k : <i1>
  end %f : <i1>
}

// -----

// A load that drops on a domain's kill counts the addresses the domain gave
// it: one from outside would be counted as owed to the domain.
handshake.func @addr_in(%a: !handshake.channel<i2>, %d: !handshake.channel<i3>,
                        %mem: memref<4xi8>, %memStart: !handshake.control<>,
                        %ctrlEnd: !handshake.control<>, ...)
    -> (!handshake.channel<i1>, !handshake.channel<i3>, !handshake.control<>)
    attributes {argNames = ["a", "d", "mem", "memStart", "ctrlEnd"], resNames = ["out0", "out1", "memEnd"]} {
  // expected-error @below {{drops on kill domain 0's kill, and its address does not come from a unit of it}}
  %ldAddr, %ldData = load [%a] %memData {handshake.bb = 0 : ui32, handshake.kill_domain = 0 : ui32} : <i2>, <i8>, <i2>, <i8>
  %memData, %memEnd = mem_controller [%mem : memref<4xi8>] %memStart (%ldAddr) %ctrlEnd {connectedBlocks = [0 : i32]} : (!handshake.channel<i2>) -> !handshake.channel<i8>
  %c = trunci %ldData {handshake.kill_domain = 0 : ui32} : <i8> to <i1>
  %out, %kill = commit %d : <i3>
  %f = stand_in %c, %kill : <i1>
  end %f, %out, %memEnd : <i1>, <i3>, <>
}

// -----

// The drop counter's two bits count what a memory controller can owe a load
// port: a load whose address goes anywhere else may owe more, and the count
// would wrap.
handshake.func @addr_out(%a: !handshake.channel<i2>, %d: !handshake.channel<i3>,
                         %word: !handshake.channel<i8>, ...)
    -> (!handshake.channel<i1>, !handshake.channel<i3>, !handshake.channel<i2>)
    attributes {argNames = ["a", "d", "word"], resNames = ["out0", "out1", "addr"]} {
  %addr = buffer %a, bufferType = ONE_SLOT_BREAK_R, numSlots = 1, dvLatency = 0 {handshake.kill_domain = 0 : ui32} : <i2>
  // expected-error @below {{drops on kill domain 0's kill, and its address goes to 'handshake.end': only a memory controller bounds what the load can owe}}
  %ldAddr, %ldData = load [%addr] %word {handshake.kill_domain = 0 : ui32} : <i2>, <i8>, <i2>, <i8>
  %c = trunci %ldData {handshake.kill_domain = 0 : ui32} : <i8> to <i1>
  %out, %kill = commit %d : <i3>
  %f = stand_in %c, %kill : <i1>
  end %f, %out, %ldAddr : <i1>, <i3>, <i2>
}

// -----

// A unit between units of a domain joins it, and is refused if the closure
// does not know its reset to be synchronous (an ndwire's is asynchronous: a
// kill made by logic would glitch it).
handshake.func @async_join(%a: !handshake.channel<i1>, %d: !handshake.channel<i3>, ...)
    -> (!handshake.channel<i1>, !handshake.channel<i3>)
    attributes {argNames = ["a", "d"], resNames = ["out0", "out1"]} {
  %la = buffer %a, bufferType = ONE_SLOT_BREAK_R, numSlots = 1, dvLatency = 0 {handshake.kill_domain = 0 : ui32} : <i1>
  // expected-error @below {{joins kill domain 0, sitting between units of it, and a 'handshake.ndwire' is no unit a commit's kill may reset}}
  %w = ndwire %la : <i1>
  %out, %kill = commit %d : <i3>
  %f = stand_in %w, %kill : <i1>
  end %f, %out : <i1>, <i3>
}

// -----

// A stand-in is never in the domain it answers for: it answers from outside,
// on the module's reset.
handshake.func @stand_in_marked(%a: !handshake.channel<i2>, %d: !handshake.channel<i1>, ...)
    -> (!handshake.channel<i2>, !handshake.channel<i1>)
    attributes {argNames = ["a", "d"], resNames = ["flag", "dec"]} {
  %la = buffer %a, bufferType = ONE_SLOT_BREAK_R, numSlots = 1, dvLatency = 0 {handshake.kill_domain = 0 : ui32} : <i2>
  %decision, %kill = commit %d : <i1>
  // expected-error @below {{is marked with kill domain 0, and a 'handshake.stand_in' is never in one}}
  %flag = stand_in %la, %kill {handshake.kill_domain = 0 : ui32} : <i2>
  end %flag, %decision : <i2>, <i1>
}

// -----

// The error names why the unit a channel leaves into joined no domain: here a
// fork with one copy into the stand-in and the other out of the function.
handshake.func @fork_out(%a: !handshake.channel<i1>, %d: !handshake.channel<i3>, ...)
    -> (!handshake.channel<i1>, !handshake.channel<i1>, !handshake.channel<i3>)
    attributes {argNames = ["a", "d"], resNames = ["f", "g", "o1"]} {
  // expected-error @below {{is in kill domain 0 and hands a channel to 'handshake.fork' outside it (which joins no domain: it hands a channel to 'handshake.end')}}
  %la = buffer %a, bufferType = ONE_SLOT_BREAK_R, numSlots = 1, dvLatency = 0 {handshake.kill_domain = 0 : ui32} : <i1>
  %x:2 = fork [2] %la : <i1>
  %out, %kill = commit %d : <i3>
  %f = stand_in %x#0, %kill : <i1>
  end %f, %x#1, %out : <i1>, <i1>, <i3>
}
