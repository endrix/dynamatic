// RUN: %export-vhdl
// RUN: FileCheck %s -input-file %t/sram/handshake_ram_0.vhd --check-prefix=DP
// RUN: FileCheck %s -input-file %t/sram/handshake_ram_1.vhd --check-prefix=SP
// RUN: FileCheck %s -input-file %t/sram/handshake_ram_2.vhd --check-prefix=BITS
// RUN: tail -n +2 %t/handshake_ram_0.vhd | sed 's/handshake_ram_0/RAM/g' > %t/flops0
// RUN: tail -n +2 %t/handshake_ram_2.vhd | sed 's/handshake_ram_2/RAM/g' > %t/flops2
// RUN: diff %t/flops0 %t/flops2
// RUN: export RAM_RESET_CONTENT=1; %export-vhdl
// RUN: FileCheck %s -input-file %t/handshake_ram_0.vhd --check-prefix=RESET
// RUN: tail -n +2 %t/handshake_ram_0.vhd | sed 's/handshake_ram_0/RAM/g' > %t/rflops0
// RUN: tail -n +2 %t/handshake_ram_2.vhd | sed 's/handshake_ram_2/RAM/g' > %t/rflops2
// RUN: diff %t/rflops0 %t/rflops2

// A MEMORY ITS PROGRAM STORES BEFORE IT LOADS. Every SRAM view keeps a bit a
// word, so that a word never stored since reset reads as zero, the declared
// content a macro does not have at power-up (ram-sram.mlir). A memory whose
// program lets no bit of a word it has not stored reach what it does (it
// may load one and shift or mask its bits away) says so (STORED_BEFORE_LOAD
// = 1, from the front end's handshake.ram_stored_before_load, CalPy's
// `@memory(name, kind="ram", stored_before_load=True)`), and its view is the
// macro alone: no bits, no mux, loadData the macro's read data. The
// parameter reaches the generator in the unit's parameters file, like the
// initial values.

module {
  hw.module @test(in %clk : i1, in %rst : i1, in %loadEn : i1, in %loadAddr : i6,
                  in %storeEn : i1, in %storeAddr : i6, in %storeData : i32,
                  out loadData0 : i32, out loadData1 : i32, out loadData2 : i32) {
    %ram0.loadData = hw.instance "ram0" @handshake_ram_0(loadEn: %loadEn: i1, loadAddr: %loadAddr: i6, storeEn: %storeEn: i1, storeAddr: %storeAddr: i6, storeData: %storeData: i32, clk: %clk: i1, rst: %rst: i1) -> (loadData: i32)
    %ram1.loadData = hw.instance "ram1" @handshake_ram_1(loadEn: %loadEn: i1, loadAddr: %loadAddr: i6, storeEn: %storeEn: i1, storeAddr: %storeAddr: i6, storeData: %storeData: i32, clk: %clk: i1, rst: %rst: i1) -> (loadData: i32)
    %ram2.loadData = hw.instance "ram2" @handshake_ram_2(loadEn: %loadEn: i1, loadAddr: %loadAddr: i6, storeEn: %storeEn: i1, storeAddr: %storeAddr: i6, storeData: %storeData: i32, clk: %clk: i1, rst: %rst: i1) -> (loadData: i32)
    hw.output %ram0.loadData, %ram1.loadData, %ram2.loadData : i32, i32, i32
  }

  // Stored before loaded, two ports: the dual-port macro drives loadData.
  // DP-LABEL: entity handshake_ram_0 is
  // DP: architecture arch of handshake_ram_0
  // DP-NEXT: component fakeram7_dp_64x32
  // DP: macro : fakeram7_dp_64x32
  // DP: dout_b => loadData,
  // DP-NOT: written
  // DP-NOT: raw

  // Stored before loaded, one port: the one-port macro drives loadData.
  // SP-LABEL: entity handshake_ram_1 is
  // SP: architecture arch of handshake_ram_1
  // SP-NEXT: component fakeram7_64x32
  // SP: macro : fakeram7_64x32
  // SP: rd_out  => loadData,
  // SP-NOT: written
  // SP-NOT: raw

  // A memory that does not say keeps its bits.
  // BITS-LABEL: entity handshake_ram_2 is
  // BITS: dout_b => raw,
  // BITS: written_proc : process(clk)
  // BITS: loadData <= raw when word_written = '1' else (others => '0');

  // The flop models of ram0 and ram2 are the same unit but for their names
  // (the diffs above), with the flop model's reset of the content off and on
  // (RAM_RESET_CONTENT, on in the cell-library flow, where the views are
  // used): the reset the flop model has is not the view's.
  // RESET-LABEL: architecture {{.*}} of handshake_ram_0
  // RESET: write_proc
  // RESET: if (rst = '1') then
  // RESET-NEXT: ram <= ram_init;
  hw.module.extern @handshake_ram_0(in %loadEn : i1, in %loadAddr : i6, in %storeEn : i1, in %storeAddr : i6, in %storeData : i32, in %clk : i1, in %rst : i1, out loadData : i32) attributes {hw.name = "handshake.ram", hw.parameters = {ADDR_WIDTH = 6 : ui32, DATA_WIDTH = 32 : ui32, INITIAL_VALUES = "0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,", SIZE = 64 : ui32, STORED_BEFORE_LOAD = 1 : ui32}}
  hw.module.extern @handshake_ram_1(in %loadEn : i1, in %loadAddr : i6, in %storeEn : i1, in %storeAddr : i6, in %storeData : i32, in %clk : i1, in %rst : i1, out loadData : i32) attributes {hw.name = "handshake.ram", hw.parameters = {ADDR_WIDTH = 6 : ui32, DATA_WIDTH = 32 : ui32, INITIAL_VALUES = "0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,", PORTS = 1 : ui32, SIZE = 64 : ui32, STORED_BEFORE_LOAD = 1 : ui32}}
  hw.module.extern @handshake_ram_2(in %loadEn : i1, in %loadAddr : i6, in %storeEn : i1, in %storeAddr : i6, in %storeData : i32, in %clk : i1, in %rst : i1, out loadData : i32) attributes {hw.name = "handshake.ram", hw.parameters = {ADDR_WIDTH = 6 : ui32, DATA_WIDTH = 32 : ui32, INITIAL_VALUES = "0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,", SIZE = 64 : ui32}}
}
