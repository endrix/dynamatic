// RUN: export RAM_RESET_CONTENT=1; %export-vhdl
// RUN: FileCheck %s -input-file %t/handshake_ram_0.vhd
// RUN: export RAM_RESET_CONTENT=0; %export-vhdl
// RUN: FileCheck %s -input-file %t/handshake_ram_0.vhd --check-prefix=FPGA
// RUN: unset RAM_RESET_CONTENT; %export-vhdl
// RUN: FileCheck %s -input-file %t/handshake_ram_0.vhd --check-prefix=FPGA

// A MEMORY RESETS TO WHAT IT DECLARES, WHEN THE TARGET ASKS. A declared
// initial value is a simulator's and an FPGA bitstream's; a cell library has
// neither, so left as a declaration alone it is honoured in simulation and
// dropped on the way to cells. With RAM_RESET_CONTENT=1 the content is a
// constant, the declaration keeps it for the simulator, and the write
// process resets to it. Without it the unit is what it always was, because
// on an FPGA the bitstream loads the content and a reset would stop block
// RAM being inferred. Unset, it is off: the third pair of RUN lines is what
// keeps that the default.

// FPGA-NOT: ram_init
// FPGA-NOT: rst = '1'
// FPGA: if (storeEn = '1') then

// CHECK-LABEL: architecture {{.*}} of handshake_ram_0
// CHECK: constant ram_init : ram_type := (0 => "{{0+}}101",
// CHECK-NEXT: 1 => "{{1+}}01");
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

  hw.module.extern @handshake_ram_0(in %loadEn : i1, in %loadAddr : i32, in %storeEn : i1, in %storeAddr : i32, in %storeData : i32, in %clk : i1, in %rst : i1, out loadData : i32) attributes {hw.name = "handshake.ram", hw.parameters = {ADDR_WIDTH = 32 : ui32, DATA_WIDTH = 32 : ui32, INITIAL_VALUES = "5,-3,", SIZE = 2 : ui32}}
}
