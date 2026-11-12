// RUN: dynamatic-opt %s --lower-handshake-to-hw | FileCheck %s
// RUN: dynamatic-opt %s --lower-handshake-to-hw | grep -c "hw.module @.*_wrapper(" | FileCheck %s --check-prefix=COUNT
// RUN: dynamatic-opt %s --lower-handshake-to-hw | FileCheck %s --check-prefix=CONV

// Which modules get a wrapper. A wrapper is the module with standard memory
// interfaces, for whoever uses a module from outside the design. A module
// that another one instantiates is used from inside, unwrapped: its wrapper
// would be a module nothing instantiates, one file more in the exported
// design for every module of a hierarchy. So only the modules that no other
// one instantiates are wrapped -- here the two tops, `top` (over `mid` over
// `leaf`, and over `reader`, to which it hands a memory down) and `other`,
// which stands alone. `top` comes first: a module is known to be
// instantiated whatever the order of the functions.

// Two wrappers, and no more.
// COUNT: {{^}}2{{$}}

// The memory converter was in the wrapper of `reader`, which holds the
// controller: with that wrapper it is gone. (The wrapper of `top` passes the
// memory it hands down as it is, as it always did.)
// CONV-NOT: mem_to_bram

// CHECK-DAG: hw.module @leaf(
// CHECK-DAG: hw.module @mid(
// CHECK-DAG: hw.module @reader(
// CHECK-DAG: hw.module @top(
// CHECK-DAG: hw.module @other(
// CHECK-DAG: hw.module @top_wrapper(
// CHECK-DAG: hw.instance "top_wrapped" @top(
// CHECK-DAG: hw.module @other_wrapper(
// CHECK-DAG: hw.instance "other_wrapped" @other(

module {
  handshake.func @top(%a: !handshake.channel<i32>, %mem: memref<64xi32>, %start: !handshake.control<>) -> (!handshake.channel<i32>, !handshake.channel<i32>)
      attributes {argNames = ["in0", "store", "in1"], resNames = ["out0", "out1"]} {
    %r = instance @mid(%a) : (!handshake.channel<i32>) -> !handshake.channel<i32>
    %v = instance @reader(%mem, %start) : (memref<64xi32>, !handshake.control<>) -> !handshake.channel<i32>
    end %r, %v : <i32>, <i32>
  }
  handshake.func @leaf(%a: !handshake.channel<i32>) -> !handshake.channel<i32>
      attributes {argNames = ["in0"], resNames = ["out0"]} {
    %c = source : <>
    %k = constant %c {value = 2 : i32} : <>, <i32>
    %r = addi %a, %k : <i32>
    end %r : <i32>
  }
  handshake.func @mid(%a: !handshake.channel<i32>) -> !handshake.channel<i32>
      attributes {argNames = ["in0"], resNames = ["out0"]} {
    %r = instance @leaf(%a) : (!handshake.channel<i32>) -> !handshake.channel<i32>
    end %r : <i32>
  }
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
  handshake.func @other(%a: !handshake.channel<i32>) -> !handshake.channel<i32>
      attributes {argNames = ["in0"], resNames = ["out0"]} {
    %c = source : <>
    %k = constant %c {value = 3 : i32} : <>, <i32>
    %r = addi %a, %k : <i32>
    end %r : <i32>
  }
}
