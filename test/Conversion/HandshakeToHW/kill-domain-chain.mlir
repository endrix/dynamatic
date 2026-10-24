// RUN: dynamatic-opt %s --lower-handshake-to-hw | FileCheck %s

// A chain left between a domain and its load -- the address narrowed (a
// placer's or a bitwidth pass's unit), taken apart into wires and put back --
// joins the domain as a whole: none of it can join alone, each link's
// neighbour being outside until it does, and without the chain the domain
// would hand its address to a unit outside it (refused). Joined, a unit that
// holds nothing -- the unbundle, the wires, the bundle -- has nothing to
// reset and keeps the module's reset; the load drops on the kill.

// CHECK-LABEL: hw.module @chain
// CHECK: hw.instance "buffer{{.*}}" @{{.*}}(ins: %arg: {{.*}}, clk: %clk: i1, rst: %commit{{.*}}.kill: i1)
// CHECK: hw.instance "unbundle{{.*}}" @{{.*}}(ins: %buffer{{.*}}.outs: {{.*}}, clk: %clk: i1, rst: %rst: i1)
// CHECK: hw.instance "trunci{{.*}}" @arith_trunci{{.*}}(ins: %unbundle{{.*}}.data: i8, clk: %clk: i1, rst: %rst: i1)
// CHECK: hw.instance "bundle{{.*}}" @{{.*}}({{.*}}clk: %clk: i1, rst: %rst: i1)
// CHECK: hw.instance "load{{.*}}" @{{.*}}(addrIn: %bundle{{.*}}, dataFromMem: {{.*}}, kill: %commit{{.*}}.kill: i1, clk: %clk: i1, rst: %rst: i1)
handshake.func @chain(%arg: !handshake.channel<i8>, %dec: !handshake.channel<i3>,
                      %mem: memref<4xi8>, %memStart: !handshake.control<>,
                      %ctrlEnd: !handshake.control<>, %start: !handshake.control<>, ...)
    -> (!handshake.channel<i1>, !handshake.channel<i3>, !handshake.control<>, !handshake.control<>)
    attributes {argNames = ["arg", "dec", "mem", "memStart", "ctrlEnd", "start"],
                resNames = ["flag", "dec_out", "memEnd", "end"]} {
  %latch = buffer %arg, bufferType = ONE_SLOT_BREAK_R, numSlots = 1, dvLatency = 0 {handshake.kill_domain = 0 : ui32} : <i8>
  %ctrl, %wide = unbundle %latch : <i8> to _
  %narrow = arith.trunci %wide : i8 to i2
  %addr = bundle %ctrl, %narrow : _ to <i2>
  %ldAddr, %ldData = load [%addr] %memData {handshake.bb = 0 : ui32, handshake.kill_domain = 0 : ui32} : <i2>, <i8>, <i2>, <i8>
  %memData, %memEnd = mem_controller [%mem : memref<4xi8>] %memStart (%ldAddr) %ctrlEnd {connectedBlocks = [0 : i32]} : (!handshake.channel<i2>) -> !handshake.channel<i8>
  %c = trunci %ldData {handshake.kill_domain = 0 : ui32} : <i8> to <i1>
  %decision, %kill = commit %dec : <i3>
  %flag = stand_in %c, %kill : <i1>
  end %flag, %decision, %memEnd, %start : <i1>, <i3>, <>, <>
}
