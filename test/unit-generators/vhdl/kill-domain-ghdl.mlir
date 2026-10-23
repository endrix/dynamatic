// REQUIRES: ghdl
// RUN: rm -rf %t && mkdir -p %t
// RUN: dynamatic-opt %s --lower-handshake-to-hw > %t/kd.hw
// RUN: export-rtl %t/kd.hw %t/out %dynamatic_src_root/data/rtl-config-vhdl.json --dynamatic-path %dynamatic_src_root --hdl vhdl
// RUN: cd %t/out && ghdl -a --std=08 handshake_*.vhd kd.vhd %S/Inputs/kill-domain-tb.vhd
// RUN: cd %t/out && ghdl --elab-run --std=08 tb --stop-time=2us 2>&1 | FileCheck %s

// A kill domain simulated, through the lowering and the exporter (the
// function below, Inputs/kill-domain-tb.vhd): the commit's transfer
// resets the slot in the domain and not its neighbour; the stand-in on the
// slot, whose token had not passed, offers one zero the cycle after and holds
// it until taken; a token that passed in the commit's cycle, or earlier in the
// round, owes nothing; a token offered while the zero is owed waits behind it,
// and a commit in the cycle that zero is taken resets the slot holding it.
// No commit comes while a token waits at the stand-in's output (its
// precondition, which the stand-in's VHDL asserts).

// CHECK: kill domain: 19 cycles as expected
// CHECK-NOT: failure

handshake.func @kd(%a: !handshake.channel<i2>, %b: !handshake.channel<i2>, %d: !handshake.channel<i1>, ...)
    -> (!handshake.channel<i2>, !handshake.channel<i2>, !handshake.channel<i1>)
    attributes {argNames = ["a", "b", "d"], resNames = ["flag", "other", "dec"]} {
  %latch = buffer %a, bufferType = ONE_SLOT_BREAK_R, numSlots = 1, dvLatency = 0 {handshake.kill_domain = 0 : ui32} : <i2>
  %neighbour = buffer %b, bufferType = ONE_SLOT_BREAK_R, numSlots = 1, dvLatency = 0 : <i2>
  %decision, %kill = commit %d : <i1>
  %flag = stand_in %latch, %kill : <i2>
  end %flag, %neighbour, %decision : <i2>, <i2>, <i1>
}
