// RUN: rm -rf %t && mkdir %t && cd %t
// RUN: python3 %dynamatic_src_root/tools/unit-generators/vhdl/vhdl-unit-generator.py -n q -o %t/q.vhd -t queue -p num_slots=4 bitwidth=16 size_width=3 space_width=3 initial_tokens="'1111111111111101,0000000000000111'"
// RUN: FileCheck %s --input-file %t/q.vhd
// RUN: python3 %dynamatic_src_root/tools/unit-generators/vhdl/vhdl-unit-generator.py -n f -o %t/f.vhd -t queue -p num_slots=2 bitwidth=8 size_width=2 space_width=0 initial_tokens="'00000001,00000010'"
// RUN: FileCheck %s --input-file %t/f.vhd --check-prefix=FULL
// RUN: python3 %dynamatic_src_root/tools/unit-generators/vhdl/vhdl-unit-generator.py -n e -o %t/e.vhd -t queue -p num_slots=4 bitwidth=16 size_width=3 space_width=3 initial_tokens="'none'"
// RUN: FileCheck %s --input-file %t/e.vhd --check-prefix=EMPTY
// RUN: for p in "2 8 00000001,00000010,00000011" "4 8 0001" "4 8 0000000x" "4 0 1"; do set -- $p; \
// RUN:   ! python3 %dynamatic_src_root/tools/unit-generators/vhdl/vhdl-unit-generator.py -n bad -o %t/bad.vhd -t queue -p num_slots=$1 bitwidth=$2 size_width=0 space_width=0 initial_tokens="'$3'" 2>&1 || exit 1; \
// RUN:   done | FileCheck %s --check-prefix=BAD

// A queue holding tokens at reset (handshake.queue's initialTokens, a dataflow
// channel that starts with tokens on it): the reset writes them to the first
// slots, the count starts at their number and the tail past them, so the
// output is valid on the first from reset and `size`/`space` count them.

// CHECK:      if rst = '1' then
// CHECK-NEXT:   Count <= 2;
// CHECK:      if rst = '1' then
// CHECK-NEXT:   Tail <= 2;
// CHECK:      if rst = '1' then
// CHECK-NEXT:   Head <= 0;
// CHECK:      if rst = '1' then
// CHECK-NEXT:   Memory(0) <= "1111111111111101";
// CHECK-NEXT:   Memory(1) <= "0000000000000111";
// CHECK-NEXT: elsif WriteEn = '1' then
// CHECK-NEXT:   Memory(Tail) <= ins;

// Full at reset: the tail wraps to slot 0.
// FULL: Count <= 2;
// FULL: Tail <= 0;
// FULL: Memory(1) <= "00000010";

// Starting empty, the queue is the one it was: nothing written by the reset.
// EMPTY:     Count <= 0;
// EMPTY:     Tail <= 0;
// EMPTY-NOT: Memory(0) <=

// BAD: queue bad: 3 initial tokens but 2 slots
// BAD: queue bad: initial token '0001' is not 8 bits
// BAD: queue bad: initial token '0000000x' is not 8 bits
// BAD: queue bad: initial tokens on a dataless channel
