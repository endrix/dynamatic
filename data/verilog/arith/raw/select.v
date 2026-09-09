`timescale 1ns/1ps
// select on raw wires: no valid, no ready, the wires and nothing else. clk and
// rst are ports because every instance is handed them; nothing here reads them.
module arith_select #(
  parameter DATA_WIDTH = 32
)(
  input  clk,
  input  rst,
  input  condition,
  input  [DATA_WIDTH - 1 : 0] true_value,
  input  [DATA_WIDTH - 1 : 0] false_value,
  output [DATA_WIDTH - 1 : 0] result
);
  assign result = condition ? true_value : false_value;
endmodule
