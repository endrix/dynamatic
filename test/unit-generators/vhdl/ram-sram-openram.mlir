// RUN: export SRAM_INTERFACE=openram; export SRAM_MACROS="[('sky130_sram_1rw1r_64x256_8',256,64),('sky130_sram_1rw1r_44x64_8',64,44)]"; %export-vhdl
// RUN: FileCheck %s -input-file %t/handshake_ram_0.vhd --check-prefix=FLOPS
// RUN: FileCheck %s -input-file %t/sram/handshake_ram_0.vhd --check-prefix=SRAM
// RUN: ls %t/sram | FileCheck %s --check-prefix=ONLY
// The SRAM view on OpenRAM's 1rw1r macros. The RTL config's ram generator
// reads `SRAM_INTERFACE` and `SRAM_MACROS` from the environment: with
// `openram` and a list of the macros on hand as (name, words, width), a
// memory of at least `sram_threshold` words with no initial content gets,
// under sram/, the same entity wrapping the smallest macro that holds it --
// here 64 x 32 goes into the 64-word, 44-bit macro rather than the 256-word
// one -- the store on the read-write port, the load on the read port,
// address and data padded with zeros to the macro's. The flop model is
// untouched; an 8-word memory and an initialised one stay flops only.
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

  // The flop model, untouched.
  // FLOPS-LABEL: entity handshake_ram_0 is
  // FLOPS: read_proc : process(clk)
  // FLOPS-NOT: component
  // The view: the 64-word, 44-bit macro, both ports, the padding.
  // SRAM-LABEL: entity handshake_ram_0 is
  // SRAM: architecture arch of handshake_ram_0
  // SRAM-NEXT: component sky130_sram_1rw1r_44x64_8
  // SRAM: wmask0 : in  std_logic_vector(6 - 1 downto 0);
  // SRAM: csb0   <= not storeEn;
  // SRAM-NEXT: web0   <= not storeEn;
  // SRAM: csb1   <= not loadEn;
  // SRAM: addr0  <= std_logic_vector(resize(unsigned(storeAddr), 6));
  // SRAM-NEXT: din0   <= std_logic_vector(resize(unsigned(storeData), 44));
  // SRAM: loadData <= dout1(32 - 1 downto 0);
  // SRAM: macro : sky130_sram_1rw1r_44x64_8
  // SRAM: dout1  => dout1
  // SRAM-NOT: read_proc
  // ONLY: handshake_ram_0.vhd
  // ONLY-NOT: handshake_ram_1.vhd
  // ONLY-NOT: handshake_ram_2.vhd



  hw.module.extern @handshake_ram_0(in %loadEn : i1, in %loadAddr : i6, in %storeEn : i1, in %storeAddr : i6, in %storeData : i32, in %clk : i1, in %rst : i1, out loadData : i32) attributes {hw.name = "handshake.ram", hw.parameters = {ADDR_WIDTH = 6 : ui32, DATA_WIDTH = 32 : ui32, INITIAL_VALUES = "0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,", SIZE = 64 : ui32}}
  hw.module.extern @handshake_ram_1(in %loadEn : i1, in %loadAddr : i3, in %storeEn : i1, in %storeAddr : i3, in %storeData : i32, in %clk : i1, in %rst : i1, out loadData : i32) attributes {hw.name = "handshake.ram", hw.parameters = {ADDR_WIDTH = 3 : ui32, DATA_WIDTH = 32 : ui32, INITIAL_VALUES = "0,0,0,0,0,0,0,0,", SIZE = 8 : ui32}}
  hw.module.extern @handshake_ram_2(in %loadEn : i1, in %loadAddr : i6, in %storeEn : i1, in %storeAddr : i6, in %storeData : i32, in %clk : i1, in %rst : i1, out loadData : i32) attributes {hw.name = "handshake.ram", hw.parameters = {ADDR_WIDTH = 6 : ui32, DATA_WIDTH = 32 : ui32, INITIAL_VALUES = "1,2,3,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,", SIZE = 64 : ui32}}
}
