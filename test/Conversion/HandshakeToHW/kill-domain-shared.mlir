// RUN: dynamatic-opt %s --lower-handshake-to-hw | FileCheck %s

// A KILL DOMAIN WITH TWO COMMITS (handshake.commit): the shape of a guard
// that two states of an actor share. Each state decides on its own channel
// (d0, d1) and stops its private guard (domains 0 and 1); the shared guard is
// domain 2, stopped by either decision: on each channel a second commit, in
// series after the state's own, names domain 2. A commit is a wire, so the
// two in series see the same transfer. Domain 2's kill is the OR of its two
// commits' kills: one kill_or instance, `kill_domain2`, whose output is the
// reset of every unit of domain 2 (its argument latch, its start slot, the
// slot the placer put after the latch) and the kill input of its load. The
// shared guard's stand-in takes both kills, each private one its own. Domains
// 0 and 1 keep their one commit's kill, and no unit is reset by another
// domain's.

// CHECK-LABEL: hw.module @shared_guard
// CHECK-DAG: hw.instance "buffer0" @{{.*}}(ins: %a0: {{.*}}, clk: %clk: i1, rst: %[[K0:commit0.kill]]: i1)
// CHECK-DAG: hw.instance "buffer1" @{{.*}}(ins: %a1: {{.*}}, clk: %clk: i1, rst: %[[K1:commit2.kill]]: i1)
// CHECK-DAG: %[[K2:kill_domain2.outs]] = hw.instance "kill_domain2" @[[OR:kill_or_2]](ins_0: %commit1.kill: i1, ins_1: %commit3.kill: i1) -> (outs: i1)
// CHECK-DAG: hw.instance "buffer2" @{{.*}}(ins: %a2: {{.*}}, clk: %clk: i1, rst: %[[K2]]: i1)
// CHECK-DAG: hw.instance "buffer3" @{{.*}}(ins: %s2: {{.*}}, clk: %clk: i1, rst: %[[K2]]: i1)
// CHECK-DAG: hw.instance "buffer4" @{{.*}}(ins: %buffer2.outs: {{.*}}, clk: %clk: i1, rst: %[[K2]]: i1)
// CHECK-DAG: hw.instance "load0" @{{.*}}(addrIn: %buffer4.outs: {{.*}}, dataFromMem: {{.*}}, kill: %[[K2]]: i1, clk: %clk: i1, rst: %rst: i1)
// CHECK-DAG: hw.instance "sink0" @{{.*}}(ins: %buffer3.outs: {{.*}}, clk: %clk: i1, rst: %[[K2]]: i1)
// CHECK-DAG: hw.instance "trunci0" @{{.*}}(ins: %load0.dataOut: {{.*}}, clk: %clk: i1, rst: %[[K2]]: i1)
// CHECK-DAG: %commit0.outs, %commit0.kill = hw.instance "commit0" @{{.*}}(ins: %d0: {{.*}}, clk: %clk: i1, rst: %rst: i1)
// CHECK-DAG: %commit1.outs, %commit1.kill = hw.instance "commit1" @{{.*}}(ins: %commit0.outs: {{.*}}, clk: %clk: i1, rst: %rst: i1)
// CHECK-DAG: %commit2.outs, %commit2.kill = hw.instance "commit2" @{{.*}}(ins: %d1: {{.*}}, clk: %clk: i1, rst: %rst: i1)
// CHECK-DAG: %commit3.outs, %commit3.kill = hw.instance "commit3" @{{.*}}(ins: %commit2.outs: {{.*}}, clk: %clk: i1, rst: %rst: i1)
// CHECK-DAG: hw.instance "stand_in0" @{{.*}}(ins: %buffer0.outs: {{.*}}, kill_0: %[[K0]]: i1, clk: %clk: i1, rst: %rst: i1)
// CHECK-DAG: hw.instance "stand_in1" @{{.*}}(ins: %buffer1.outs: {{.*}}, kill_0: %[[K1]]: i1, clk: %clk: i1, rst: %rst: i1)
// CHECK-DAG: hw.instance "stand_in2" @[[SI2:.*]](ins: %trunci0.outs: {{.*}}, kill_0: %commit1.kill: i1, kill_1: %commit3.kill: i1, clk: %clk: i1, rst: %rst: i1)
// CHECK-NOT: handshake.kill_domain
// CHECK-NOT: handshake.kill_source
// CHECK-DAG: hw.module.extern @[[OR]](in %ins_0 : i1, in %ins_1 : i1, out outs : i1) attributes {hw.name = "kill_or", hw.parameters = {SIZE = 2 : ui32}}
// CHECK-DAG: hw.module.extern @[[SI2]](in %ins : {{.*}}, in %kill_0 : i1, in %kill_1 : i1, in %clk : i1, in %rst : i1, {{.*}}) attributes {hw.name = "handshake.stand_in", hw.parameters = {DATA_TYPE = !handshake.channel<i1>, SIZE = 2 : ui32}}

handshake.func @shared_guard(%a0: !handshake.channel<i1>, %a1: !handshake.channel<i1>,
                       %a2: !handshake.channel<i2>, %s2: !handshake.control<>,
                       %d0: !handshake.channel<i3>, %d1: !handshake.channel<i3>,
                       %mem: memref<4xi8>, %memStart: !handshake.control<>,
                       %ctrlEnd: !handshake.control<>, %start: !handshake.control<>, ...)
    -> (!handshake.channel<i1>, !handshake.channel<i1>, !handshake.channel<i1>,
        !handshake.channel<i3>, !handshake.channel<i3>, !handshake.control<>,
        !handshake.control<>)
    attributes {argNames = ["a0", "a1", "a2", "s2", "d0", "d1", "mem", "memStart", "ctrlEnd", "start"],
                resNames = ["flag0", "flag1", "flag2", "dec0", "dec1", "memEnd", "end"]} {
  // state 0's private guard (domain 0) and state 1's (domain 1)
  %l0 = buffer %a0, bufferType = ONE_SLOT_BREAK_R, numSlots = 1, dvLatency = 0 {handshake.kill_domain = 0 : ui32} : <i1>
  %l1 = buffer %a1, bufferType = ONE_SLOT_BREAK_R, numSlots = 1, dvLatency = 0 {handshake.kill_domain = 1 : ui32} : <i1>
  // the shared guard (domain 2): a latch, a start slot, a slot the placer
  // put after the latch (it joins the domain), a load
  %l2 = buffer %a2, bufferType = ONE_SLOT_BREAK_R, numSlots = 1, dvLatency = 0 {handshake.kill_domain = 2 : ui32} : <i2>
  %st = buffer %s2, bufferType = ONE_SLOT_BREAK_R, numSlots = 1, dvLatency = 0 {handshake.kill_domain = 2 : ui32} : <>
  %placed = buffer %l2, bufferType = ONE_SLOT_BREAK_DV, numSlots = 1, dvLatency = 1 : <i2>
  %ldAddr, %ldData = load [%placed] %memData {handshake.bb = 0 : ui32, handshake.kill_domain = 2 : ui32} : <i2>, <i8>, <i2>, <i8>
  %memData, %memEnd = mem_controller [%mem : memref<4xi8>] %memStart (%ldAddr) %ctrlEnd {connectedBlocks = [0 : i32]} : (!handshake.channel<i2>) -> !handshake.channel<i8>
  sink %st {handshake.kill_domain = 2 : ui32} : <>
  %w = trunci %ldData {handshake.kill_domain = 2 : ui32} : <i8> to <i1>
  // state 0's decision stops domains 0 and 2, state 1's domains 1 and 2
  %o0, %k0 = commit %d0 : <i3>
  %o0s, %k0s = commit %o0 {domain = 2 : ui32} : <i3>
  %o1, %k1 = commit %d1 {domain = 1 : ui32} : <i3>
  %o1s, %k1s = commit %o1 {domain = 2 : ui32} : <i3>
  %flag0 = stand_in %l0, %k0 : <i1>
  %flag1 = stand_in %l1, %k1 : <i1>
  %flag2 = stand_in %w, %k0s, %k1s : <i1>
  end %flag0, %flag1, %flag2, %o0s, %o1s, %memEnd, %start : <i1>, <i1>, <i1>, <i3>, <i3>, <>, <>
}
