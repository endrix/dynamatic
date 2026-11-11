// REQUIRES: ghdl
// RUN: rm -rf %t && mkdir -p %t
// RUN: dynamatic-opt %s --lower-handshake-to-hw > %t/raw.hw
// RUN: export-rtl %t/raw.hw %t/vhdl %dynamatic_src_root/data/rtl-config-vhdl.json --dynamatic-path %dynamatic_src_root --hdl vhdl
// RUN: FileCheck %s --input-file=%t/vhdl/raw.vhd
// RUN: ls %t/vhdl | FileCheck %s --check-prefix=FILES
// RUN: cd %t/vhdl && ghdl -a --std=08 arith_*.vhd handshake_*.vhd raw.vhd && ghdl -e --std=08 raw

// arith on raw wires through the exporter: one generic entity per operation,
// whatever its width, its predicate or its value. Two constants and two
// comparisons are two external modules each and one file each. A string
// parameter is written as a string literal (a bit string for the constant's
// value, which would read as a decimal number unquoted), and a one-bit wire,
// a scalar in the module, is associated with element 0 of the unit's port,
// a vector at every width. The exported design elaborates, which binds every
// generic and every port.

// CHECK:      constant0 : entity work.arith_constant(arch) generic map("00000011", 8)
// CHECK:        outs => constant0_outs
// CHECK:      constant1 : entity work.arith_constant(arch) generic map("00000101", 8)
// CHECK:      constant2 : entity work.arith_constant(arch) generic map("1", 1)
// CHECK:        outs(0) => constant2_outs
// CHECK:      cmpi0 : entity work.arith_cmpi(arch) generic map("eq", 8)
// CHECK:        result(0) => cmpi0_result
// CHECK:      select0 : entity work.arith_select(arch) generic map(8)
// CHECK:        condition(0) => cmpi0_result,
// CHECK-NEXT:   true_value => unbundle1_data,
// CHECK:        clk => clk,
// CHECK-NEXT:   rst => rst,
// CHECK:      cmpi1 : entity work.arith_cmpi(arch) generic map("ult", 8)
// CHECK:      extui0 : entity work.arith_extui(arch) generic map(1, 8)
// CHECK:        ins(0) => cmpi1_result,
// CHECK:      trunci0 : entity work.arith_trunci(arch) generic map(8, 1)
// CHECK:        outs(0) => trunci0_outs
// CHECK:      xori0 : entity work.arith_xori(arch) generic map(1)
// CHECK:        lhs(0) => trunci0_outs,
// CHECK-NEXT:   rhs(0) => constant2_outs,
// CHECK:        result(0) => xori0_result

// The fifteen operations, each through its entry of the configuration; the
// shifts at forty bits, where the amount is read in two parts.
// CHECK:      extsi0 : entity work.arith_extsi(arch) generic map(8, 40)
// CHECK:      addi0 : entity work.arith_addi(arch) generic map(40)
// CHECK:      subi0 : entity work.arith_subi(arch) generic map(40)
// CHECK:      muli0 : entity work.arith_muli(arch) generic map(40)
// CHECK:      ori0 : entity work.arith_ori(arch) generic map(40)
// CHECK:      shli0 : entity work.arith_shli(arch) generic map(40)
// CHECK:      shrui0 : entity work.arith_shrui(arch) generic map(40)
// CHECK:      shrsi0 : entity work.arith_shrsi(arch) generic map(40)

// FILES-NOT:  arith_{{[a-z]+}}_{{[0-9]+}}.vhd
// FILES:      arith_addi.vhd
// FILES-NEXT: arith_andi.vhd
// FILES-NEXT: arith_cmpi.vhd
// FILES-NEXT: arith_constant.vhd
// FILES-NEXT: arith_extsi.vhd
// FILES-NEXT: arith_extui.vhd
// FILES-NEXT: arith_muli.vhd
// FILES-NEXT: arith_ori.vhd
// FILES-NEXT: arith_select.vhd
// FILES-NEXT: arith_shli.vhd
// FILES-NEXT: arith_shrsi.vhd
// FILES-NEXT: arith_shrui.vhd
// FILES-NEXT: arith_subi.vhd
// FILES-NEXT: arith_trunci.vhd
// FILES-NEXT: arith_xori.vhd
// FILES-NOT:  arith_{{[a-z]+}}_{{[0-9]+}}.vhd

handshake.func @raw(%a: !handshake.channel<i8>, %b: !handshake.channel<i8>, %c: !handshake.channel<i40>, %start: !handshake.control<>) -> (!handshake.channel<i1>, !handshake.channel<i40>, !handshake.control<>) attributes {argNames = ["a", "b", "c", "start"], resNames = ["flag", "word", "end"]} {
  %c3 = arith.constant {handshake.name = "constant0"} 3 : i8
  %c5 = arith.constant {handshake.name = "constant1"} 5 : i8
  %one = arith.constant {handshake.name = "constant2"} true
  %ctrlA, %dataA = unbundle %a {handshake.name = "unbundle0"} : <i8> to _
  %ctrlB, %dataB = unbundle %b {handshake.name = "unbundle1"} : <i8> to _
  %ctrlC, %dataC = unbundle %c {handshake.name = "unbundle2"} : <i40> to _
  %eq = arith.cmpi eq, %dataA, %c3 {handshake.name = "cmpi0"} : i8
  %sel = arith.select %eq, %dataB, %dataA {handshake.name = "select0"} : i8
  %lt = arith.cmpi ult, %sel, %c5 {handshake.name = "cmpi1"} : i8
  %wide = arith.extui %lt {handshake.name = "extui0"} : i1 to i8
  %and = arith.andi %wide, %sel {handshake.name = "andi0"} : i8
  %bit = arith.trunci %and {handshake.name = "trunci0"} : i8 to i1
  %not = arith.xori %bit, %one {handshake.name = "xori0"} : i1
  %sext = arith.extsi %dataA {handshake.name = "extsi0"} : i8 to i40
  %sum = arith.addi %dataC, %sext {handshake.name = "addi0"} : i40
  %dif = arith.subi %sext, %dataC {handshake.name = "subi0"} : i40
  %mul = arith.muli %dif, %sext {handshake.name = "muli0"} : i40
  %or = arith.ori %mul, %sum {handshake.name = "ori0"} : i40
  %shl = arith.shli %or, %dataC {handshake.name = "shli0"} : i40
  %shru = arith.shrui %shl, %sext {handshake.name = "shrui0"} : i40
  %shrs = arith.shrsi %shru, %dataC {handshake.name = "shrsi0"} : i40
  %j = join %ctrlA, %ctrlB, %ctrlC {handshake.name = "join0"} : <>
  %jf, %jw = lazy_fork [2] %j {handshake.name = "fork0"} : <>
  %out = bundle %jf, %not {handshake.name = "bundle0"} : _ to <i1>
  %word = bundle %jw, %shrs {handshake.name = "bundle1"} : _ to <i40>
  end {handshake.name = "end0"} %out, %word, %start : <i1>, <i40>, <>
}
