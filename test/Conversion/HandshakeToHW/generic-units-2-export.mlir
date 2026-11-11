// REQUIRES: ghdl
// RUN: rm -rf %t && mkdir -p %t
// RUN: dynamatic-opt %s --lower-handshake-to-hw > %t/genunits2.hw
// RUN: export-rtl %t/genunits2.hw %t/vhdl %dynamatic_src_root/data/rtl-config-vhdl.json --dynamatic-path %dynamatic_src_root --hdl vhdl
// RUN: FileCheck %s --input-file=%t/vhdl/genunits2.vhd
// RUN: ls %t/vhdl | FileCheck %s --check-prefix=FILES
// RUN: cd %t/vhdl && ghdl -i --std=08 *.vhd && ghdl -m --std=08 genunits2

// The handshake units with a generic entity written from their generator's
// logic (data/vhdl/handshake/generic), and the buffers, whose hand-written
// entities are that logic. A constant has no parameter that shows its
// channel types: its entry says "no-extra-signals", and the speculative one
// is generated, as is every other unit on a speculative value.

// CHECK-DAG: constant0 : entity work.handshake_constant(arch) generic map("00000011", 8)
// CHECK-DAG: constant1 : entity work.handshake_constant(arch) generic map("1", 1)
// CHECK-DAG: constant2 : entity work.handshake_constant_{{[0-9]+}}(arch)
// CHECK-DAG: shli0 : entity work.handshake_shli(arch) generic map(8)
// CHECK-DAG: shrui0 : entity work.handshake_shrui(arch) generic map(40)
// CHECK-DAG: shrsi0 : entity work.handshake_shrsi(arch) generic map(40)
// CHECK-DAG: trunci0 : entity work.handshake_trunci(arch) generic map(40, 8)
// CHECK-DAG: trunci1 : entity work.handshake_trunci_{{[0-9]+}}(arch)
// CHECK-DAG: cmpi0 : entity work.handshake_cmpi(arch) generic map("slt", 8)
// CHECK-DAG: cmpi1 : entity work.handshake_cmpi(arch) generic map("eq", 8)
// CHECK-DAG: select0 : entity work.handshake_select(arch) generic map(8)
// CHECK-DAG: buffer0 : entity work.oehb(arch) generic map(8)
// CHECK-DAG: buffer1 : entity work.tehb(arch) generic map(8)
// CHECK-DAG: buffer2 : entity work.tfifo(arch) generic map(3, 8)
// CHECK-DAG: buffer3 : entity work.oehb_dataless(arch)
// CHECK-DAG: buffer4 : entity work.tehb_dataless(arch)
// CHECK-DAG: buffer5 : entity work.tfifo_dataless(arch) generic map(2)
// CHECK-DAG: buffer6 : entity work.handshake_buffer_{{[0-9]+}}(arch)
// CHECK-DAG: buffer7 : entity work.handshake_buffer_{{[0-9]+}}(arch)

// The generated files of these kinds: the speculative buffer, the buffer of
// a kind with no generic entry here, the speculative constant and trunci.
// FILES:      handshake_buffer_{{[0-9]+}}.vhd
// FILES-NEXT: handshake_buffer_{{[0-9]+}}.vhd
// FILES-NEXT: handshake_cmpi.vhd
// FILES-NEXT: handshake_constant.vhd
// FILES-NEXT: handshake_constant_{{[0-9]+}}.vhd
// FILES-NOT:  handshake_{{(buffer|cmpi|constant|select|shli|shrsi|shrui)}}_{{[0-9]+}}.vhd
// FILES:      handshake_trunci.vhd
// FILES-NEXT: handshake_trunci_{{[0-9]+}}.vhd
// FILES-NOT:  handshake_trunci_{{[0-9]+}}.vhd

handshake.func @genunits2(%a: !handshake.channel<i8>, %b: !handshake.channel<i8>, %w: !handshake.channel<i40>, %s: !handshake.channel<i40, [spec: i1]>, %st: !handshake.control<[spec: i1]>, %start: !handshake.control<>) -> (!handshake.channel<i8>, !handshake.channel<i8>, !handshake.channel<i1>, !handshake.channel<i1>, !handshake.channel<i8, [spec: i1]>, !handshake.channel<i8, [spec: i1]>, !handshake.control<>) attributes {argNames = ["a", "b", "w", "s", "st", "start"], resNames = ["low", "pick", "same", "one", "slow", "sk", "end"]} {
  %a0, %a1, %a2 = fork [3] %a {handshake.name = "fork0"} : <i8>
  %b0, %b1, %b2 = fork [3] %b {handshake.name = "fork1"} : <i8>
  %w0, %w1, %w2 = fork [3] %w {handshake.name = "fork2"} : <i40>
  %src = source {handshake.name = "source0"} : <>
  %k = constant %src {handshake.name = "constant0", value = 3 : i8} : <>, <i8>
  %src1 = source {handshake.name = "source1"} : <>
  %one = constant %src1 {handshake.name = "constant1", value = 1 : i1} : <>, <i1>
  %sk = constant %st {handshake.name = "constant2", value = 3 : i8} : <[spec: i1]>, <i8, [spec: i1]>
  %shl = shli %a0, %k {handshake.name = "shli0"} : <i8>
  %shru = shrui %w0, %w1 {handshake.name = "shrui0"} : <i40>
  %shrs = shrsi %shru, %w2 {handshake.name = "shrsi0"} : <i40>
  %low = trunci %shrs {handshake.name = "trunci0"} : <i40> to <i8>
  %slow = trunci %s {handshake.name = "trunci1"} : <i40, [spec: i1]> to <i8, [spec: i1]>
  %lt = cmpi slt, %a1, %b0 {handshake.name = "cmpi0"} : <i8>
  %same = cmpi eq, %a2, %b1 {handshake.name = "cmpi1"} : <i8>
  %pick = select %lt [%shl, %b2] {handshake.name = "select0"} : <i1>, <i8>
  %p0 = buffer %pick, bufferType = ONE_SLOT_BREAK_DV, numSlots = 1, dvLatency = 1 {handshake.name = "buffer0"} : <i8>
  %p1 = buffer %p0, bufferType = ONE_SLOT_BREAK_R, numSlots = 1, dvLatency = 0 {handshake.name = "buffer1"} : <i8>
  %p2 = buffer %p1, bufferType = FIFO_BREAK_NONE, numSlots = 3, dvLatency = 0 {handshake.name = "buffer2"} : <i8>
  %p3 = buffer %p2, bufferType = FIFO_BREAK_DV, numSlots = 2, dvLatency = 1 {handshake.name = "buffer7"} : <i8>
  %e0 = buffer %start, bufferType = ONE_SLOT_BREAK_DV, numSlots = 1, dvLatency = 1 {handshake.name = "buffer3"} : <>
  %e1 = buffer %e0, bufferType = ONE_SLOT_BREAK_R, numSlots = 1, dvLatency = 0 {handshake.name = "buffer4"} : <>
  %e2 = buffer %e1, bufferType = FIFO_BREAK_NONE, numSlots = 2, dvLatency = 0 {handshake.name = "buffer5"} : <>
  %sb = buffer %slow, bufferType = ONE_SLOT_BREAK_DV, numSlots = 1, dvLatency = 1 {handshake.name = "buffer6"} : <i8, [spec: i1]>
  end {handshake.name = "end0"} %low, %p3, %same, %one, %sb, %sk, %e2 : <i8>, <i8>, <i1>, <i1>, <i8, [spec: i1]>, <i8, [spec: i1]>, <>
}
