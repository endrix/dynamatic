`timescale 1ns/1ps
// The static priority (data/verilog/handshake/priority_merge.v, the file the
// Verilog configuration emits) under the generator's name and width, so that
// priority-tb.v drives both.
module dut(
  input  clk,
  input  rst,
  input  [3:0] hi,
  input  hi_valid,
  output hi_ready,
  input  [3:0] lo,
  input  lo_valid,
  output lo_ready,
  output [3:0] outs,
  output outs_valid,
  input  outs_ready
);
  priority_merge #(.DATA_TYPE(4)) p(
    .clk(clk), .rst(rst), .hi(hi), .hi_valid(hi_valid), .hi_ready(hi_ready),
    .lo(lo), .lo_valid(lo_valid), .lo_ready(lo_ready),
    .outs(outs), .outs_valid(outs_valid), .outs_ready(outs_ready));
endmodule
