// RUN: %export-vhdl
// RUN: FileCheck %s -input-file %t/handshake_ram_0.vhd

// A MEMORY RESETS TO WHAT IT DECLARES. A declared initial value is a
// simulator's and an FPGA bitstream's; a cell library has neither, so left
// as a declaration alone it is honoured in simulation and dropped on the
// way to cells, and the netlist that is verified and the netlist that could
// be fabricated hold different things at power-up. The content is a
// constant, the declaration keeps it for the simulator, and the write
// process resets to it.

// CHECK-LABEL: architecture {{.*}} of handshake_ram_0
// CHECK: constant ram_init : ram_type :=
// CHECK: signal ram : ram_type := ram_init;
// CHECK: write_proc
// CHECK: if (rst = '1') then
// CHECK-NEXT: ram <= ram_init;
// CHECK-NEXT: elsif (storeEn = '1') then

module {
  hw.module @test(in %clk : i1, in %rst : i1, in %loadEn : i1, in %loadAddr : i32,
                  in %storeEn : i1, in %storeAddr : i32, in %storeData : i32,
                  out loadData : i32) {
    %ram0.loadData = hw.instance "ram0" @handshake_ram_0(loadEn: %loadEn: i1, loadAddr: %loadAddr: i32, storeEn: %storeEn: i1, storeAddr: %storeAddr: i32, storeData: %storeData: i32, clk: %clk: i1, rst: %rst: i1) -> (loadData: i32)
    hw.output %ram0.loadData : i32
  }

  hw.module.extern @handshake_ram_0(in %loadEn : i1, in %loadAddr : i32, in %storeEn : i1, in %storeAddr : i32, in %storeData : i32, in %clk : i1, in %rst : i1, out loadData : i32) attributes {hw.name = "handshake.ram", hw.parameters = {ADDR_WIDTH = 32 : ui32, DATA_WIDTH = 32 : ui32, INITIAL_VALUES = "0,0,", SIZE = 2 : ui32}}
}
