"""Writes ram-large.mlir's input: two 70,000-word memories, too large for
their initial values to go on the generator's command line (Linux takes at
most 128 KiB in one argument with 4 KiB pages; the lists here are 249 KB and
140 KB). handshake_ram_0 holds i % 251 at word i, handshake_ram_1 zeros, so it
also gets an SRAM view."""
N = 70000
content = "".join(f"{i % 251}," for i in range(N))
zeros = "0," * N
ports = ("in %loadEn : i1, in %loadAddr : i17, in %storeEn : i1, in %storeAddr : i17, "
         "in %storeData : i8, in %clk : i1, in %rst : i1, out loadData : i8")
print("module {")
print("  hw.module @test(in %clk : i1, in %rst : i1, in %loadEn : i1, in %loadAddr : i17,")
print("                  in %storeEn : i1, in %storeAddr : i17, in %storeData : i8,")
print("                  out loadData0 : i8, out loadData1 : i8) {")
for k in (0, 1):
    print(f'    %ram{k}.loadData = hw.instance "ram{k}" @handshake_ram_{k}(loadEn: %loadEn: i1, '
          "loadAddr: %loadAddr: i17, storeEn: %storeEn: i1, storeAddr: %storeAddr: i17, "
          "storeData: %storeData: i8, clk: %clk: i1, rst: %rst: i1) -> (loadData: i8)")
print("    hw.output %ram0.loadData, %ram1.loadData : i8, i8")
print("  }")
for k, values in ((0, content), (1, zeros)):
    print(f"  hw.module.extern @handshake_ram_{k}({ports}) attributes {{hw.name = \"handshake.ram\", "
          f"hw.parameters = {{ADDR_WIDTH = 17 : ui32, DATA_WIDTH = 8 : ui32, "
          f"INITIAL_VALUES = \"{values}\", SIZE = {N} : ui32}}}}")
print("}")
