`timescale 1ns/1ps
// extui on raw wires: no valid, no ready, the wires and nothing else. clk and
// rst are ports because every instance is handed them; nothing here reads them.
module arith_extui #(
  parameter INPUT_WIDTH = 32,
  parameter OUTPUT_WIDTH = 32
)(
  input  clk,
  input  rst,
  input  [INPUT_WIDTH - 1 : 0] ins,
  output [OUTPUT_WIDTH - 1 : 0] outs
);
  assign outs = {{(OUTPUT_WIDTH - INPUT_WIDTH){1'b0}}, ins};
endmodule
