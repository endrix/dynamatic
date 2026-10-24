`timescale 1ns/1ps
// The static kill_or (data/verilog/support/kill_or.v, the module the Verilog
// configuration emits) with three kills, under the generator's name, so that
// kill-or-tb.v drives both.
module dut (input [2:0] ins, output outs);
  kill_or #(.SIZE(3)) k (.ins(ins), .outs(outs));
endmodule
