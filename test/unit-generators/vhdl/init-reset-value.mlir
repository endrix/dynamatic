// RUN: rm -rf %t && mkdir %t && cd %t && for p in 1:0 1:1 1:-1 2:0 2:1 2:2 2:3 2:-1 8:0 8:1 8:2 8:255 8:-1 8:-128 32:0 32:1 32:2 32:4294967295 32:-1 100:1180591620717411303424 100:-1; do \
// RUN:   w=${p%%:*}; v=${p#*:}; \
// RUN:   python3 %dynamatic_src_root/tools/unit-generators/vhdl/vhdl-unit-generator.py -n init -o init.vhd -t init -p bitwidth=$w 'extra_signals={}' initial_value=$v || exit 1; \
// RUN:   echo "width $w value $v"; grep 'dataReg <= "' init.vhd; done | FileCheck %s
// RUN: cd %t && python3 %dynamatic_src_root/tools/unit-generators/vhdl/vhdl-unit-generator.py -n init_spec -o init_spec.vhd -t init -p bitwidth=8 "extra_signals={'spec':1}" initial_value=1
// RUN: FileCheck %s --input-file %t/init_spec.vhd --check-prefix=SPEC
// RUN: cd %t && for p in 1:2 2:4 8:256 8:-129 32:4294967296; do \
// RUN:   w=${p%%:*}; v=${p#*:}; \
// RUN:   ! python3 %dynamatic_src_root/tools/unit-generators/vhdl/vhdl-unit-generator.py -n init -o bad.vhd -t init -p bitwidth=$w 'extra_signals={}' initial_value=$v 2>&1 || exit 1; \
// RUN:   done | FileCheck %s --check-prefix=BAD

// An init's register resets to its INITIAL_VALUE as the integer at the
// channel's width, a negative value in two's complement. It used to replicate
// a 0 or a 1 over the width, (others => '1'), so a channel wider than one bit
// that starts at 1 came out of reset as all ones, -1: a state variable
// declared `= 1`, or a register file [3, 1, ...] whose rf[1] read -1.

// CHECK:      width 1 value 0
// CHECK-NEXT: dataReg <= "0";
// CHECK:      width 1 value 1
// CHECK-NEXT: dataReg <= "1";
// CHECK:      width 1 value -1
// CHECK-NEXT: dataReg <= "1";
// CHECK:      width 2 value 0
// CHECK-NEXT: dataReg <= "00";
// CHECK:      width 2 value 1
// CHECK-NEXT: dataReg <= "01";
// CHECK:      width 2 value 2
// CHECK-NEXT: dataReg <= "10";
// CHECK:      width 2 value 3
// CHECK-NEXT: dataReg <= "11";
// CHECK:      width 2 value -1
// CHECK-NEXT: dataReg <= "11";
// CHECK:      width 8 value 0
// CHECK-NEXT: dataReg <= "00000000";
// CHECK:      width 8 value 1
// CHECK-NEXT: dataReg <= "00000001";
// CHECK:      width 8 value 2
// CHECK-NEXT: dataReg <= "00000010";
// CHECK:      width 8 value 255
// CHECK-NEXT: dataReg <= "11111111";
// CHECK:      width 8 value -1
// CHECK-NEXT: dataReg <= "11111111";
// CHECK:      width 8 value -128
// CHECK-NEXT: dataReg <= "10000000";
// CHECK:      width 32 value 0
// CHECK-NEXT: dataReg <= "00000000000000000000000000000000";
// CHECK:      width 32 value 1
// CHECK-NEXT: dataReg <= "00000000000000000000000000000001";
// CHECK:      width 32 value 2
// CHECK-NEXT: dataReg <= "00000000000000000000000000000010";
// CHECK:      width 32 value 4294967295
// CHECK-NEXT: dataReg <= "11111111111111111111111111111111";
// CHECK:      width 32 value -1
// CHECK-NEXT: dataReg <= "11111111111111111111111111111111";
// CHECK:      width 100 value 1180591620717411303424
// CHECK-NEXT: dataReg <= "0000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000";
// CHECK:      width 100 value -1
// CHECK-NEXT: dataReg <= "1111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111";

// With extra signals, which the signal manager concatenates above the data,
// the value is the data's and the extra bits reset to zero.
// SPEC: entity init_spec_inner_dataless is
// SPEC: dataReg <= "000000001";

// A value the width cannot hold is refused, not cut.
// BAD: initial value 2 does not fit 1 bits
// BAD: initial value 4 does not fit 2 bits
// BAD: initial value 256 does not fit 8 bits
// BAD: initial value -129 does not fit 8 bits
// BAD: initial value 4294967296 does not fit 32 bits
