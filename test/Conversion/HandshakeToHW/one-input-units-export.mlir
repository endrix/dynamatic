// REQUIRES: ghdl
// RUN: rm -rf %t && mkdir -p %t
// RUN: dynamatic-opt %S/one-input-units.mlir --lower-handshake-to-hw > %t/one.hw
// RUN: export-rtl %t/one.hw %t/vhdl %dynamatic_src_root/data/rtl-config-vhdl.json --dynamatic-path %dynamatic_src_root --hdl vhdl
// RUN: FileCheck %s --input-file=%t/vhdl/one.vhd
// RUN: cd %t/vhdl && ghdl -i --std=08 *.vhd && ghdl -m --std=08 one
// RUN: dynamatic-opt %s --lower-handshake-to-hw > %t/fork.hw
// RUN: export-rtl %t/fork.hw %t/smv %dynamatic_src_root/data/rtl-config-smv.json --dynamatic-path %dynamatic_src_root --hdl smv
// RUN: FileCheck %s --input-file=%t/smv/onefork.smv --check-prefix=SMV
// RUN: cat %t/smv/handshake_fork_*.smv | FileCheck %s --check-prefix=SMVUNIT

// The units of one-input-units.mlir, a merge, a mux, a control merge, a
// blocker and a join of one input and a fork of one output, exported: each
// is bound as an array of one and the design elaborates. It did not: the
// netlist bound a vector to the array.

// CHECK-DAG: merge0 : entity work.handshake_merge(arch) generic map(1, 8, 1)
// CHECK-DAG: mux0 : entity work.handshake_mux(arch) generic map(1, 8, 1, 1)
// CHECK-DAG: cmerge0 : entity work.handshake_control_merge(arch) generic map(1, 8, 1)
// CHECK-DAG: blocker0 : entity work.handshake_blocker(arch) generic map(1, 8)
// CHECK-DAG: fork0 : entity work.handshake_fork(arch) generic map(1, 8)
// CHECK-DAG: merge1 : entity work.handshake_merge_dataless(arch) generic map(1, 1)
// CHECK-DAG: join0 : entity work.handshake_join(arch) generic map(1)
// CHECK-DAG: fork1 : entity work.fork_dataless(arch) generic map(1)
// CHECK-DAG: ins(0) => a,
// CHECK-DAG: ins_valid(0) => a_valid,
// CHECK-DAG: outs(0) => fork0_outs_0,
// CHECK-DAG: outs_valid(0) => fork0_outs_0_valid,

// The SMV export of a fork of one output names the output as the fork's
// module defines it. It named `fork0.outs`, which the module does not have.
// SMVUNIT: outs_0 := ins;
// SMV: fork0.outs_0;
// SMV: fork0.outs_0_valid;

handshake.func @onefork(%e: !handshake.channel<i8>, %start: !handshake.control<>) -> (!handshake.channel<i8>, !handshake.control<>) attributes {argNames = ["e", "start"], resNames = ["o", "end"]} {
  %fo = fork [1] %e {handshake.name = "fork0"} : <i8>
  end {handshake.name = "end0"} %fo, %start : <i8>, <>
}
