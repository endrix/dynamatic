// REQUIRES: ghdl
// RUN: rm -rf %t && mkdir -p %t
// RUN: dynamatic-opt %s --lower-handshake-to-hw > %t/genunits.hw
// RUN: export-rtl %t/genunits.hw %t/vhdl %dynamatic_src_root/data/rtl-config-vhdl.json --dynamatic-path %dynamatic_src_root --hdl vhdl
// RUN: FileCheck %s --input-file=%t/vhdl/genunits.vhd
// RUN: ls %t/vhdl | FileCheck %s --check-prefix=FILES
// RUN: cd %t/vhdl && ghdl -i --std=08 *.vhd && ghdl -m --std=08 genunits

// The handshake units whose hand-written generic entity (data/vhdl) is the
// logic their generator writes: one entity for every width and size, two
// where a unit without data has no data port. A unit whose channel carries
// an extra signal has no generic entity -- a generic cannot add a port -- and
// is still generated, here the fork of a speculative channel.

// CHECK-DAG: fork0 : entity work.handshake_fork(arch) generic map(3, 8)
// CHECK-DAG: fork1 : entity work.fork_dataless(arch) generic map(2)
// CHECK-DAG: fork2 : entity work.handshake_fork_{{[0-9]+}}(arch)
// CHECK-DAG: lazy_fork0 : entity work.lazy_fork(arch) generic map(2, 8)
// CHECK-DAG: extui0 : entity work.extui(arch) generic map(8, 16)
// CHECK-DAG: extsi0 : entity work.extsi(arch) generic map(8, 16)
// CHECK-DAG: addi0 : entity work.addi(arch) generic map(16)
// CHECK-DAG: subi0 : entity work.subi(arch) generic map(16)
// CHECK-DAG: andi0 : entity work.andi(arch) generic map(16)
// CHECK-DAG: ori0 : entity work.ori(arch) generic map(16)
// CHECK-DAG: xori0 : entity work.xori(arch) generic map(16)
// CHECK-DAG: cond_br0 : entity work.cond_br(arch) generic map(16)
// CHECK-DAG: cond_br1 : entity work.cond_br_dataless(arch)
// CHECK-DAG: sink0 : entity work.sink(arch) generic map(16)
// CHECK-DAG: sink1 : entity work.sink_dataless(arch)
// CHECK-DAG: source0 : entity work.source(arch)

// Of the units above, only the fork with an extra signal is a generated file.
// FILES-NOT:  handshake_{{(lazy_fork|extui|extsi|addi|subi|andi|ori|xori|cond_br|sink|source)}}_{{[0-9]+}}.vhd
// FILES:      handshake_fork.vhd
// FILES-NEXT: handshake_fork_{{[0-9]+}}.vhd
// FILES-NOT:  handshake_fork_{{[0-9]+}}.vhd

handshake.func @genunits(%a: !handshake.channel<i8>, %c: !handshake.channel<i1>, %s: !handshake.channel<i8, [spec: i1]>, %start: !handshake.control<>) -> (!handshake.channel<i16>, !handshake.channel<i8>, !handshake.channel<i8, [spec: i1]>, !handshake.channel<i8, [spec: i1]>, !handshake.control<>) attributes {argNames = ["a", "c", "s", "start"], resNames = ["word", "byte", "sa", "sb", "end"]} {
  %a0, %a1, %a2 = fork [3] %a {handshake.name = "fork0"} : <i8>
  %st0, %st1 = fork [2] %start {handshake.name = "fork1"} : <>
  %s0, %s1 = fork [2] %s {handshake.name = "fork2"} : <i8, [spec: i1]>
  %l0, %l1 = lazy_fork [2] %a2 {handshake.name = "lazy_fork0"} : <i8>
  %zx = extui %a0 {handshake.name = "extui0"} : <i8> to <i16>
  %sx = extsi %a1 {handshake.name = "extsi0"} : <i8> to <i16>
  %sum = addi %zx, %sx {handshake.name = "addi0"} : <i16>
  %zx2 = extui %l0 {handshake.name = "extui1"} : <i8> to <i16>
  %dif = subi %sum, %zx2 {handshake.name = "subi0"} : <i16>
  %src = source {handshake.name = "source0"} : <>
  %k = constant %src {handshake.name = "constant0", value = 255 : i16} : <>, <i16>
  %k0, %k1, %k2 = fork [3] %k {handshake.name = "fork3"} : <i16>
  %and = andi %dif, %k0 {handshake.name = "andi0"} : <i16>
  %or = ori %and, %k1 {handshake.name = "ori0"} : <i16>
  %xor = xori %or, %k2 {handshake.name = "xori0"} : <i16>
  %c0, %c1 = fork [2] %c {handshake.name = "fork4"} : <i1>
  %t, %f = cond_br %c0, %xor {handshake.name = "cond_br0"} : <i1>, <i16>
  sink %f {handshake.name = "sink0"} : <i16>
  %ct, %cf = cond_br %c1, %st0 {handshake.name = "cond_br1"} : <i1>, <>
  sink %cf {handshake.name = "sink1"} : <>
  sink %ct {handshake.name = "sink2"} : <>
  end {handshake.name = "end0"} %t, %l1, %s0, %s1, %st1 : <i16>, <i8>, <i8, [spec: i1]>, <i8, [spec: i1]>, <>
}
