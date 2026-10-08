// RUN: %export-vhdl
// RUN: FileCheck %s -input-file %t/handshake_ram_0.vhd --check-prefix=FLOPS
// RUN: FileCheck %s -input-file %t/sram/handshake_ram_0.vhd --check-prefix=SRAM
// RUN: ls %t/sram | FileCheck %s --check-prefix=ONLY

// SRAM macros on FakeRAM2.0's dual-port RAM, what a memory gets unless it
// says it needs one port (no PORTS here; the macro fakeram7_dp_{size}x{width}): the
// store on port a, the load on port b, so a load and a store in one cycle
// are both served, as the flop model serves them. Which memories get a view
// is decided as for the one-port RAM (ram-sram.mlir): at least 64 words, no
// initial content.
module {
  hw.module @test(in %clk : i1, in %rst : i1, in %loadEn : i1, in %loadAddr : i6,
                  in %storeEn : i1, in %storeAddr : i6, in %storeData : i32,
                  in %loadAddr3 : i3, in %storeAddr3 : i3,
                  out loadData : i32, out loadData1 : i32, out loadData2 : i32) {
    %ram0.loadData = hw.instance "ram0" @handshake_ram_0(loadEn: %loadEn: i1, loadAddr: %loadAddr: i6, storeEn: %storeEn: i1, storeAddr: %storeAddr: i6, storeData: %storeData: i32, clk: %clk: i1, rst: %rst: i1) -> (loadData: i32)
    %ram1.loadData = hw.instance "ram1" @handshake_ram_1(loadEn: %loadEn: i1, loadAddr: %loadAddr3: i3, storeEn: %storeEn: i1, storeAddr: %storeAddr3: i3, storeData: %storeData: i32, clk: %clk: i1, rst: %rst: i1) -> (loadData: i32)
    %ram2.loadData = hw.instance "ram2" @handshake_ram_2(loadEn: %loadEn: i1, loadAddr: %loadAddr: i6, storeEn: %storeEn: i1, storeAddr: %storeAddr: i6, storeData: %storeData: i32, clk: %clk: i1, rst: %rst: i1) -> (loadData: i32)
    hw.output %ram0.loadData, %ram1.loadData, %ram2.loadData : i32, i32, i32
  }

  // The flop model, untouched: the entity and the two processes.
  // FLOPS-LABEL: entity handshake_ram_0 is
  // FLOPS: architecture arch of handshake_ram_0
  // FLOPS: type ram_type is array (0 to 64 - 1) of std_logic_vector(32 - 1 downto 0);
  // FLOPS: read_proc : process(clk)
  // FLOPS: write_proc : process(clk)
  // FLOPS-NOT: component

  // The synthesis view: the same entity, the dual-port macro as a
  // component, the store on port a and the load on port b, nothing shared.
  // SRAM-LABEL: entity handshake_ram_0 is
  // SRAM: loadData  : out std_logic_vector(32 - 1 downto 0)
  // SRAM: architecture arch of handshake_ram_0
  // SRAM-NEXT: component fakeram7_dp_64x32
  // SRAM: macro : fakeram7_dp_64x32
  // SRAM: we_a   => storeEn,
  // SRAM-NEXT: addr_a => storeAddr,
  // SRAM-NEXT: din_a  => storeData,
  // SRAM-NEXT: dout_a => open,
  // SRAM-NEXT: clk_a  => clk,
  // SRAM-NEXT: we_b   => '0',
  // SRAM-NEXT: addr_b => loadAddr,
  // SRAM: dout_b => raw,
  // SRAM-NEXT: clk_b  => clk
  // SRAM: written_proc : process(clk)
  // SRAM: loadData <= raw when word_written = '1' else (others => '0');
  // SRAM-NOT: ce_in
  // SRAM-NOT: read_proc

  // Only the 64-word, zero-initialised memory has a view under sram/.
  // ONLY: handshake_ram_0.vhd
  // ONLY-NOT: handshake_ram_1.vhd
  // ONLY-NOT: handshake_ram_2.vhd
  hw.module.extern @handshake_ram_0(in %loadEn : i1, in %loadAddr : i6, in %storeEn : i1, in %storeAddr : i6, in %storeData : i32, in %clk : i1, in %rst : i1, out loadData : i32) attributes {hw.name = "handshake.ram", hw.parameters = {ADDR_WIDTH = 6 : ui32, DATA_WIDTH = 32 : ui32, INITIAL_VALUES = "0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,", SIZE = 64 : ui32}}
  hw.module.extern @handshake_ram_1(in %loadEn : i1, in %loadAddr : i3, in %storeEn : i1, in %storeAddr : i3, in %storeData : i32, in %clk : i1, in %rst : i1, out loadData : i32) attributes {hw.name = "handshake.ram", hw.parameters = {ADDR_WIDTH = 3 : ui32, DATA_WIDTH = 32 : ui32, INITIAL_VALUES = "0,0,0,0,0,0,0,0,", SIZE = 8 : ui32}}
  hw.module.extern @handshake_ram_2(in %loadEn : i1, in %loadAddr : i6, in %storeEn : i1, in %storeAddr : i6, in %storeData : i32, in %clk : i1, in %rst : i1, out loadData : i32) attributes {hw.name = "handshake.ram", hw.parameters = {ADDR_WIDTH = 6 : ui32, DATA_WIDTH = 32 : ui32, INITIAL_VALUES = "1,2,3,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,", SIZE = 64 : ui32}}
}
