// RUN: dynamatic-opt %s --lower-handshake-to-hw --split-input-file | FileCheck %s

// A memory handed DOWN a hierarchy. The callee holds the controller and takes
// the memory as an argument, the way a top-level kernel does; the parent only
// passes an argument of its own to the instance. Both modules expose the
// memory the same way, as the load and store ports of the controller: the
// callee's because the controller is inside it, the parent's because the
// instance is -- the callee's ports brought up one level, named after the
// parent's argument. Before this the instance was refused ("instantiating a
// function with a memref argument is not supported").

// The callee: a memref argument is one input, the load data, at the argument's
// position, and five outputs after the function's own.
// CHECK-LABEL: hw.module @reader(
// CHECK-SAME:    in %mem_loadData : i32, in %in0 : !handshake.control<>, in %clk : i1, in %rst : i1, out out0 : !handshake.channel<i32>, out mem_loadEn : i1, out mem_loadAddr : i32, out mem_storeEn : i1, out mem_storeAddr : i32, out mem_storeData : i32)

// The parent: the same ports under its own name for the memory, the instance
// fed the load data at the memref's position and its memory outputs driving
// the module's, in the module's order.
// CHECK-LABEL: hw.module @top(
// CHECK-SAME:    in %store_loadData : i32, in %in0 : !handshake.control<>, in %clk : i1, in %rst : i1, out out0 : !handshake.channel<i32>, out store_loadEn : i1, out store_loadAddr : i32, out store_storeEn : i1, out store_storeAddr : i32, out store_storeData : i32)
// CHECK:         %[[OUT:.*]], %[[LDEN:.*]], %[[LDADDR:.*]], %[[STEN:.*]], %[[STADDR:.*]], %[[STDATA:.*]] = hw.instance "instance0" @reader(mem_loadData: %store_loadData: i32, in0: %in0: !handshake.control<>, clk: %clk: i1, rst: %rst: i1) -> (out0: !handshake.channel<i32>, mem_loadEn: i1, mem_loadAddr: i32, mem_storeEn: i1, mem_storeAddr: i32, mem_storeData: i32)
// CHECK:         hw.output %[[OUT]], %[[LDEN]], %[[LDADDR]], %[[STEN]], %[[STADDR]], %[[STDATA]]

module {
  handshake.func @reader(%mem: memref<64xi32>, %start: !handshake.control<>) -> !handshake.channel<i32>
      attributes {argNames = ["mem", "in0"], resNames = ["out0"]} {
    %ms = source : <>
    %ce = source : <>
    %ldData, %done = mem_controller[%mem : memref<64xi32>] %ms (%ldAddr) %ce {connectedBlocks = [0 : i32]} : (!handshake.channel<i32>) -> !handshake.channel<i32>
    sink %done : <>
    %addr = constant %start {value = 5 : i32, handshake.bb = 0 : ui32} : <>, <i32>
    %ldAddr, %ldVal = load[%addr] %ldData {handshake.bb = 0 : ui32} : <i32>, <i32>, <i32>, <i32>
    end %ldVal : <i32>
  }
  handshake.func @top(%mem: memref<64xi32>, %start: !handshake.control<>) -> !handshake.channel<i32>
      attributes {argNames = ["store", "in0"], resNames = ["out0"]} {
    %r = instance @reader(%mem, %start) : (memref<64xi32>, !handshake.control<>) -> !handshake.channel<i32>
    end %r : <i32>
  }
}

// -----

// The instance reached BEFORE its callee: the ports are computed from the
// callee's Handshake function, memory included, and the result is the same.
// CHECK-LABEL: hw.module @top(
// CHECK-SAME:    in %in0 : !handshake.control<>, in %store_loadData : i32, in %clk : i1, in %rst : i1, out out0 : !handshake.channel<i32>, out store_loadEn : i1, out store_loadAddr : i32, out store_storeEn : i1, out store_storeAddr : i32, out store_storeData : i32)
// CHECK:         %[[OUT:.*]], %[[LDEN:.*]], %[[LDADDR:.*]], %[[STEN:.*]], %[[STADDR:.*]], %[[STDATA:.*]] = hw.instance "instance0" @reader(in0: %in0: !handshake.control<>, mem_loadData: %store_loadData: i32, clk: %clk: i1, rst: %rst: i1) -> (out0: !handshake.channel<i32>, mem_loadEn: i1, mem_loadAddr: i32, mem_storeEn: i1, mem_storeAddr: i32, mem_storeData: i32)
// CHECK:         hw.output %[[OUT]], %[[LDEN]], %[[LDADDR]], %[[STEN]], %[[STADDR]], %[[STDATA]]
// CHECK-LABEL: hw.module @reader(
// CHECK-SAME:    in %in0 : !handshake.control<>, in %mem_loadData : i32, in %clk : i1, in %rst : i1, out out0 : !handshake.channel<i32>, out mem_loadEn : i1, out mem_loadAddr : i32, out mem_storeEn : i1, out mem_storeAddr : i32, out mem_storeData : i32)

module {
  handshake.func @top(%start: !handshake.control<>, %mem: memref<64xi32>) -> !handshake.channel<i32>
      attributes {argNames = ["in0", "store"], resNames = ["out0"]} {
    %r = instance @reader(%start, %mem) : (!handshake.control<>, memref<64xi32>) -> !handshake.channel<i32>
    end %r : <i32>
  }
  handshake.func @reader(%start: !handshake.control<>, %mem: memref<64xi32>) -> !handshake.channel<i32>
      attributes {argNames = ["in0", "mem"], resNames = ["out0"]} {
    %ms = source : <>
    %ce = source : <>
    %ldData, %done = mem_controller[%mem : memref<64xi32>] %ms (%ldAddr) %ce {connectedBlocks = [0 : i32]} : (!handshake.channel<i32>) -> !handshake.channel<i32>
    sink %done : <>
    %addr = constant %start {value = 5 : i32, handshake.bb = 0 : ui32} : <>, <i32>
    %ldAddr, %ldVal = load[%addr] %ldData {handshake.bb = 0 : ui32} : <i32>, <i32>, <i32>, <i32>
    end %ldVal : <i32>
  }
}
