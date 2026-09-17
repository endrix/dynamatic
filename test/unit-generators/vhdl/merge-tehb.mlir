// RUN: %export-vhdl
// RUN: FileCheck %s -input-file %t/handshake_merge_0.vhd --check-prefix=SLOT
// RUN: FileCheck %s -input-file %t/handshake_merge_1.vhd --check-prefix=BARE

// The slot behind a merge's arbiter. TEHB=1 is the unit as it was, the
// arbiter (merge_notehb) and a one_slot_break_r; TEHB=0 is the arbiter
// alone under the unit's name, for a consumer that cuts ready itself.

// SLOT: entity handshake_merge_0_inner is
// SLOT: entity handshake_merge_0_one_slot_break_r is
// SLOT: entity handshake_merge_0 is
// SLOT: one_slot_break_r : entity work.handshake_merge_0_one_slot_break_r

// BARE-NOT: one_slot_break_r
// BARE: entity handshake_merge_1 is
// BARE-NOT: one_slot_break_r
module {
  hw.module @test(in %a : !handshake.channel<i8>, in %b : !handshake.channel<i8>, in %c : !handshake.channel<i8>, in %d : !handshake.channel<i8>, in %clk : i1, in %rst : i1, out out0 : !handshake.channel<i8>, out out1 : !handshake.channel<i8>) {
    %merge0.outs = hw.instance "merge0" @handshake_merge_0(ins_0: %a: !handshake.channel<i8>, ins_1: %b: !handshake.channel<i8>, clk: %clk: i1, rst: %rst: i1) -> (outs: !handshake.channel<i8>)
    %merge1.outs = hw.instance "merge1" @handshake_merge_1(ins_0: %c: !handshake.channel<i8>, ins_1: %d: !handshake.channel<i8>, clk: %clk: i1, rst: %rst: i1) -> (outs: !handshake.channel<i8>)
    hw.output %merge0.outs, %merge1.outs : !handshake.channel<i8>, !handshake.channel<i8>
  }
  hw.module.extern @handshake_merge_0(in %ins_0 : !handshake.channel<i8>, in %ins_1 : !handshake.channel<i8>, in %clk : i1, in %rst : i1, out outs : !handshake.channel<i8>) attributes {hw.name = "handshake.merge", hw.parameters = {DATA_TYPE = !handshake.channel<i8>, SIZE = 2 : ui32, TEHB = 1 : ui32}}
  hw.module.extern @handshake_merge_1(in %ins_0 : !handshake.channel<i8>, in %ins_1 : !handshake.channel<i8>, in %clk : i1, in %rst : i1, out outs : !handshake.channel<i8>) attributes {hw.name = "handshake.merge", hw.parameters = {DATA_TYPE = !handshake.channel<i8>, SIZE = 2 : ui32, TEHB = 0 : ui32}}
}
