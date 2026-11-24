// RUN: dynamatic-opt %s --lower-handshake-to-hw | FileCheck %s
// RUN: rm -rf %t && mkdir -p %t
// RUN: dynamatic-opt %s --lower-handshake-to-hw > %t/hw.mlir
// RUN: export-rtl %t/hw.mlir %t/rtl %dynamatic_src_root/data/rtl-config-vhdl.json --dynamatic-path %dynamatic_src_root --hdl vhdl
// RUN: FileCheck %s --check-prefix=SAID -input-file %t/rtl/sram/handshake_ram_0.vhd
// RUN: FileCheck %s --check-prefix=UNSAID -input-file %t/rtl/sram/handshake_ram_1.vhd

// A RAM the front end says is stored before it is loaded
// (handshake.ram_stored_before_load, streamblocks' from CalPy's
// `@memory(name, kind="ram", stored_before_load=True)`) is a module of its
// own with STORED_BEFORE_LOAD = 1, which the RAM generator reads from the
// unit's parameters file: its SRAM view keeps no written bits
// (test/unit-generators/vhdl/ram-sram-stored-before-load.mlir). The same
// memory that does not say is the module it was, without the parameter, and
// its view keeps them.

// CHECK: hw.module.extern @handshake_ram_0({{.*}}) attributes {hw.name = "handshake.ram", hw.parameters = {ADDR_WIDTH = 6 : ui32, DATA_WIDTH = 32 : ui32, INITIAL_VALUES = "{{[0,]+}}", SIZE = 64 : ui32, STORED_BEFORE_LOAD = 1 : ui32}}
// CHECK: hw.module.extern @handshake_ram_1({{.*}}) attributes {hw.name = "handshake.ram", hw.parameters = {ADDR_WIDTH = 6 : ui32, DATA_WIDTH = 32 : ui32, INITIAL_VALUES = "{{[0,]+}}", SIZE = 64 : ui32}}

// SAID: macro : fakeram7_dp_64x32
// SAID: dout_b => loadData,
// SAID-NOT: written

// UNSAID: macro : fakeram7_dp_64x32
// UNSAID: dout_b => raw,
// UNSAID: written_proc : process(clk)

// Each RAM after its controller: HandshakeToHW lowers a RAM with the
// controller that uses it, and refuses one it reaches first.
module {
  handshake.func @mems(%a0: !handshake.channel<i6>, %d0: !handshake.channel<i32>, %l0: !handshake.channel<i6>,
                       %a1: !handshake.channel<i6>, %d1: !handshake.channel<i32>, %l1: !handshake.channel<i6>,
                       %start: !handshake.control<>, ...) -> (!handshake.channel<i32>, !handshake.channel<i32>, !handshake.control<>)
      attributes {argNames = ["sa0", "sd0", "la0", "sa1", "sd1", "la1", "start"], resNames = ["out0", "out1", "end"]} {
    %s:6 = fork [6] %start : <>
    %ld0, %end0 = mem_controller[%said : memref<64xi32>] %s#0 (%cnt0, %sa0, %sd0, %la0) %s#1 {connectedBlocks = [0 : i32]} : (!handshake.channel<i32>, !handshake.channel<i6>, !handshake.channel<i32>, !handshake.channel<i6>) -> !handshake.channel<i32>
    %said = "handshake.ram"() <{initialValue = dense<0> : tensor<64xi32>}> {handshake.ram_stored_before_load} : () -> memref<64xi32>
    %ld1, %end1 = mem_controller[%unsaid : memref<64xi32>] %s#2 (%cnt1, %sa1, %sd1, %la1) %s#3 {connectedBlocks = [0 : i32]} : (!handshake.channel<i32>, !handshake.channel<i6>, !handshake.channel<i32>, !handshake.channel<i6>) -> !handshake.channel<i32>
    %unsaid = "handshake.ram"() <{initialValue = dense<0> : tensor<64xi32>}> : () -> memref<64xi32>
    %cnt0 = constant %s#4 {value = 1 : i32, handshake.bb = 0 : ui32} : <>, <i32>
    %cnt1 = constant %s#5 {value = 1 : i32, handshake.bb = 0 : ui32} : <>, <i32>
    %sa0, %sd0 = store[%a0] %d0 {handshake.bb = 0 : ui32} : <i6>, <i32>, <i6>, <i32>
    %la0, %lv0 = load[%l0] %ld0 {handshake.bb = 0 : ui32} : <i6>, <i32>, <i6>, <i32>
    %sa1, %sd1 = store[%a1] %d1 {handshake.bb = 0 : ui32} : <i6>, <i32>, <i6>, <i32>
    %la1, %lv1 = load[%l1] %ld1 {handshake.bb = 0 : ui32} : <i6>, <i32>, <i6>, <i32>
    %done = join %end0, %end1 : <>
    end {handshake.bb = 0 : ui32} %lv0, %lv1, %done : <i32>, <i32>, <>
  }
}
