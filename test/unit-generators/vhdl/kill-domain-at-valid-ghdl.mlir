// REQUIRES: ghdl
// RUN: rm -rf %t && mkdir -p %t
// RUN: dynamatic-opt %s --lower-handshake-to-hw > %t/kdv.hw
// RUN: export-rtl %t/kdv.hw %t/out %dynamatic_src_root/data/rtl-config-vhdl.json --dynamatic-path %dynamatic_src_root --hdl vhdl
// RUN: cd %t/out && ghdl -a --std=08 handshake_*.vhd kill_or_*.vhd kdv.vhd %S/Inputs/kill-domain-at-valid-tb.vhd
// RUN: cd %t/out && ghdl --elab-run --std=08 tb --stop-time=2us 2>&1 | FileCheck %s

// kill-domain-ghdl.mlir's two domains, its kill_or and its commits in series,
// with `kill_at_valid` on every commit: the same lowering and exporter, and
// the readers of the decisions stalling, which is the only case in which the
// earlier kill differs from the transfer's. What this pins (Inputs/
// kill-domain-at-valid-tb.vhd, whose expected values are a model's of the
// units):
// - the kill comes in the FIRST cycle a decision is offered, so a stand-in
//   that owes a zero offers it the cycle after that, while the decision is
//   still waiting for its reader;
// - and not again for that token: neither in the cycles it keeps waiting nor
//   in the cycle it transfers (one kill a token, one round ended a token);
// - the token offered after a transfer is killed again in its first cycle,
//   the cycle right after the transfer included;
// - two commits in series on one decision (domain 1's then domain 0's) see
//   one valid and one ready, so their one-shots pulse in the same cycle and
//   their stand-ins owe their zeros in the same cycle;
// - the kill_or of domain 0's two commits never carries two pulses in one
//   cycle (the tb models both one-shots and asserts it, as the domain's
//   promise; each stand-in asserts that no two of its kills are high in one
//   cycle);
// - a slot outside the domains is never reset by a kill.
// Run against the transfer's commits (the attributes dropped below), the
// bench fails at the first cycle a zero is expected.

// CHECK: at-valid kill domain: 10 cycles as expected
// CHECK-NOT: failure

handshake.func @kdv(%a: !handshake.channel<i2>, %b: !handshake.channel<i2>, %d: !handshake.channel<i1>,
                    %e: !handshake.channel<i1>, %c: !handshake.channel<i2>, ...)
    -> (!handshake.channel<i2>, !handshake.channel<i2>, !handshake.channel<i1>,
        !handshake.channel<i1>, !handshake.channel<i2>)
    attributes {argNames = ["a", "b", "d", "e", "c"], resNames = ["flag", "other", "dec", "dec2", "flag1"]} {
  %latch = buffer %a, bufferType = ONE_SLOT_BREAK_R, numSlots = 1, dvLatency = 0 {handshake.kill_domain = 0 : ui32} : <i2>
  %neighbour = buffer %b, bufferType = ONE_SLOT_BREAK_R, numSlots = 1, dvLatency = 0 : <i2>
  %decision, %kill = commit %d {kill_at_valid} : <i1>
  %e1, %kill1 = commit %e {domain = 1 : ui32, kill_at_valid} : <i1>
  %decision2, %kill2 = commit %e1 {kill_at_valid} : <i1>
  %latch1 = buffer %c, bufferType = ONE_SLOT_BREAK_R, numSlots = 1, dvLatency = 0 {handshake.kill_domain = 1 : ui32} : <i2>
  %flag = stand_in %latch, %kill, %kill2 : <i2>
  %flag1 = stand_in %latch1, %kill1 : <i2>
  end %flag, %neighbour, %decision, %decision2, %flag1 : <i2>, <i2>, <i1>, <i1>, <i2>
}
