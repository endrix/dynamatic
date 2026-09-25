// REQUIRES: ghdl
// RUN: rm -rf %t && mkdir %t
// RUN: cd %t && for k in fptosi sitofp uitofp; do for l in 0 3; do \
// RUN:   mkdir $k-$l && python3 %dynamatic_src_root/tools/unit-generators/vhdl/vhdl-unit-generator.py -n dut -o $k-$l/dut.vhd -t $k -p latency=$l bitwidth=32 'extra_signals={}' && \
// RUN:   ghdl -a --std=08 --workdir=$k-$l $k-$l/dut.vhd %S/Inputs/converter-rounding-tb.vhd && \
// RUN:   (cd $k-$l && ghdl --elab-run --std=08 --workdir=. tb -gKIND=$k --stop-time=10us) || exit 1; done; done 2>&1 | FileCheck %s

// The converters' rounding, on operands whose conversion is not exact,
// against bit patterns written out in the testbench. fptosi truncates toward
// zero, as C, MLIR's arith.fptosi and RISC-V's fcvt.w.s do, and saturates
// out of range: it rounded to nearest (float_pkg's default), so 11.75 gave
// 12 and -11.75 gave -12, and 0.99999994 gave 1. sitofp and uitofp round to
// nearest, ties to even, which is IEEE's default and what the package does.

// CHECK-COUNT-2: fptosi: 15 of 15 results, 0 wrong
// CHECK-COUNT-2: sitofp: 8 of 8 results, 0 wrong
// CHECK-COUNT-2: uitofp: 7 of 7 results, 0 wrong
// CHECK-NOT: FAILED
