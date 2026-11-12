// REQUIRES: ghdl
// RUN: rm -rf %t && mkdir -p %t
// RUN: dynamatic-opt %s --lower-handshake-to-hw > %t/genunits3.hw
// RUN: export-rtl %t/genunits3.hw %t/vhdl %dynamatic_src_root/data/rtl-config-vhdl.json --dynamatic-path %dynamatic_src_root --hdl vhdl
// RUN: FileCheck %s --input-file=%t/vhdl/genunits3.vhd
// RUN: ls %t/vhdl | FileCheck %s --check-prefix=FILES
// RUN: cd %t/vhdl && ghdl -i --std=08 *.vhd && ghdl -m --std=08 genunits3
// RUN: cd %t/vhdl && ghdl -r --std=08 genunits3 --stop-time=1ns --ieee-asserts=disable 2>&1 | FileCheck %s --check-prefix=SIM --allow-empty

// The init and the sequential multiplier: one generic entity each
// (data/vhdl/handshake/generic). An init's value is a generic, a decimal
// string of any length; an init without data has no value and no generic;
// a speculative init and the pipelined multiplier are generated.

// CHECK-DAG: init0 : entity work.handshake_init(arch) generic map("4", 10)
// CHECK-DAG: init1 : entity work.handshake_init(arch) generic map("0", 10)
// CHECK-DAG: init2 : entity work.handshake_init(arch) generic map("1180591620717411303424", 100)
// CHECK-DAG: init3 : entity work.handshake_init(arch) generic map("1", 1)
// CHECK-DAG: init4 : entity work.handshake_init_dataless(arch)
// CHECK-DAG: init5 : entity work.handshake_init_{{[0-9]+}}(arch)
// CHECK-DAG: init6 : entity work.handshake_init_{{[0-9]+}}(arch)
// CHECK-DAG: mul0 : entity work.handshake_muli_sequential(arch) generic map(4, 32)
// CHECK-DAG: mul1 : entity work.handshake_muli_sequential(arch) generic map(16, 32)
// CHECK-DAG: mul2 : entity work.handshake_muli_{{[0-9]+}}(arch)

// FILES:      handshake_init.vhd
// FILES-NEXT: handshake_init_{{[0-9]+}}.vhd
// FILES-NEXT: handshake_init_{{[0-9]+}}.vhd
// FILES-NEXT: handshake_init_dataless.vhd
// FILES-NEXT: handshake_muli_{{[0-9]+}}.vhd
// FILES-NEXT: handshake_muli_sequential.vhd
// FILES-NOT:  handshake_{{(init|muli)}}_{{[0-9]+}}.vhd

// The entities' assertions (a value that fits, a step within the width)
// hold at the start of a run.
// SIM-NOT: handshake_init:
// SIM-NOT: handshake_muli_sequential:

handshake.func @genunits3(%a: !handshake.channel<i10>, %w: !handshake.channel<i100>, %b: !handshake.channel<i1>, %x: !handshake.channel<i32>, %y: !handshake.channel<i32>, %s: !handshake.channel<i10, [spec: i1]>, %st: !handshake.control<[spec: i1]>, %start: !handshake.control<>) -> (!handshake.channel<i10>, !handshake.channel<i100>, !handshake.channel<i1>, !handshake.channel<i32>, !handshake.channel<i10, [spec: i1]>, !handshake.control<[spec: i1]>, !handshake.control<>) attributes {argNames = ["a", "w", "b", "x", "y", "s", "st", "start"], resNames = ["oa", "ow", "ob", "prod", "os", "ost", "end"]} {
  %i0 = init %a {handshake.name = "init0", hw.parameters = {INIT_VALUE = 4 : i64}} : <i10>
  %i1 = init %i0 {handshake.name = "init1"} : <i10>
  %i2 = init %w {handshake.name = "init2", hw.parameters = {INIT_VALUE = 1180591620717411303424 : i100}} : <i100>
  %i3 = init %b {handshake.name = "init3", hw.parameters = {INIT_TOKEN = true}} : <i1>
  %i4 = init %start {handshake.name = "init4"} : <>
  %i5 = init %s {handshake.name = "init5", hw.parameters = {INIT_VALUE = 4 : i64}} : <i10, [spec: i1]>
  %i6 = init %st {handshake.name = "init6"} : <[spec: i1]>
  %x0, %x1, %x2 = fork [3] %x {handshake.name = "fork0"} : <i32>
  %y0, %y1, %y2 = fork [3] %y {handshake.name = "fork1"} : <i32>
  %p0 = muli %x0, %y0 {handshake.name = "mul0", latency = 9, hw.parameters = {IMPL = "sequential", STEP = 4 : i64}} : <i32>
  %p1 = muli %x1, %y1 {handshake.name = "mul1", latency = 3, hw.parameters = {IMPL = "sequential", STEP = 16 : i64}} : <i32>
  %p2 = muli %x2, %y2 {handshake.name = "mul2", latency = 4} : <i32>
  %q0 = muli %p0, %p1 {handshake.name = "mul3", latency = 9, hw.parameters = {IMPL = "sequential", STEP = 4 : i64}} : <i32>
  %q1 = muli %q0, %p2 {handshake.name = "mul4", latency = 4} : <i32>
  end {handshake.name = "end0"} %i1, %i2, %i3, %q1, %i5, %i6, %i4 : <i10>, <i100>, <i1>, <i32>, <i10, [spec: i1]>, <[spec: i1]>, <>
}
