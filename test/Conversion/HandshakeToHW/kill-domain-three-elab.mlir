// REQUIRES: ghdl, iverilog
// RUN: rm -rf %t && mkdir -p %t
// RUN: dynamatic-opt %S/kill-domain-three.mlir --lower-handshake-to-hw > %t/three.hw
// RUN: export-rtl %t/three.hw %t/vhdl %dynamatic_src_root/data/rtl-config-vhdl.json --dynamatic-path %dynamatic_src_root --hdl vhdl
// RUN: cd %t/vhdl && ghdl -a --std=08 handshake_*.vhd kill_or_*.vhd three.vhd && ghdl -e --std=08 three
// RUN: export-rtl %t/three.hw %t/vlog %dynamatic_src_root/data/rtl-config-verilog.json --dynamatic-path %dynamatic_src_root --hdl verilog
// RUN: cd %t/vlog && iverilog -g2012 -s three -o sim *.v

// The circuit of kill-domain-three.mlir (kill_or of 3 and of 2, stand-ins on
// 3 and 2 kills in one module) exported to VHDL (the generators) and to
// Verilog (the static modules) elaborates: each OR and each stand-in's
// `kill` port is as wide as its domain's commits.
