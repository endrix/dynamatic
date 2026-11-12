// REQUIRES: ghdl
// RUN: rm -rf %t && mkdir -p %t
// RUN: dynamatic-opt %s --lower-handshake-to-hw > %t/genunits4.hw
// RUN: FileCheck %s --input-file=%t/genunits4.hw --check-prefix=HW
// RUN: export-rtl %t/genunits4.hw %t/vhdl %dynamatic_src_root/data/rtl-config-vhdl.json --dynamatic-path %dynamatic_src_root --hdl vhdl
// RUN: FileCheck %s --input-file=%t/vhdl/genunits4.vhd
// RUN: ls %t/vhdl | FileCheck %s --check-prefix=FILES
// RUN: grep -c one_slot_break_r %t/vhdl/handshake_merge_[0-9]*.vhd | sort -t: -k2 -n | FileCheck %s --check-prefix=SLOT
// RUN: cd %t/vhdl && ghdl -i --std=08 *.vhd && ghdl -m --std=08 genunits4
// RUN: cd %t/vhdl && ghdl -r --std=08 genunits4 --stop-time=1ns --ieee-asserts=disable 2>&1 | FileCheck %s --check-prefix=SIM --allow-empty

// The merge, the join, the blocker and the queue: one generic entity per
// kind (data/vhdl/handshake/generic). A merge is one of four, with or
// without data and with or without the slot behind its arbiter (TEHB); a
// queue's depth, widths and tokens held at reset are generics. A unit on
// speculative channels, and a queue that does not publish both of its
// counts (its ports differ), are generated. (A join of speculative controls
// is not in the test: the configuration never gave its generator the extra
// signals, so it does not elaborate; it still takes the generator.)

// The blocker's width reaches the configuration as a parameter, and the
// queue's on its own: its type serializes with the channel's `space`.
// HW-DAG: hw.name = "handshake.blocker", hw.parameters = {DATA_TYPE = !handshake.channel<i12>, SIZE = 2 : ui32}
// HW-DAG: hw.name = "handshake.queue", hw.parameters = {DATA_TYPE = !handshake.channel<i12, [space: i3 (U)]>, DATA_WIDTH = 12 : ui32,

// CHECK-DAG: merge0 : entity work.handshake_merge(arch) generic map(2, 12)
// CHECK-DAG: merge1 : entity work.handshake_merge(arch) generic map(3, 12)
// CHECK-DAG: merge2 : entity work.handshake_merge_notehb(arch) generic map(2, 12)
// CHECK-DAG: merge3 : entity work.handshake_merge_dataless(arch) generic map(2)
// CHECK-DAG: merge4 : entity work.handshake_merge_notehb_dataless(arch) generic map(3)
// CHECK-DAG: merge5 : entity work.handshake_merge_{{[0-9]+}}(arch)
// CHECK-DAG: merge6 : entity work.handshake_merge_{{[0-9]+}}(arch)
// CHECK-DAG: join0 : entity work.handshake_join(arch) generic map(2)
// CHECK-DAG: join1 : entity work.handshake_join(arch) generic map(3)
// CHECK-DAG: blocker0 : entity work.handshake_blocker(arch) generic map(2, 12)
// CHECK-DAG: blocker1 : entity work.handshake_blocker(arch) generic map(3, 12)
// CHECK-DAG: blocker2 : entity work.handshake_blocker_{{[0-9]+}}(arch)
// CHECK-DAG: queue0 : entity work.handshake_queue(arch) generic map(4, 12, 3, 3, "none")
// CHECK-DAG: queue1 : entity work.handshake_queue(arch) generic map(3, 12, 2, 2, "111111111101,000000000111")
// CHECK-DAG: queue2 : entity work.handshake_queue_{{[0-9]+}}(arch)

// FILES:      handshake_blocker.vhd
// FILES-NEXT: handshake_blocker_{{[0-9]+}}.vhd
// FILES-NOT:  handshake_blocker_{{[0-9]+}}.vhd
// FILES:      handshake_join.vhd
// FILES-NEXT: handshake_merge.vhd
// FILES-NEXT: handshake_merge_{{[0-9]+}}.vhd
// FILES-NEXT: handshake_merge_{{[0-9]+}}.vhd
// FILES-NEXT: handshake_merge_dataless.vhd
// FILES-NEXT: handshake_merge_notehb.vhd
// FILES-NEXT: handshake_merge_notehb_dataless.vhd
// FILES-NEXT: handshake_queue.vhd
// FILES-NEXT: handshake_queue_{{[0-9]+}}.vhd
// FILES-NOT:  handshake_{{(join|merge|queue)}}_{{[0-9]+}}.vhd

// A generated merge is still told whether it keeps its slot: of the two
// speculative ones, one file has a one_slot_break_r.
// SLOT:      handshake_merge_{{[0-9]+}}.vhd:0
// SLOT-NEXT: handshake_merge_{{[0-9]+}}.vhd:{{[1-9]}}

// The queue's assertions (tokens of the data width, no more than slots)
// hold at the start of a run.
// SIM-NOT: handshake_queue:

handshake.func @genunits4(%a: !handshake.channel<i12>, %b: !handshake.channel<i12>, %c: !handshake.channel<i12>, %d: !handshake.channel<i12>, %e: !handshake.channel<i12>, %s: !handshake.channel<i12, [spec: i1]>, %t: !handshake.channel<i12, [spec: i1]>, %qa: !handshake.channel<i12, [space: i3 (U)]>, %qb: !handshake.channel<i12, [space: i2 (U)]>, %qc: !handshake.channel<i12>, %x: !handshake.control<>, %y: !handshake.control<>, %z: !handshake.control<>, %start: !handshake.control<>) -> (!handshake.channel<i12>, !handshake.channel<i12>, !handshake.channel<i12, [spec: i1]>, !handshake.channel<i12, [spec: i1]>, !handshake.channel<i12, [size: i3]>, !handshake.channel<i12, [size: i2]>, !handshake.channel<i12, [size: i2]>, !handshake.control<>, !handshake.control<>) attributes {argNames = ["a", "b", "c", "d", "e", "s", "t", "qa", "qb", "qc", "x", "y", "z", "start"], resNames = ["om", "ob", "oms", "obs", "oqa", "oqb", "oqc", "oc", "end"]} {
  %a0, %a1, %a2 = fork [3] %a {handshake.name = "fork0"} : <i12>
  %b0, %b1, %b2 = fork [3] %b {handshake.name = "fork1"} : <i12>
  %m0 = merge %a0, %b0 {handshake.name = "merge0"} : <i12>
  %m1 = merge %m0, %c, %d {handshake.name = "merge1"} : <i12>
  %m2 = merge %m1, %e {handshake.name = "merge2", hw.parameters = {TEHB = 0 : i64}} : <i12>
  %x0, %x1, %x2 = fork [3] %x {handshake.name = "fork2"} : <>
  %y0, %y1, %y2 = fork [3] %y {handshake.name = "fork3"} : <>
  %z0, %z1 = fork [2] %z {handshake.name = "fork4"} : <>
  %m3 = merge %x0, %y0 {handshake.name = "merge3"} : <>
  %m4 = merge %m3, %x1, %z0 {handshake.name = "merge4", hw.parameters = {TEHB = 0 : i64}} : <>
  %s0, %s1, %s2 = fork [3] %s {handshake.name = "fork5"} : <i12, [spec: i1]>
  %t0, %t1 = fork [2] %t {handshake.name = "fork6"} : <i12, [spec: i1]>
  %m5a = merge %s0, %t0 {handshake.name = "merge5"} : <i12, [spec: i1]>
  %m5 = merge %m5a, %s2 {handshake.name = "merge6", hw.parameters = {TEHB = 0 : i64}} : <i12, [spec: i1]>
  %j0 = join %x2, %y1 {handshake.name = "join0"} : <>
  %j1 = join %j0, %y2, %z1 {handshake.name = "join1"} : <>
  %k0 = blocker %a1, %b1 {handshake.name = "blocker0"} : <i12>
  %k1 = blocker %k0, %a2, %b2 {handshake.name = "blocker1"} : <i12>
  %k2 = blocker %s1, %t1 {handshake.name = "blocker2"} : <i12, [spec: i1]>
  %q0 = handshake.queue %qa {handshake.name = "queue0", numSlots = 4 : i64} : !handshake.channel<i12, [space: i3 (U)]> to !handshake.channel<i12, [size: i3]>
  %q1 = handshake.queue %qb {handshake.name = "queue1", numSlots = 3 : i64, initialTokens = [-3 : i12, 7 : i12]} : !handshake.channel<i12, [space: i2 (U)]> to !handshake.channel<i12, [size: i2]>
  %q2 = handshake.queue %qc {handshake.name = "queue2", numSlots = 2 : i64} : !handshake.channel<i12> to !handshake.channel<i12, [size: i2]>
  %c0 = join %m4, %j1 {handshake.name = "join3"} : <>
  end {handshake.name = "end0"} %m2, %k1, %m5, %k2, %q0, %q1, %q2, %c0, %start : <i12>, <i12>, <i12, [spec: i1]>, <i12, [spec: i1]>, <i12, [size: i3]>, <i12, [size: i2]>, <i12, [size: i2]>, <>, <>
}
