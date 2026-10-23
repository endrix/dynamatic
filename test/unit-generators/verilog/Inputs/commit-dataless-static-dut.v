`timescale 1ns/1ps
// The static dataless commit (data/verilog/handshake/dataless/commit.v, the
// module the Verilog configuration emits for a control channel) under the
// generator's name, so that commit-tb.v (DATALESS) drives both.
module dut (
  input clk, input rst,
  input ins_valid, output ins_ready,
  output outs_valid, input outs_ready, output kill
);
  commit_dataless c (
    .clk(clk), .rst(rst), .ins_valid(ins_valid), .ins_ready(ins_ready),
    .outs_valid(outs_valid), .outs_ready(outs_ready), .kill(kill));
endmodule
