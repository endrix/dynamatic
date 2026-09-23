// REQUIRES: ghdl
// RUN: rm -rf %t && mkdir %t
// RUN: cd %t && for k in sitofp uitofp fptosi; do for l in 0 1 3 5 8; do \
// RUN:   mkdir $k-$l && python3 %dynamatic_src_root/tools/unit-generators/vhdl/vhdl-unit-generator.py -n dut -o $k-$l/dut.vhd -t $k -p latency=$l bitwidth=32 'extra_signals={}' && \
// RUN:   ghdl -a --std=08 --workdir=$k-$l $k-$l/dut.vhd %S/Inputs/converter-tb.vhd && \
// RUN:   (cd $k-$l && ghdl --elab-run --std=08 --workdir=. tb -gKIND=$k --stop-time=10us) || exit 1; done; done 2>&1 | FileCheck %s

// `--elab-run` works on every GHDL backend: `-e -o` then running the file
// needs the LLVM or GCC one, and CI's GHDL is mcode.

// Each converter at latencies 0, 1, 3, 5 and 8, simulated against the
// conversion computed in the testbench with its output stalled one cycle in
// four. Before, only latency 5 was right: at 0 the unit did not analyse
// (the data stages named the valid buffer's ready, which a combinational
// unit has not got), and at any other every or nearly every result was
// wrong.

// CHECK-COUNT-15: 12 results, 0 wrong
// CHECK-NOT: FAILED
