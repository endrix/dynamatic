`timescale 1ns/1ps
// xori on raw wires: no valid, no ready, the wires and nothing else. clk and
// rst are ports because every instance is handed them; nothing here reads them.
module arith_xori #(
  parameter DATA_WIDTH = 32
)(
  input  clk,
  input  rst,
  input  [DATA_WIDTH - 1 : 0] lhs,
  input  [DATA_WIDTH - 1 : 0] rhs,
  output [DATA_WIDTH - 1 : 0] result
);
  assign result = lhs ^ rhs;
endmodule
