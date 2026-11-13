// RUN: rm -rf %t && mkdir -p %t
// RUN: python3 %S/Inputs/ram-large.py > %t.mlir
// RUN: export-rtl %t.mlir %t %dynamatic_src_root/data/rtl-config-vhdl.json --dynamatic-path %dynamatic_src_root --hdl vhdl
// RUN: FileCheck %s -input-file %t/handshake_ram_0.vhd --check-prefix=CONTENT
// RUN: ls %t/sram | FileCheck %s --check-prefix=SRAM --implicit-check-not=handshake_ram_0

// A MEMORY TOO LARGE FOR ITS CONTENT TO GO ON A COMMAND LINE. The RTL config
// gave the generator a memory's initial values inline, `values="(...)"`, and
// Linux takes at most 128 KiB in one argument: a 147,456-word memory's zeros
// alone are 295 KB, so the shell never started the generator ("generator
// failed with status 32512", the shell's 127). Found exporting AV1's entropy
// actor, whose largest arrays are 147,456 and 1,048,576 words. The values now
// reach the generator in the parameters file export-rtl writes for the unit
// (`use-json-config`), read as the command line's were.
//
// The input (Inputs/ram-large.py) is two 70,000-word memories, with 249 KB
// and 140 KB of initial values. The old command line fails it where pages are
// 4 KiB (the limit is 32 pages); with 64 KiB pages it would not have.

// The content, word for word: i % 251 at word i.
// CONTENT:      signal ram : ram_type := (0 => "00000000",
// CONTENT-NEXT: 1 => "00000001",
// CONTENT:      250 => "11111010",
// CONTENT-NEXT: 251 => "00000000",
// CONTENT:      69999 => "11011101");

// The memory of zeros keeps its SRAM view; the one with content has none.
// SRAM: handshake_ram_1.vhd
