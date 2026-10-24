// RUN: dynamatic-opt %s --lower-handshake-to-hw | FileCheck %s

// A KILL DOMAIN (handshake.commit): the units a commit's transfer stops get
// its kill as their reset; a unit between them that carries no mark (here the
// DV slot after the latch, as a placer would put it) joins the domain; a load
// of the domain keeps the module's reset and takes the kill on an input of
// its own (it drops what the stopped units are owed, KILL_DROP); a neighbour,
// the commit and the stand-in keep the module's reset. A unit of the domain
// is told apart by KILL_RESET for the backends that model the reset as an
// input; its circuit is any other's. The stand-in's kills are one port, a bit
// a kill (here one, SIZE = 1).

// CHECK-LABEL: hw.module @guard
// CHECK: hw.instance "buffer0" @[[LATCH:.*]](ins: %arg: {{.*}}, clk: %clk: i1, rst: %commit0.kill: i1)
// CHECK: hw.instance "buffer1" @{{.*}}(ins: %permit: {{.*}}, clk: %clk: i1, rst: %commit0.kill: i1)
// CHECK: hw.instance "buffer2" @{{.*}}(ins: %buffer0.outs: {{.*}}, clk: %clk: i1, rst: %commit0.kill: i1)
// CHECK: hw.instance "load0" @[[LOAD:.*]](addrIn: {{.*}}, dataFromMem: {{.*}}, kill: %commit0.kill: i1, clk: %clk: i1, rst: %rst: i1)
// CHECK: hw.instance "sink0" @{{.*}}(ins: %buffer1.outs: {{.*}}, clk: %clk: i1, rst: %commit0.kill: i1)
// CHECK: hw.instance "trunci0" @{{.*}}(ins: %load0.dataOut: {{.*}}, clk: %clk: i1, rst: %commit0.kill: i1)
// CHECK: hw.instance "buffer3" @[[NEIGHBOUR:.*]](ins: %other: {{.*}}, clk: %clk: i1, rst: %rst: i1)
// CHECK: %commit0.outs, %commit0.kill = hw.instance "commit0" @{{.*}}(ins: %dec: {{.*}}, clk: %clk: i1, rst: %rst: i1) -> (outs: !handshake.channel<i3>, kill: i1)
// CHECK: hw.instance "stand_in0" @[[STANDIN:.*]](ins: %trunci0.outs: {{.*}}, kill_0: %commit0.kill: i1, clk: %clk: i1, rst: %rst: i1)
// CHECK-NOT: handshake.kill_domain
// CHECK-NOT: handshake.kill_source
// CHECK: hw.module.extern @[[LATCH]]({{.*}}) attributes {hw.name = "handshake.buffer", hw.parameters = {{{.*}}KILL_RESET = 1 : ui32
// CHECK: hw.module.extern @[[LOAD]](in %addrIn : {{.*}}, in %dataFromMem : {{.*}}, in %kill : i1, in %clk : i1, in %rst : i1, {{.*}}) attributes {hw.name = "handshake.load", hw.parameters = {{{.*}}KILL_DROP = 1 : ui32
// CHECK: hw.module.extern @[[NEIGHBOUR]]({{.*}}) attributes {hw.name = "handshake.buffer", hw.parameters = {BUFFER_TYPE = "ONE_SLOT_BREAK_R", DATA_TYPE = !handshake.channel<i2>, DV_LATENCY = 0 : ui32, NUM_SLOTS = 1 : ui32}}
// CHECK: hw.module.extern @[[STANDIN]](in %ins : {{.*}}, in %kill_0 : i1, in %clk : i1, in %rst : i1, {{.*}}) attributes {hw.name = "handshake.stand_in", hw.parameters = {DATA_TYPE = !handshake.channel<i1>, SIZE = 1 : ui32}}
handshake.func @guard(%arg: !handshake.channel<i2>, %permit: !handshake.control<>,
                      %other: !handshake.channel<i2>, %dec: !handshake.channel<i3>,
                      %mem: memref<4xi8>, %memStart: !handshake.control<>,
                      %ctrlEnd: !handshake.control<>, %start: !handshake.control<>, ...)
    -> (!handshake.channel<i1>, !handshake.channel<i2>, !handshake.channel<i3>,
        !handshake.control<>, !handshake.control<>)
    attributes {argNames = ["arg", "permit", "other", "dec", "mem", "memStart", "ctrlEnd", "start"],
                resNames = ["flag", "other_out", "dec_out", "memEnd", "end"]} {
  %latch = buffer %arg, bufferType = ONE_SLOT_BREAK_R, numSlots = 1, dvLatency = 0 {handshake.kill_domain = 0 : ui32} : <i2>
  %slot = buffer %permit, bufferType = ONE_SLOT_BREAK_R, numSlots = 1, dvLatency = 0 {handshake.kill_domain = 0 : ui32} : <>
  %inside = buffer %latch, bufferType = ONE_SLOT_BREAK_DV, numSlots = 1, dvLatency = 1 : <i2>
  %addr = extui %inside {handshake.kill_domain = 0 : ui32} : <i2> to <i2>
  %ldAddr, %ldData = load [%addr] %memData {handshake.bb = 0 : ui32, handshake.kill_domain = 0 : ui32} : <i2>, <i8>, <i2>, <i8>
  %memData, %memEnd = mem_controller [%mem : memref<4xi8>] %memStart (%ldAddr) %ctrlEnd {connectedBlocks = [0 : i32]} : (!handshake.channel<i2>) -> !handshake.channel<i8>
  sink %slot {handshake.kill_domain = 0 : ui32} : <>
  %c = trunci %ldData {handshake.kill_domain = 0 : ui32} : <i8> to <i1>
  %neighbour = buffer %other, bufferType = ONE_SLOT_BREAK_R, numSlots = 1, dvLatency = 0 : <i2>
  %decision, %kill = commit %dec : <i3>
  %flag = stand_in %c, %kill : <i1>
  end %flag, %neighbour, %decision, %memEnd, %start : <i1>, <i2>, <i3>, <>, <>
}
