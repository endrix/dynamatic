// RUN: python3 %S/Inputs/bound_sizes.py %dynamatic_src_root | FileCheck %s

// report_parser.bound_sizes on the port models of a unit u at sizes 2, 3 and
// 4, and of a unit v at sizes 2 and 3. Past the base size an entry is
// measured at 1, 8, 32 and 64 bits; the base at every width.
//
// At a width it was measured at, an entry holds the larger of its own delay
// and the size below's: u's size 4 at 32 bits is size 3's 0.4.
//
// At a width it was not measured at, it holds the larger of the size below's
// delay there and its own at the next width it was measured at, so bounded
// (where TimingDatabase reads that width): u's size 3 at 2 bits is its own
// 8-bit 0.3, not the base's 0.1, and at 4 bits the base's 0.5; v's size 3 at
// 2 and 4 bits is 0.5, its 8-bit delay bounded by the base's, not its own
// 0.3. Past its widest (64) it reads its widest: v's size 3 at 128 bits is
// its own 0.8, not the base's 0.2, and u's the base's 0.9.

// CHECK:      u.size.2 1:0.1 2:0.1 4:0.5 8:0.1 16:0.1 32:0.1 64:0.1 128:0.9
// CHECK-NEXT: u.size.2 inport zero
// CHECK-NEXT: u.size.3 1:0.2 2:0.3 4:0.5 8:0.3 16:0.4 32:0.4 64:0.6 128:0.9
// CHECK-NEXT: u.size.3 inport zero
// CHECK-NEXT: u.size.4 1:0.2 2:0.3 4:0.5 8:0.3 16:0.4 32:0.4 64:0.7 128:0.9
// CHECK-NEXT: u.size.4 inport zero
// CHECK-NEXT: v.size.2 1:0.1 2:0.1 4:0.1 8:0.5 16:0.1 32:0.1 64:0.1 128:0.2
// CHECK-NEXT: v.size.2 inport zero
// CHECK-NEXT: v.size.3 1:0.2 2:0.5 4:0.5 8:0.5 16:0.3 32:0.3 64:0.8 128:0.8
// CHECK-NEXT: v.size.3 inport zero
