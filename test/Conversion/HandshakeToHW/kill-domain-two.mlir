// RUN: dynamatic-opt %s --lower-handshake-to-hw | FileCheck %s

// TWO KILL DOMAINS, one commit each (handshake.commit): each unit's reset is
// its own domain's commit's kill, never the other's. Domain 0 is a guard with
// a body (its argument latch, its start slot, the predicate's instance, whose
// end a sink of the domain takes); domain 1 a guard that reads memory (its
// address latch, the load, the narrowing of its word). Each domain's stand-in
// takes its own commit's kill. The commits, the stand-ins and the memory
// controller keep the module's reset.

// CHECK-LABEL: hw.module @two
// CHECK-DAG: hw.instance "buffer0" @{{.*}}(ins: %a: {{.*}}, clk: %clk: i1, rst: %[[K0:commit0.kill]]: i1)
// CHECK-DAG: hw.instance "buffer1" @{{.*}}(ins: %s: {{.*}}, clk: %clk: i1, rst: %[[K0]]: i1)
// CHECK-DAG: hw.instance "instance0" @pred(x: %buffer0.outs: {{.*}}, start: %buffer1.outs: {{.*}}, clk: %clk: i1, rst: %[[K0]]: i1)
// CHECK-DAG: hw.instance "buffer2" @{{.*}}(ins: %c: {{.*}}, clk: %clk: i1, rst: %[[K1:commit1.kill]]: i1)
// CHECK-DAG: hw.instance "load0" @{{.*}}(addrIn: %buffer2.outs: {{.*}}, dataFromMem: {{.*}}, kill: %[[K1]]: i1, clk: %clk: i1, rst: %rst: i1)
// CHECK-DAG: hw.instance "trunci1" @{{.*}}(ins: %load0.dataOut: {{.*}}, clk: %clk: i1, rst: %[[K1]]: i1)
// CHECK-DAG: hw.instance "commit0" @{{.*}}(ins: %d0: {{.*}}, clk: %clk: i1, rst: %rst: i1)
// CHECK-DAG: hw.instance "commit1" @{{.*}}(ins: %d1: {{.*}}, clk: %clk: i1, rst: %rst: i1)
// CHECK-DAG: hw.instance "stand_in0" @{{.*}}(ins: %instance0.flag: {{.*}}, kill_0: %[[K0]]: i1, clk: %clk: i1, rst: %rst: i1)
// CHECK-DAG: hw.instance "stand_in1" @{{.*}}(ins: %trunci1.outs: {{.*}}, kill_0: %[[K1]]: i1, clk: %clk: i1, rst: %rst: i1)
// CHECK-DAG: hw.instance "mem_controller0" @{{.*}}(loadData: {{.*}}, clk: %clk: i1, rst: %rst: i1)
// CHECK-NOT: kill_or
// CHECK-NOT: handshake.kill_domain

handshake.func @pred(%x: !handshake.channel<i2>, %start: !handshake.control<>, ...)
    -> (!handshake.channel<i1>, !handshake.control<>)
    attributes {argNames = ["x", "start"], resNames = ["flag", "end"]} {
  %t = trunci %x : <i2> to <i1>
  end %t, %start : <i1>, <>
}

handshake.func @two(%a: !handshake.channel<i2>, %s: !handshake.control<>,
                    %c: !handshake.channel<i2>, %d0: !handshake.channel<i3>,
                    %d1: !handshake.channel<i3>, %mem: memref<4xi8>,
                    %memStart: !handshake.control<>, %ctrlEnd: !handshake.control<>,
                    %start: !handshake.control<>, ...)
    -> (!handshake.channel<i1>, !handshake.channel<i1>, !handshake.channel<i3>,
        !handshake.channel<i3>, !handshake.control<>, !handshake.control<>)
    attributes {argNames = ["a", "s", "c", "d0", "d1", "mem", "memStart", "ctrlEnd", "start"],
                resNames = ["flag0", "flag1", "dec0", "dec1", "memEnd", "end"]} {
  // domain 0: a guard with a body
  %la = buffer %a, bufferType = ONE_SLOT_BREAK_R, numSlots = 1, dvLatency = 0 {handshake.kill_domain = 0 : ui32} : <i2>
  %sa = buffer %s, bufferType = ONE_SLOT_BREAK_R, numSlots = 1, dvLatency = 0 {handshake.kill_domain = 0 : ui32} : <>
  %f0, %e0 = instance @pred(%la, %sa) {handshake.kill_domain = 0 : ui32} : (!handshake.channel<i2>, !handshake.control<>) -> (!handshake.channel<i1>, !handshake.control<>)
  sink %e0 {handshake.kill_domain = 0 : ui32} : <>
  %o0, %k0 = commit %d0 : <i3>
  %flag0 = stand_in %f0, %k0 : <i1>
  // domain 1: a guard that reads memory
  %lc = buffer %c, bufferType = ONE_SLOT_BREAK_R, numSlots = 1, dvLatency = 0 {handshake.kill_domain = 1 : ui32} : <i2>
  %ldAddr, %ldData = load [%lc] %memData {handshake.bb = 0 : ui32, handshake.kill_domain = 1 : ui32} : <i2>, <i8>, <i2>, <i8>
  %memData, %memEnd = mem_controller [%mem : memref<4xi8>] %memStart (%ldAddr) %ctrlEnd {connectedBlocks = [0 : i32]} : (!handshake.channel<i2>) -> !handshake.channel<i8>
  %w = trunci %ldData {handshake.kill_domain = 1 : ui32} : <i8> to <i1>
  %o1, %k1 = commit %d1 {domain = 1 : ui32} : <i3>
  %flag1 = stand_in %w, %k1 : <i1>
  end %flag0, %flag1, %o0, %o1, %memEnd, %start : <i1>, <i1>, <i3>, <i3>, <>, <>
}
