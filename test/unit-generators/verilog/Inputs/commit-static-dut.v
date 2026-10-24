`timescale 1ns/1ps
// The static commit (data/verilog/handshake/commit.v, the module the Verilog
// configuration emits for a channel with data) under the generator's name and
// width, so that commit-tb.v drives both.
module dut (
  input clk, input rst,
  input [2:0] ins, input ins_valid, output ins_ready,
  output [2:0] outs, output outs_valid, input outs_ready, output kill
);
  commit #(.DATA_TYPE(3)) c (
    .clk(clk), .rst(rst), .ins(ins), .ins_valid(ins_valid), .ins_ready(ins_ready),
    .outs(outs), .outs_valid(outs_valid), .outs_ready(outs_ready), .kill(kill));
endmodule
