`timescale 1ns/1ps
// The static first (data/verilog/handshake/first.v, the module the
// Verilog configuration emits) under the generator's name and size, so that
// first-tb.v drives both.
module dut (
  input clk, input rst,
  input [5:0] ins, input [2:0] ins_valid, output [2:0] ins_ready,
  output [1:0] outs, output outs_valid, input outs_ready
);
  first #(.SIZE(3), .DATA_TYPE(2)) f (
    .clk(clk), .rst(rst), .ins(ins), .ins_valid(ins_valid), .ins_ready(ins_ready),
    .outs(outs), .outs_valid(outs_valid), .outs_ready(outs_ready));
endmodule
