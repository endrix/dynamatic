// REQUIRES: ghdl, iverilog
// RUN: rm -rf %t && mkdir -p %t
// RUN: dynamatic-opt %S/kill-at-valid.mlir --lower-handshake-to-hw > %t/forms.hw
// RUN: export-rtl %t/forms.hw %t/vhdl %dynamatic_src_root/data/rtl-config-vhdl.json --dynamatic-path %dynamatic_src_root --hdl vhdl
// RUN: cd %t/vhdl && ghdl -i --std=08 *.vhd && ghdl -m --std=08 forms
// RUN: cat %t/vhdl/handshake_commit_*.vhd | FileCheck %s --check-prefix=COMMIT
// RUN: cat %t/vhdl/handshake_race_*.vhd | FileCheck %s --check-prefix=RACE
// RUN: export-rtl %t/forms.hw %t/verilog %dynamatic_src_root/data/rtl-config-verilog.json --dynamatic-path %dynamatic_src_root --hdl verilog
// RUN: iverilog -g2012 -o %t/verilog/sim %t/verilog/*.v
// RUN: cat %t/verilog/*.v | FileCheck %s --check-prefix=VCOMMIT
// RUN: export-rtl %t/forms.hw %t/smv %dynamatic_src_root/data/rtl-config-smv.json --dynamatic-path %dynamatic_src_root --hdl smv
// RUN: cat %t/smv/*.smv | FileCheck %s --check-prefix=SMV

// The two forms through the exporter, in each configuration it reads: the
// commit with `kill_at_valid` is written with its flip-flop and its kill from
// the valid alone (the Verilog configuration, which emits a static file for
// the transfer's commit, writes it from the generator; the vivado one does the
// same, and is not read here: its `timing` parameters are not export-rtl's),
// the transfer's commit as before; the race with `reopen_after_taken` reopens its inputs on
// `emitted` alone, the plain race on `emitted or outs_ready`. Everything
// elaborates or compiles.

// COMMIT-DAG: kill       <= rst or (ins_valid and not killed);
// COMMIT-DAG: killed <= ins_valid and not outs_ready;
// COMMIT-DAG: kill       <= rst or (ins_valid and outs_ready);

// RACE-DAG: done_wo <= others_in and (2 - 1 downto 0 => emitted);
// RACE-DAG: done_wo <= others_in and (2 - 1 downto 0 => (emitted or outs_ready));

// VCOMMIT-DAG: assign kill       = rst | (ins_valid & ~killed);
// VCOMMIT-DAG: assign kill       = rst | (ins_valid & outs_ready);
// VCOMMIT-DAG: wire [2 - 1 : 0] done_wo = others_in & {2{emitted}};
// VCOMMIT-DAG: wire [2 - 1 : 0] done_wo = others_in & {2{emitted | outs_ready}};

// SMV-DAG: kill := ins_valid & !killed;
// SMV-DAG: kill := ins_valid & outs_ready;
// SMV-DAG: done_wo_0 := others_in_0 & emitted;
// SMV-DAG: done_wo_0 := others_in_0 & (emitted | outs_ready);
