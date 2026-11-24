// RUN: rm -rf %t; mkdir %t; not export-rtl %s %t %S/../../../data/rtl-config-vhdl.json --dynamatic-path %S/../../.. --hdl vhdl 2>&1 | FileCheck %s

// STORED_BEFORE_LOAD is 0 or 1, as RAM_RESET_CONTENT is. HandshakeToHW only
// ever writes 1; anything else in a RAM's parameters is refused by the
// generator rather than read as true or false.
// CHECK: stored_before_load 2 is not 0 or 1

module {
  hw.module @test(in %clk : i1, in %rst : i1, in %loadEn : i1, in %loadAddr : i6,
                  in %storeEn : i1, in %storeAddr : i6, in %storeData : i32,
                  out loadData : i32) {
    %ram0.loadData = hw.instance "ram0" @handshake_ram_0(loadEn: %loadEn: i1, loadAddr: %loadAddr: i6, storeEn: %storeEn: i1, storeAddr: %storeAddr: i6, storeData: %storeData: i32, clk: %clk: i1, rst: %rst: i1) -> (loadData: i32)
    hw.output %ram0.loadData : i32
  }
  hw.module.extern @handshake_ram_0(in %loadEn : i1, in %loadAddr : i6, in %storeEn : i1, in %storeAddr : i6, in %storeData : i32, in %clk : i1, in %rst : i1, out loadData : i32) attributes {hw.name = "handshake.ram", hw.parameters = {ADDR_WIDTH = 6 : ui32, DATA_WIDTH = 32 : ui32, INITIAL_VALUES = "0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,", SIZE = 64 : ui32, STORED_BEFORE_LOAD = 2 : ui32}}
}
