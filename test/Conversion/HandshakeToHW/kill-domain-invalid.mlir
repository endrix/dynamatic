// RUN: dynamatic-opt %s --lower-handshake-to-hw --split-input-file --verify-diagnostics

// A unit in a kill domain no commit of the function names has no reset to
// take (here domain 1, beside domain 0 and its commit).
handshake.func @no_commit(%a: !handshake.channel<i2>, %c: !handshake.channel<i2>,
                          %d: !handshake.channel<i3>, ...)
    -> !handshake.channel<i3>
    attributes {argNames = ["a", "c", "d"], resNames = ["out0"]} {
  %b0 = buffer %c, bufferType = ONE_SLOT_BREAK_R, numSlots = 1, dvLatency = 0 {handshake.kill_domain = 0 : ui32} : <i2>
  sink %b0 {handshake.kill_domain = 0 : ui32} : <i2>
  // expected-error @below {{is in kill domain 1 and no commit of this function names that domain: it has no reset to take}}
  %b = buffer %a, bufferType = ONE_SLOT_BREAK_R, numSlots = 1, dvLatency = 0 {handshake.kill_domain = 1 : ui32} : <i2>
  sink %b {handshake.kill_domain = 1 : ui32} : <i2>
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

// A commit's domain has a unit or a stand-in: its kill would reset nothing.
// (Domain 0 has two commits, which is allowed; domain 2 has nothing.)
handshake.func @commit_alone(%a: !handshake.channel<i2>, %d: !handshake.channel<i3>,
                             %e: !handshake.channel<i3>, ...)
    -> (!handshake.channel<i3>, !handshake.channel<i3>)
    attributes {argNames = ["a", "d", "e"], resNames = ["out0", "out1"]} {
  %b = buffer %a, bufferType = ONE_SLOT_BREAK_R, numSlots = 1, dvLatency = 0 {handshake.kill_domain = 0 : ui32} : <i2>
  sink %b {handshake.kill_domain = 0 : ui32} : <i2>
  %out, %kill = commit %d : <i3>
  %out2, %kill2 = commit %e : <i3>
  // expected-error @below {{is a commit of kill domain 2, and no unit of this function is in that domain and no stand-in answers for it: its kill would reset nothing}}
  %out3, %kill3 = commit %out2 {domain = 2 : ui32} : <i3>
  end %out, %out3 : <i3>, <i3>
}

// -----

// A stand-in takes the kills of ALL its domain's commits: the transfer of one
// it does not take resets its producer and owes nothing here, so the round
// that commit ends never gets the stand-in's token. Here the shared domain 2
// has a commit on each of two decisions (as in kill-domain-shared.mlir) and
// its stand-in takes the first's kill only.
handshake.func @stand_in_some(%a: !handshake.channel<i1>, %d0: !handshake.channel<i3>,
                              %d1: !handshake.channel<i3>, ...)
    -> (!handshake.channel<i1>, !handshake.channel<i3>, !handshake.channel<i3>)
    attributes {argNames = ["a", "d0", "d1"], resNames = ["f", "o0", "o1"]} {
  %la = buffer %a, bufferType = ONE_SLOT_BREAK_R, numSlots = 1, dvLatency = 0 {handshake.kill_domain = 2 : ui32} : <i1>
  %o0, %k0 = commit %d0 {domain = 2 : ui32} : <i3>
  // expected-note @below {{a commit of kill domain 2 whose kill the stand-in does not take}}
  %o1, %k1 = commit %d1 {domain = 2 : ui32} : <i3>
  // expected-error @below {{stands in for kill domain 2 and takes the kills of 1 of its 2 commits: the transfer of one it does not take resets its producer with no zero owed here, and the round's reader waits for ever; a stand-in takes the kill of every commit of its domain}}
  %f = stand_in %la, %k0 : <i1>
  end %f, %o0, %o1 : <i1>, <i3>, <i3>
}

// -----

// A stand-in takes each kill once: two bits of one commit are high in the
// cycle that ends one round.
handshake.func @kill_twice(%a: !handshake.channel<i1>, %d: !handshake.channel<i3>, ...)
    -> (!handshake.channel<i1>, !handshake.channel<i3>)
    attributes {argNames = ["a", "d"], resNames = ["f", "o"]} {
  %la = buffer %a, bufferType = ONE_SLOT_BREAK_R, numSlots = 1, dvLatency = 0 {handshake.kill_domain = 0 : ui32} : <i1>
  %out, %kill = commit %d : <i3>
  // expected-error @below {{stands in for kill domain 0 and takes one commit's kill twice (#0 and #1): a commit's transfer ends one round, so a stand-in takes each kill once}}
  %f = stand_in %la, %kill, %kill : <i1>
  end %f, %out : <i1>, <i3>
}

// -----

// A decision stops a domain through one commit: two commits of one domain in
// series on one channel (here with domain 1's between them) see one transfer
// and end one round.
handshake.func @series_same_domain(%a: !handshake.channel<i2>, %c: !handshake.channel<i2>,
                                   %d: !handshake.channel<i3>, ...)
    -> !handshake.channel<i3>
    attributes {argNames = ["a", "c", "d"], resNames = ["o"]} {
  %b = buffer %a, bufferType = ONE_SLOT_BREAK_R, numSlots = 1, dvLatency = 0 {handshake.kill_domain = 0 : ui32} : <i2>
  sink %b {handshake.kill_domain = 0 : ui32} : <i2>
  %b1 = buffer %c, bufferType = ONE_SLOT_BREAK_R, numSlots = 1, dvLatency = 0 {handshake.kill_domain = 1 : ui32} : <i2>
  sink %b1 {handshake.kill_domain = 1 : ui32} : <i2>
  // expected-note @below {{the commit of kill domain 0 before it on the channel}}
  %o0, %k0 = commit %d : <i3>
  %o1, %k1 = commit %o0 {domain = 1 : ui32} : <i3>
  // expected-error @below {{is a commit of kill domain 0 in series after another commit of it: the two see one transfer and end one round, so one of them is all the decision needs}}
  %o2, %k2 = commit %o1 : <i3>
  end %o2 : <i3>
}

// -----

// A stand-in answers for one domain, its producer's: its kills are commits'
// of that domain (all of them), never of two.
handshake.func @two_domains_kills(%a: !handshake.channel<i1>, %c: !handshake.channel<i1>,
                                  %d: !handshake.channel<i3>, %e: !handshake.channel<i3>, ...)
    -> (!handshake.channel<i1>, !handshake.channel<i3>, !handshake.channel<i3>)
    attributes {argNames = ["a", "c", "d", "e"], resNames = ["f", "o1", "o2"]} {
  %la = buffer %a, bufferType = ONE_SLOT_BREAK_R, numSlots = 1, dvLatency = 0 {handshake.kill_domain = 0 : ui32} : <i1>
  %lc = buffer %c, bufferType = ONE_SLOT_BREAK_R, numSlots = 1, dvLatency = 0 {handshake.kill_domain = 1 : ui32} : <i1>
  sink %lc {handshake.kill_domain = 1 : ui32} : <i1>
  %out, %kill = commit %d : <i3>
  %out2, %kill2 = commit %e {domain = 1 : ui32} : <i3>
  // expected-error @below {{stands in for kill domain 0 (its kill #0 is a commit's of it), and its kill #1 is kill domain 1's: a stand-in answers for one domain, its producer's}}
  %f = stand_in %la, %kill, %kill2 : <i1>
  end %f, %out, %out2 : <i1>, <i3>, <i3>
}

// -----

// A stand-in answers for the domain whose commits' kills it takes: a kill
// from anywhere else names no domain.
handshake.func @kill_arg(%a: !handshake.channel<i1>, %k: i1, ...)
    -> (!handshake.channel<i1>)
    attributes {argNames = ["a", "k"], resNames = ["out0"]} {
  // expected-error @below {{stands in for a producer, and its kill #0 is no commit's: a stand-in answers for the domain whose commits' kills it takes}}
  %f = stand_in %a, %k : <i1>
  end %f : <i1>
}

// -----

// ... whichever of its kills it is.
handshake.func @kill_arg_second(%a: !handshake.channel<i1>, %d: !handshake.channel<i3>,
                                %k: i1, ...)
    -> (!handshake.channel<i1>, !handshake.channel<i3>)
    attributes {argNames = ["a", "d", "k"], resNames = ["out0", "out1"]} {
  %la = buffer %a, bufferType = ONE_SLOT_BREAK_R, numSlots = 1, dvLatency = 0 {handshake.kill_domain = 0 : ui32} : <i1>
  %out, %kill = commit %d : <i3>
  // expected-error @below {{stands in for a producer, and its kill #1 is no commit's}}
  %f = stand_in %la, %kill, %k : <i1>
  end %f, %out : <i1>, <i3>
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
