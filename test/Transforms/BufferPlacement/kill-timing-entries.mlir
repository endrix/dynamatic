// The units a commit stops have entries of their own: a stand-in is timed by
// the entry for its number of kills, `handshake.stand_in.size.<N>` (as
// HandshakeToHW writes its SIZE), and a load in a kill domain, which counts
// and drops the words it owes, by `handshake.load.kill_drop`. The model in
// Inputs gives the one-kill stand-in and the plain load a 0.001 ns data path
// and the two-kill stand-in and the dropping load a 1.5 ns one, so at a
// 2.0 ns period the placer cuts only where the longer entry is read.
//
// REQUIRES: cbc
// RUN: dynamatic-opt %s --handshake-place-buffers="algorithm=fpga20 solver=cbc timeout=30 target-period=2.0 timing-models=%S/Inputs/kill-timing-models.json spec-timing-models=%dynamatic_src_root/data/spec-timing.json" --remove-operation-names 2>/dev/null | FileCheck %s

// Two stand-ins of one kill in a row: 0.001 ns twice fits, nothing is placed.
// CHECK-LABEL: handshake.func @one_kill
// CHECK-NOT:   buffer
// CHECK:       end
handshake.func @one_kill(%d: !handshake.channel<i3>, %f: !handshake.channel<i8>, %start: !handshake.control<>, ...) -> (!handshake.channel<i3>, !handshake.channel<i8>, !handshake.control<>) attributes {argNames = ["d", "f", "start"], resNames = ["d_out", "f_out", "end"], handshake.frequencies = []} {
  %out, %kill = commit %d {handshake.bb = 0 : ui32} : <i3>
  %a = stand_in %f, %kill {handshake.bb = 0 : ui32} : <i8>
  %b = stand_in %a, %kill {handshake.bb = 0 : ui32} : <i8>
  end %out, %b, %start : <i3>, <i8>, <>
}

// Two stand-ins of two kills in a row (a domain of two commits, one a
// state's decision each): the size-2 entry is read, 1.5 + 1.5 ns does not fit
// in 2.0 ns, and the placer cuts between them.
// CHECK-LABEL: handshake.func @two_kills
// CHECK:       stand_in
// CHECK-NEXT:  buffer
// CHECK-NEXT:  stand_in
handshake.func @two_kills(%d: !handshake.channel<i3>, %e: !handshake.channel<i3>, %f: !handshake.channel<i8>, %start: !handshake.control<>, ...) -> (!handshake.channel<i3>, !handshake.channel<i3>, !handshake.channel<i8>, !handshake.control<>) attributes {argNames = ["d", "e", "f", "start"], resNames = ["d_out", "e_out", "f_out", "end"], handshake.frequencies = []} {
  %o1, %k1 = commit %d {handshake.bb = 0 : ui32} : <i3>
  %o2, %k2 = commit %e {handshake.bb = 0 : ui32} : <i3>
  %a = stand_in %f, %k1, %k2 {handshake.bb = 0 : ui32} : <i8>
  %b = stand_in %a, %k1, %k2 {handshake.bb = 0 : ui32} : <i8>
  end %o1, %o2, %b, %start : <i3>, <i3>, <i8>, <>
}

// A load and a truncation after it: the plain load's 0.001 ns and the
// truncation's 1.0 ns fit in 2.0 ns, and nothing is placed.
// CHECK-LABEL: handshake.func @plain_load
// CHECK-NOT:   buffer
// CHECK:       end
handshake.func @plain_load(%addr: !handshake.channel<i2>, %mem: memref<4xi8>, %memStart: !handshake.control<>, %ctrlEnd: !handshake.control<>, %start: !handshake.control<>, ...) -> (!handshake.channel<i1>, !handshake.control<>, !handshake.control<>) attributes {argNames = ["addr", "mem", "memStart", "ctrlEnd", "start"], resNames = ["out", "memEnd", "end"], handshake.frequencies = []} {
  %ldAddr, %ldData = load [%addr] %memData {handshake.bb = 0 : ui32} : <i2>, <i8>, <i2>, <i8>
  %memData, %memEnd = mem_controller [%mem : memref<4xi8>] %memStart (%ldAddr) %ctrlEnd {connectedBlocks = [0 : i32]} : (!handshake.channel<i2>) -> !handshake.channel<i8>
  %c = trunci %ldData {handshake.bb = 0 : ui32} : <i8> to <i1>
  end %c, %memEnd, %start : <i1>, <>, <>
}

// The same load in a kill domain is the one that drops what it owes on a
// kill: its entry's 1.5 ns and the truncation's 1.0 ns do not fit, and the
// placer cuts between them.
// CHECK-LABEL: handshake.func @dropping_load
// CHECK:       load
// CHECK:       buffer
// CHECK-NEXT:  trunci
handshake.func @dropping_load(%addr: !handshake.channel<i2>, %mem: memref<4xi8>, %memStart: !handshake.control<>, %ctrlEnd: !handshake.control<>, %start: !handshake.control<>, ...) -> (!handshake.channel<i1>, !handshake.control<>, !handshake.control<>) attributes {argNames = ["addr", "mem", "memStart", "ctrlEnd", "start"], resNames = ["out", "memEnd", "end"], handshake.frequencies = []} {
  %ldAddr, %ldData = load [%addr] %memData {handshake.bb = 0 : ui32, handshake.kill_domain = 0 : ui32} : <i2>, <i8>, <i2>, <i8>
  %memData, %memEnd = mem_controller [%mem : memref<4xi8>] %memStart (%ldAddr) %ctrlEnd {connectedBlocks = [0 : i32]} : (!handshake.channel<i2>) -> !handshake.channel<i8>
  %c = trunci %ldData {handshake.bb = 0 : ui32} : <i8> to <i1>
  end %c, %memEnd, %start : <i1>, <>, <>
}
