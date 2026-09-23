// RUN: %export-vhdl
// RUN: FileCheck %s -input-file %t/handshake_ram_0.vhd

// A ONE-ELEMENT memory. Two things went wrong at this size and nothing else
// covered it, so both are checked here.
//
// The RTL config wraps INITIAL_VALUES in parentheses and the generator reads
// the result with `ast.literal_eval`. `(0)` is an int in Python, not a
// one-element tuple, so the generator died with "TypeError: 'int' object is
// not iterable" -- which is why HandshakeToHW emits a TRAILING comma.
//
// And a positional VHDL aggregate of one element is ambiguous: `("0000")` is a
// string literal, not an array, and GHDL rejects it with "can't match string
// literal with type array subtype". So the initial values use NAMED
// association, which is valid at every size.

module {
  hw.module @test(in %clk : i1, in %rst : i1, in %loadEn : i1, in %loadAddr : i32,
                  in %storeEn : i1, in %storeAddr : i32, in %storeData : i32,
                  out loadData : i32) {
    %ram0.loadData = hw.instance "ram0" @handshake_ram_0(loadEn: %loadEn: i1, loadAddr: %loadAddr: i32, storeEn: %storeEn: i1, storeAddr: %storeAddr: i32, storeData: %storeData: i32, clk: %clk: i1, rst: %rst: i1) -> (loadData: i32)
    hw.output %ram0.loadData : i32
  }

  // CHECK-LABEL: architecture {{.*}} of handshake_ram_0
  // CHECK: signal ram : ram_type := (0 => "00000000000000000000000000000000");
  hw.module.extern @handshake_ram_0(in %loadEn : i1, in %loadAddr : i32, in %storeEn : i1, in %storeAddr : i32, in %storeData : i32, in %clk : i1, in %rst : i1, out loadData : i32) attributes {hw.name = "handshake.ram", hw.parameters = {ADDR_WIDTH = 32 : ui32, DATA_WIDTH = 32 : ui32, INITIAL_VALUES = "0,", SIZE = 1 : ui32}}
}
