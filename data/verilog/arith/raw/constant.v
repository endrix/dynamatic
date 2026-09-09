`timescale 1ns/1ps
// constant on raw wires: no valid, no ready, the wires and nothing else. clk and
// rst are ports because every instance is handed them; nothing here reads them.
// ENTITY_NAME and VALUE are substituted by rtl-constant-generator-verilog.
module ENTITY_NAME #(
  parameter DATA_WIDTH = 32
)(
  input  clk,
  input  rst,
  output [DATA_WIDTH - 1 : 0] outs
);
  assign outs = VALUE;
endmodule
