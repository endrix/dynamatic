// RUN: rm -rf %t && mkdir -p %t
// RUN: python3 %dynamatic_src_root/tools/unit-generators/vhdl/vhdl-unit-generator.py -n handshake_merge_0 -o %t/handshake_merge_0.vhd -t merge -p size=2 bitwidth=8 'extra_signals={}' tehb=1
// RUN: python3 %dynamatic_src_root/tools/unit-generators/vhdl/vhdl-unit-generator.py -n handshake_merge_1 -o %t/handshake_merge_1.vhd -t merge -p size=2 bitwidth=8 'extra_signals={}' tehb=0
// RUN: FileCheck %s -input-file %t/handshake_merge_0.vhd --check-prefix=SLOT
// RUN: FileCheck %s -input-file %t/handshake_merge_1.vhd --check-prefix=BARE

// The generator is called directly: the export gives a merge without extra
// signals a generic entity (generic-units-4-export.mlir).

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
