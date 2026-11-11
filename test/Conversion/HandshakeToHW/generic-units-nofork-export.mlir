// REQUIRES: ghdl
// RUN: rm -rf %t && mkdir -p %t
// RUN: dynamatic-opt %s --lower-handshake-to-hw > %t/nofork.hw
// RUN: export-rtl %t/nofork.hw %t/vhdl %dynamatic_src_root/data/rtl-config-vhdl.json --dynamatic-path %dynamatic_src_root --hdl vhdl
// RUN: ls %t/vhdl | FileCheck %s
// RUN: cd %t/vhdl && ghdl -i --std=08 *.vhd && ghdl -m --std=08 nofork
// RUN: dynamatic-opt %S/Inputs/module-named-sink.handshake --lower-handshake-to-hw > %t/sink.hw
// RUN: not export-rtl %t/sink.hw %t/collide %dynamatic_src_root/data/rtl-config-vhdl.json --dynamatic-path %dynamatic_src_root --hdl vhdl 2>&1 | FileCheck %s --check-prefix=COLLIDE

// A design with a join and no fork: the join's entity instantiates the
// and_n of logic.vhd, which the forks' entries were alone to ask for. The
// export carries the file and elaborates.
// CHECK: join.vhd
// CHECK: logic.vhd

// A module named as a component it instantiates, whatever the case: its
// file would replace the component's.
// COLLIDE: the module is named as an RTL component the design instantiates ("Sink", in any case)

handshake.func @nofork(%a: !handshake.channel<i8>, %b: !handshake.channel<i8>, %c: !handshake.channel<i1>, %start: !handshake.control<>) -> (!handshake.channel<i8>, !handshake.control<>) attributes {argNames = ["a", "b", "c", "start"], resNames = ["sum", "end"]} {
  %sum = addi %a, %b {handshake.name = "addi0"} : <i8>
  %t, %f = cond_br %c, %sum {handshake.name = "cond_br0"} : <i1>, <i8>
  sink %f {handshake.name = "sink0"} : <i8>
  end {handshake.name = "end0"} %t, %start : <i8>, <>
}
