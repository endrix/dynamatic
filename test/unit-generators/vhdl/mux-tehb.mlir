// RUN: %export-vhdl
// RUN: FileCheck %s -input-file %t/handshake_mux_0.vhd --check-prefix=SLOT
// RUN: FileCheck %s -input-file %t/handshake_mux_1.vhd --check-prefix=BARE

// The slot behind a mux's select. TEHB=1 is the unit as it was, the select
// and a one_slot_break_r; TEHB=0 is the select alone under the unit's name,
// for a consumer that cuts ready itself.

// SLOT: entity handshake_mux_0_one_slot_break_r is
// SLOT: entity handshake_mux_0 is
// SLOT: one_slot_break_r : entity work.handshake_mux_0_one_slot_break_r

// BARE-NOT: one_slot_break_r :
// BARE: entity handshake_mux_1 is
// BARE: outs       <= sel_data;
// BARE: sel_ready  <= outs_ready;
module {
  hw.module @test(in %s0 : !handshake.channel<i1>, in %a : !handshake.channel<i8>, in %b : !handshake.channel<i8>, in %s1 : !handshake.channel<i1>, in %c : !handshake.channel<i8>, in %d : !handshake.channel<i8>, in %clk : i1, in %rst : i1, out out0 : !handshake.channel<i8>, out out1 : !handshake.channel<i8>) {
    %mux0.outs = hw.instance "mux0" @handshake_mux_0(index: %s0: !handshake.channel<i1>, ins_0: %a: !handshake.channel<i8>, ins_1: %b: !handshake.channel<i8>, clk: %clk: i1, rst: %rst: i1) -> (outs: !handshake.channel<i8>)
    %mux1.outs = hw.instance "mux1" @handshake_mux_1(index: %s1: !handshake.channel<i1>, ins_0: %c: !handshake.channel<i8>, ins_1: %d: !handshake.channel<i8>, clk: %clk: i1, rst: %rst: i1) -> (outs: !handshake.channel<i8>)
    hw.output %mux0.outs, %mux1.outs : !handshake.channel<i8>, !handshake.channel<i8>
  }
  hw.module.extern @handshake_mux_0(in %index : !handshake.channel<i1>, in %ins_0 : !handshake.channel<i8>, in %ins_1 : !handshake.channel<i8>, in %clk : i1, in %rst : i1, out outs : !handshake.channel<i8>) attributes {hw.name = "handshake.mux", hw.parameters = {DATA_TYPE = !handshake.channel<i8>, SELECT_TYPE = !handshake.channel<i1>, SIZE = 2 : ui32, TEHB = 1 : ui32}}
  hw.module.extern @handshake_mux_1(in %index : !handshake.channel<i1>, in %ins_0 : !handshake.channel<i8>, in %ins_1 : !handshake.channel<i8>, in %clk : i1, in %rst : i1, out outs : !handshake.channel<i8>) attributes {hw.name = "handshake.mux", hw.parameters = {DATA_TYPE = !handshake.channel<i8>, SELECT_TYPE = !handshake.channel<i1>, SIZE = 2 : ui32, TEHB = 0 : ui32}}
}
