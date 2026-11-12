// RUN: rm -rf %t && mkdir -p %t
// RUN: python3 %dynamatic_src_root/tools/unit-generators/vhdl/vhdl-unit-generator.py -n handshake_mux_0 -o %t/handshake_mux_0.vhd -t mux -p size=2 data_bitwidth=8 index_bitwidth=1 'extra_signals={}' tehb=1
// RUN: python3 %dynamatic_src_root/tools/unit-generators/vhdl/vhdl-unit-generator.py -n handshake_mux_1 -o %t/handshake_mux_1.vhd -t mux -p size=2 data_bitwidth=8 index_bitwidth=1 'extra_signals={}' tehb=0
// RUN: FileCheck %s -input-file %t/handshake_mux_0.vhd --check-prefix=SLOT
// RUN: FileCheck %s -input-file %t/handshake_mux_1.vhd --check-prefix=BARE --implicit-check-not=one_slot_break_r

// The generator is called directly: the export gives a mux without extra
// signals a generic entity (generic-units-5-export.mlir).

// The slot behind a mux's select. TEHB=1 is the unit as it was, the select
// and a one_slot_break_r; TEHB=0 is the select alone under the unit's name,
// for a consumer that cuts ready itself.

// SLOT: entity handshake_mux_0_one_slot_break_r is
// SLOT: entity handshake_mux_0 is
// SLOT: one_slot_break_r : entity work.handshake_mux_0_one_slot_break_r

// BARE: entity handshake_mux_1 is
// BARE: outs       <= sel_data;
// BARE: sel_ready  <= outs_ready;
