// RUN: export SRAM_INTERFACE=openram; export SRAM_MACROS="[('sky130_sram_1rw1r_44x64_8',64,44),('sky130_sram_1rw1r_80x64_8',64,80),('sky130_sram_1rw1r_64x256_8',256,64),('sky130_sram_1rw1r_128x256_8',256,128)]"; %export-vhdl
// RUN: FileCheck %s -input-file %t/sram/handshake_ram_0.vhd --check-prefix=DEPTH
// RUN: FileCheck %s -input-file %t/sram/handshake_ram_1.vhd --check-prefix=WIDTH
// RUN: export SRAM_INTERFACE=openram; export SRAM_MACROS="[('sky130_sram_1rw1r_64x256_8',256,64)]"; %export-vhdl
// RUN: FileCheck %s -input-file %t/sram/handshake_ram_0.vhd --check-prefix=FOUR
// RUN: export SRAM_INTERFACE=openram; export SRAM_MACROS="[('odd_100x16',100,16)]"; %export-vhdl 2>&1 | FileCheck %s --check-prefix=NONE
// A memory no single macro of `sram_macros` holds is TILED on OpenRAM: rows
// of one macro in depth (the address's top bits pick the row), columns in
// width, the kind of least total area -- here, with no area in the table,
// of least capacity. 832 x 13 (MPEG-4 texture's IAP buffer, deeper than
// every sky130 macro) takes 13 rows of 44x64 (36,608 bits) before 4 of
// 64x256 (65,536); 64 x 200 (wider than every macro) takes 5 columns of
// 44x64. With only the 64x256 macro on hand, 832 x 13 is 4 rows of it. A
// table with no power-of-two depth cannot tile, and the memory stays flops.
module {
  hw.module @test(in %clk : i1, in %rst : i1, in %loadEn : i1, in %storeEn : i1,
                  in %loadAddr : i10, in %storeAddr : i10, in %storeData : i13,
                  in %loadAddr6 : i6, in %storeAddr6 : i6, in %storeData200 : i200,
                  out loadData : i13, out loadData1 : i200) {
    %ram0.loadData = hw.instance "ram0" @handshake_ram_0(loadEn: %loadEn: i1, loadAddr: %loadAddr: i10, storeEn: %storeEn: i1, storeAddr: %storeAddr: i10, storeData: %storeData: i13, clk: %clk: i1, rst: %rst: i1) -> (loadData: i13)
    %ram1.loadData = hw.instance "ram1" @handshake_ram_1(loadEn: %loadEn: i1, loadAddr: %loadAddr6: i6, storeEn: %storeEn: i1, storeAddr: %storeAddr6: i6, storeData: %storeData200: i200, clk: %clk: i1, rst: %rst: i1) -> (loadData: i200)
    hw.output %ram0.loadData, %ram1.loadData : i13, i200
  }

  // Depth: 13 rows of one 44x64 macro, a row per 64 words, the row the load
  // selected registered one-hot and its read data AND-ORed out.
  // DEPTH-LABEL: entity handshake_ram_0 is
  // DEPTH: component sky130_sram_1rw1r_44x64_8
  // DEPTH: type row_data is array (0 to 13 - 1) of std_logic_vector(44 - 1 downto 0);
  // DEPTH: signal st_row, ld_row     : unsigned(4 - 1 downto 0);
  // DEPTH: st_row <= unsigned(storeAddr(10 - 1 downto 6));
  // DEPTH-NEXT: ld_row <= unsigned(loadAddr(10 - 1 downto 6));
  // DEPTH-NEXT: rows_sel : for r in 0 to 13 - 1 generate
  // DEPTH-NEXT: csb0(r) <= '0' when storeEn = '1' and st_row = r else '1';
  // DEPTH-NEXT: csb1(r) <= '0' when loadEn = '1' and ld_row = r else '1';
  // DEPTH: addr0  <= storeAddr(6 - 1 downto 0);
  // DEPTH-NEXT: addr1  <= loadAddr(6 - 1 downto 0);
  // DEPTH-NEXT: din0   <= std_logic_vector(resize(unsigned(storeData), 44));
  // DEPTH: if loadEn = '1' then
  // DEPTH-NEXT: rd_row <= not csb1;
  // DEPTH: if rd_row(r) = '1' then
  // DEPTH-NEXT: acc := acc or dout1(r);
  // DEPTH: raw <= acc(13 - 1 downto 0);
  // DEPTH: tiles : for r in 0 to 13 - 1 generate
  // DEPTH-NEXT: columns : for c in 0 to 1 - 1 generate
  // DEPTH-NEXT: macro : sky130_sram_1rw1r_44x64_8
  // DEPTH: csb0   => csb0(r),
  // DEPTH: dout1  => dout1(r)((c + 1) * 44 - 1 downto c * 44)
  // DEPTH-NOT: read_proc

  // Width: one row of 5 columns, the data split 44 bits a macro.
  // WIDTH: 1 x 5 OpenRAM 1rw1r macros sky130_sram_1rw1r_44x64_8
  // WIDTH: entity handshake_ram_1 is
  // WIDTH: csb0(0) <= not storeEn;
  // WIDTH-NEXT: csb1(0) <= not loadEn;
  // WIDTH: din0   <= std_logic_vector(resize(unsigned(storeData), 220));
  // WIDTH-NEXT: raw <= dout1(0)(200 - 1 downto 0);
  // WIDTH: columns : for c in 0 to 5 - 1 generate
  // WIDTH: din0   => din0((c + 1) * 44 - 1 downto c * 44),

  // FOUR: 4 x 1 OpenRAM 1rw1r macros sky130_sram_1rw1r_64x256_8
  // FOUR: st_row <= unsigned(storeAddr(10 - 1 downto 8));
  // FOUR: addr0  <= storeAddr(8 - 1 downto 0);

  // NONE: handshake_ram_0: no macro in sram_macros holds 832 x 13 and none tiles it; the memory stays flops



  hw.module.extern @handshake_ram_0(in %loadEn : i1, in %loadAddr : i10, in %storeEn : i1, in %storeAddr : i10, in %storeData : i13, in %clk : i1, in %rst : i1, out loadData : i13) attributes {hw.name = "handshake.ram", hw.parameters = {ADDR_WIDTH = 10 : ui32, DATA_WIDTH = 13 : ui32, INITIAL_VALUES = "0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,", SIZE = 832 : ui32}}
  hw.module.extern @handshake_ram_1(in %loadEn : i1, in %loadAddr : i6, in %storeEn : i1, in %storeAddr : i6, in %storeData : i200, in %clk : i1, in %rst : i1, out loadData : i200) attributes {hw.name = "handshake.ram", hw.parameters = {ADDR_WIDTH = 6 : ui32, DATA_WIDTH = 200 : ui32, INITIAL_VALUES = "0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,", SIZE = 64 : ui32}}
}
