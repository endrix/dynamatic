// REQUIRES: ghdl
// RUN: rm -rf %t && mkdir -p %t
// RUN: dynamatic-opt %s --lower-handshake-to-hw > %t/kd.hw
// RUN: export-rtl %t/kd.hw %t/out %dynamatic_src_root/data/rtl-config-vhdl.json --dynamatic-path %dynamatic_src_root --hdl vhdl
// RUN: cd %t/out && ghdl -a --std=08 handshake_*.vhd kill_or_*.vhd kd.vhd %S/Inputs/kill-domain-tb.vhd
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
//
// Two domains, and a domain with two commits: domain 0 (the slot `latch`) is
// stopped by the decision on `d` and by the one on `e`, whose second commit,
// in series after domain 1's, is domain 0's (the lowering ORs the two kills,
// a kill_or); domain 1 (the slot `latch1`) by `e`'s alone. The stand-in of
// domain 0 takes both kills, domain 1's its one. `e`'s commit ends a round of
// both, `d`'s of domain 0 only: domain 1's slot, full behind its stand-in's
// owed zero, survives `d`'s commit and is reset by `e`'s; domain 0's slot,
// full behind its stand-in's owed zero, is reset by `e`'s commit too (the OR).
// The two decisions never come in one cycle: the bench observes it (the
// domain's promise).

// CHECK: kill domain: 39 cycles as expected
// CHECK-NOT: failure

handshake.func @kd(%a: !handshake.channel<i2>, %b: !handshake.channel<i2>, %d: !handshake.channel<i1>,
                   %e: !handshake.channel<i1>, %c: !handshake.channel<i2>, ...)
    -> (!handshake.channel<i2>, !handshake.channel<i2>, !handshake.channel<i1>,
        !handshake.channel<i1>, !handshake.channel<i2>)
    attributes {argNames = ["a", "b", "d", "e", "c"], resNames = ["flag", "other", "dec", "dec2", "flag1"]} {
  %latch = buffer %a, bufferType = ONE_SLOT_BREAK_R, numSlots = 1, dvLatency = 0 {handshake.kill_domain = 0 : ui32} : <i2>
  %neighbour = buffer %b, bufferType = ONE_SLOT_BREAK_R, numSlots = 1, dvLatency = 0 : <i2>
  %decision, %kill = commit %d : <i1>
  %e1, %kill1 = commit %e {domain = 1 : ui32} : <i1>
  %decision2, %kill2 = commit %e1 : <i1>
  %latch1 = buffer %c, bufferType = ONE_SLOT_BREAK_R, numSlots = 1, dvLatency = 0 {handshake.kill_domain = 1 : ui32} : <i2>
  %flag = stand_in %latch, %kill, %kill2 : <i2>
  %flag1 = stand_in %latch1, %kill1 : <i2>
  end %flag, %neighbour, %decision, %decision2, %flag1 : <i2>, <i2>, <i1>, <i1>, <i2>
}
