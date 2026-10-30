// REQUIRES: ghdl, iverilog
// RUN: rm -rf %t && mkdir -p %t
// RUN: dynamatic-opt %s --lower-handshake-to-hw > %t/rc.hw
// RUN: export-rtl %t/rc.hw %t/vhdl %dynamatic_src_root/data/rtl-config-vhdl.json --dynamatic-path %dynamatic_src_root --hdl vhdl
// RUN: cd %t/vhdl && ghdl -a --std=08 types.vhd handshake_race_0.vhd handshake_race_1.vhd rc.vhd && ghdl -e --std=08 rc
// RUN: FileCheck %s --check-prefix=VHDL --input-file=%t/vhdl/rc.vhd
// RUN: export-rtl %t/rc.hw %t/verilog %dynamatic_src_root/data/rtl-config-verilog.json --dynamatic-path %dynamatic_src_root --hdl verilog
// RUN: iverilog -g2012 -o %t/verilog/sim %t/verilog/handshake_race_0.v %t/verilog/handshake_race_1.v %t/verilog/rc.v
// RUN: export-rtl %t/rc.hw %t/smv %dynamatic_src_root/data/rtl-config-smv.json --dynamatic-path %dynamatic_src_root --hdl smv
// RUN: FileCheck %s --check-prefix=SMV --input-file=%t/smv/rc.smv
// RUN: FileCheck %s --check-prefix=SMVUNIT --input-file=%t/smv/handshake_race_0.smv

// A race through the exporter, in each language a configuration names it in:
// the generator's command takes the structure (CANDIDATES) through the shell
// and the generator's parameter parsing, the inputs map onto the arrays
// `tokens` and `flags` element by element, the VHDL elaborates and the
// Verilog compiles, and the SMV instance passes its inputs in the order of
// the model's parameters (each array's payloads, then its valids, tokens
// before flags, then the output's ready). A race with no token is written at
// its decision's width, not at its first input's one bit.

// VHDL:      race0 : entity work.handshake_race_0(arch)
// VHDL:        tokens(0) => t,
// VHDL:        tokens_valid(0) => t_valid,
// VHDL:        tokens_ready(0) => t_ready,
// VHDL:        flags(0) => a,
// VHDL:        flags(1) => b,
// VHDL:        flags(2) => c,

// SMV: VAR race0 : handshake_race_0(race0_tokens_0, race0_tokens_0_valid, race0_flags_0, race0_flags_1, race0_flags_2, race0_flags_0_valid, race0_flags_1_valid, race0_flags_2_valid, race0_outs_ready);
// SMVUNIT: -- candidates: t0/p2:f0:u1/p4:f2:a0,1
// SMVUNIT: MODULE handshake_race_0(tokens_0, tokens_0_valid, flags_0, flags_1, flags_2, flags_0_valid, flags_1_valid, flags_2_valid, outs_ready)
// SMVUNIT: winner : unsigned word [3];
// RUN: FileCheck %s --check-prefix=WIDTH --input-file=%t/vhdl/handshake_race_1.vhd
// WIDTH: outs       : out std_logic_vector(3 - 1 downto 0);
handshake.func @rc(%t: !handshake.channel<i3>, %a: !handshake.channel<i1>,
                   %b: !handshake.channel<i1>, %c: !handshake.channel<i1>,
                   %d: !handshake.channel<i1>, %e: !handshake.channel<i1>, ...)
    -> (!handshake.channel<i3>, !handshake.channel<i3>)
    attributes {argNames = ["t", "a", "b", "c", "d", "e"], resNames = ["out0", "out1"]} {
  %0 = race [%t] [%a, %b, %c] {candidates = [
         {token = 0 : i64},
         {payload = 2 : ui3, flags = array<i64: 0>, unless = array<i64: 1>},
         {payload = 4 : ui3, flags = array<i64: 2>, after = array<i64: 0, 1>}
       ]} : <i3>
  %1 = race [] [%d, %e] {candidates = [
         {payload = 1 : ui3, flags = array<i64: 0>},
         {payload = 4 : ui3, flags = array<i64: 1>, after = array<i64: 0>}
       ]} : <i3>
  end %0, %1 : <i3>, <i3>
}
