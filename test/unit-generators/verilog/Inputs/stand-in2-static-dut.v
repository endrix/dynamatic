`timescale 1ns/1ps
// The static stand_in (data/verilog/handshake/stand_in.v, the module the
// Verilog configuration emits) with two kills, under the generator's name and
// width, so that stand-in2-tb.v drives both.
module dut (
  input clk, input rst,
  input [1:0] ins, input ins_valid, output ins_ready, input [1:0] kill,
  output [1:0] outs, output outs_valid, input outs_ready
);
  stand_in #(.SIZE(2), .DATA_TYPE(2)) s (
    .clk(clk), .rst(rst), .ins(ins), .ins_valid(ins_valid), .ins_ready(ins_ready),
    .kill(kill), .outs(outs), .outs_valid(outs_valid), .outs_ready(outs_ready));
endmodule
