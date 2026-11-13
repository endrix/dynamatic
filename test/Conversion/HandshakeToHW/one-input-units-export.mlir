// REQUIRES: ghdl
// RUN: rm -rf %t && mkdir -p %t
// RUN: dynamatic-opt %S/one-input-units.mlir --lower-handshake-to-hw > %t/one.hw
// RUN: export-rtl %t/one.hw %t/vhdl %dynamatic_src_root/data/rtl-config-vhdl.json --dynamatic-path %dynamatic_src_root --hdl vhdl
// RUN: FileCheck %s --input-file=%t/vhdl/one.vhd
// RUN: cd %t/vhdl && ghdl -i --std=08 *.vhd && ghdl -m --std=08 one
// RUN: sed -n "/^\/\/ BEGIN smv$/,/^\/\/ END$/p" %s > %t/smv.mlir && dynamatic-opt %t/smv.mlir --lower-handshake-to-hw > %t/smv.hw
// RUN: export-rtl %t/smv.hw %t/smv %dynamatic_src_root/data/rtl-config-smv.json --dynamatic-path %dynamatic_src_root --hdl smv
// RUN: FileCheck %s --input-file=%t/smv/onesmv.smv --check-prefix=SMV
// RUN: sed -n "/^\/\/ BEGIN props$/,/^\/\/ END$/p" %s > %t/props.mlir && dynamatic-opt %t/props.mlir --handshake-annotate-properties="json-path=%t/props.json annotate-invariants=true" > %t/annotated.mlir
// RUN: dynamatic-opt %t/annotated.mlir --lower-handshake-to-hw > %t/props.hw
// RUN: export-rtl %t/props.hw %t/smvprops %dynamatic_src_root/data/rtl-config-smv.json --dynamatic-path %dynamatic_src_root --hdl smv --property-database %t/props.json
// RUN: FileCheck %s --input-file=%t/smvprops/oneprops.smv --check-prefix=PROPS
// RUN: cat %t/smvprops/handshake_fork_*.smv | FileCheck %s --check-prefix=FORK

// The units of one-input-units.mlir, exported: a merge, a first, a mux, a
// control merge, a blocker and a join of one input and a fork of one output,
// with and without data, and a merge and a fork on speculative channels,
// which are generated. Each is bound as an array of one, data, valid and
// ready, and the design elaborates. It did not: the netlist bound a vector
// to the array.

// CHECK:      merge0 : entity work.handshake_merge(arch) generic map(1, 8, 1)
// CHECK:        ins(0) => a,
// CHECK-NEXT:   ins_valid(0) => a_valid,
// CHECK-NEXT:   ins_ready(0) => a_ready,
// CHECK:      mux0 : entity work.handshake_mux(arch) generic map(1, 8, 1, 1)
// CHECK:        ins(0) => b,
// CHECK-NEXT:   ins_valid(0) => b_valid,
// CHECK-NEXT:   ins_ready(0) => b_ready,
// CHECK:      cmerge0 : entity work.handshake_control_merge(arch) generic map(1, 8, 1)
// CHECK:        ins(0) => c,
// CHECK-NEXT:   ins_valid(0) => c_valid,
// CHECK-NEXT:   ins_ready(0) => c_ready,
// CHECK:      blocker0 : entity work.handshake_blocker(arch) generic map(1, 8)
// CHECK:        ins(0) => d,
// CHECK-NEXT:   ins_valid(0) => d_valid,
// CHECK-NEXT:   ins_ready(0) => d_ready,
// CHECK:      fork0 : entity work.handshake_fork(arch) generic map(1, 8)
// CHECK:        outs(0) => fork0_outs_0,
// CHECK-NEXT:   outs_valid(0) => fork0_outs_0_valid,
// CHECK-NEXT:   outs_ready(0) => fork0_outs_0_ready
// CHECK:      lfork0 : entity work.lazy_fork(arch) generic map(1, 8)
// CHECK:        outs(0) => lfork0_outs_0,
// CHECK-NEXT:   outs_valid(0) => lfork0_outs_0_valid,
// CHECK-NEXT:   outs_ready(0) => lfork0_outs_0_ready
// CHECK:      first0 : entity work.handshake_first_{{[0-9]+}}(arch)
// CHECK:        ins(0) => i,
// CHECK-NEXT:   ins_valid(0) => i_valid,
// CHECK-NEXT:   ins_ready(0) => i_ready,
// CHECK:      merge3 : entity work.handshake_merge_{{[0-9]+}}(arch)
// CHECK:        ins(0) => s,
// CHECK-NEXT:   ins_valid(0) => s_valid,
// CHECK-NEXT:   ins_ready(0) => s_ready,
// CHECK:      fork2 : entity work.handshake_fork_{{[0-9]+}}(arch)
// CHECK:        outs(0) => fork2_outs_0,
// CHECK-NEXT:   outs_valid(0) => fork2_outs_0_valid,
// CHECK-NEXT:   outs_ready(0) => fork2_outs_0_ready,
// CHECK:      merge1 : entity work.handshake_merge_dataless(arch) generic map(1, 1)
// CHECK:        ins_valid(0) => x_valid,
// CHECK-NEXT:   ins_ready(0) => x_ready,
// CHECK:      join0 : entity work.handshake_join(arch) generic map(1)
// CHECK:        ins_valid(0) => y_valid,
// CHECK-NEXT:   ins_ready(0) => y_ready,
// CHECK:      fork1 : entity work.fork_dataless(arch) generic map(1)
// CHECK:        outs_valid(0) => fork1_outs_0_valid,
// CHECK-NEXT:   outs_ready(0) => fork1_outs_0_ready

// The SMV export names a lone input and a lone output as the units' modules
// define them. It named `merge0.ins_ready` and `fork0.outs`, which no module
// has.
// SMV-DAG: := merge0.ins_0_ready;
// SMV-DAG: := mux0.ins_0_ready;
// SMV-DAG: := cmerge0.ins_0_ready;
// SMV-DAG: handshake_buffer_{{[0-9]+}}(fork0.outs_0, fork0.outs_0_valid,

// The formal properties of a fork of one output name its signals the same
// way: they are written from the operation's names, as the netlist is.
// FORK:  outs_0_sent :=
// PROPS: fork0.outs_0_sent
// PROPS: fork0.outs_0_valid -> buffer0.ins_ready

// BEGIN smv
handshake.func @onesmv(%a: !handshake.channel<i8>, %b: !handshake.channel<i8>, %c: !handshake.channel<i8>, %e: !handshake.channel<i8>, %sel: !handshake.channel<i1>, %start: !handshake.control<>) -> (!handshake.channel<i8>, !handshake.channel<i8>, !handshake.channel<i8>, !handshake.channel<i1>, !handshake.channel<i8>, !handshake.control<>) attributes {argNames = ["a", "b", "c", "e", "sel", "start"], resNames = ["om", "ox", "oc", "oi", "ofk", "end"]} {
  %m = merge %a {handshake.name = "merge0"} : <i8>
  %mx = mux %sel [%b] {handshake.name = "mux0"} : <i1>, [<i8>] to <i8>
  %cm, %ci = control_merge [%c] {handshake.name = "cmerge0"} : [<i8>] to <i8>, <i1>
  %fo = fork [1] %e {handshake.name = "fork0"} : <i8>
  %bf = buffer %fo, bufferType = ONE_SLOT_BREAK_DV, numSlots = 1, dvLatency = 1 {handshake.name = "buffer0"} : <i8>
  end {handshake.name = "end0"} %m, %mx, %cm, %ci, %bf, %start : <i8>, <i8>, <i8>, <i1>, <i8>, <>
}
// END
// BEGIN props
handshake.func @oneprops(%e: !handshake.channel<i8>, %start: !handshake.control<>) -> (!handshake.channel<i8>, !handshake.control<>) attributes {argNames = ["e", "start"], resNames = ["o", "end"]} {
  %fo = fork [1] %e {handshake.name = "fork0"} : <i8>
  %bf = buffer %fo, bufferType = ONE_SLOT_BREAK_DV, numSlots = 1, dvLatency = 1 {handshake.name = "buffer0"} : <i8>
  end {handshake.name = "end0"} %bf, %start : <i8>, <>
}
// END
