// REQUIRES: ghdl
// RUN: rm -rf %t && mkdir -p %t
// RUN: dynamatic-opt %s --lower-handshake-to-hw > %t/specjoin.hw
// RUN: export-rtl %t/specjoin.hw %t/vhdl %dynamatic_src_root/data/rtl-config-vhdl.json --dynamatic-path %dynamatic_src_root --hdl vhdl
// RUN: FileCheck %s --input-file=%t/vhdl/specjoin.vhd
// RUN: cat %t/vhdl/handshake_join_*.vhd | FileCheck %s --check-prefix=UNIT
// RUN: cd %t/vhdl && ghdl -i --std=08 *.vhd %S/Inputs/join-extra-signals-tb.vhd && ghdl -m --std=08 specjoin && ghdl -m --std=08 join_extra_signals_tb
// RUN: cd %t/vhdl && ghdl -r --std=08 join_extra_signals_tb 2>&1 | FileCheck %s --check-prefix=SIM

// A join whose controls carry an extra signal: the netlist connects a spec
// bit per input and one on the output, so the generated join must declare
// them, the inputs' valid and ready as vectors of SIZE beside them. The
// output's spec bit is the OR of the inputs' (the signal manager's
// forwarding of spec), and the join's handshake is the plain join's.

// CHECK:      join0 : entity work.handshake_join_{{[0-9]+}}(arch)
// CHECK:        ins_0_spec => a_spec,
// CHECK-NEXT:   ins_1_spec => b_spec,
// CHECK:        outs_spec => join0_outs_spec
// CHECK:      join1 : entity work.handshake_join_{{[0-9]+}}(arch)
// CHECK:        ins_0_spec => c_spec,
// CHECK-NEXT:   ins_1_spec => d_spec,
// CHECK-NEXT:   ins_2_spec => e_spec,
// CHECK:        outs_spec => join1_outs_spec

// UNIT-DAG: ins_valid : in std_logic_vector(2 - 1 downto 0);
// UNIT-DAG: ins_1_spec : in std_logic_vector(1 - 1 downto 0);
// UNIT-DAG: outs_spec <= ins_0_spec or ins_1_spec;
// UNIT-DAG: ins_valid : in std_logic_vector(3 - 1 downto 0);
// UNIT-DAG: ins_2_spec : in std_logic_vector(1 - 1 downto 0);
// UNIT-DAG: outs_spec <= ins_0_spec or ins_1_spec or ins_2_spec;

// Every combination of the inputs' valid and spec bits and the outputs'
// ready bits, checked; the counts are the transfers seen on each output.
// SIM: ab: 384 speculative, 128 not; cde: 224 speculative, 32 not

handshake.func @specjoin(%a: !handshake.control<[spec: i1]>, %b: !handshake.control<[spec: i1]>, %c: !handshake.control<[spec: i1]>, %d: !handshake.control<[spec: i1]>, %e: !handshake.control<[spec: i1]>) -> (!handshake.control<[spec: i1]>, !handshake.control<[spec: i1]>) attributes {argNames = ["a", "b", "c", "d", "e"], resNames = ["ab", "cde"]} {
  %ab = join %a, %b {handshake.name = "join0"} : <[spec: i1]>
  %cde = join %c, %d, %e {handshake.name = "join1"} : <[spec: i1]>
  end {handshake.name = "end0"} %ab, %cde : <[spec: i1]>, <[spec: i1]>
}
