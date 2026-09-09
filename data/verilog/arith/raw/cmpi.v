`timescale 1ns/1ps
// cmpi on raw wires: no valid, no ready, the wires and nothing else. clk and
// rst are ports because every instance is handed them; nothing here reads them.
// ENTITY_NAME, MODIFIER and COMPARATOR are substituted by rtl-cmpi-generator.
module ENTITY_NAME #(
  parameter DATA_WIDTH = 32
)(
  input  clk,
  input  rst,
  input  [DATA_WIDTH - 1 : 0] lhs,
  input  [DATA_WIDTH - 1 : 0] rhs,
  output result
);
  assign result = (MODIFIER(lhs) COMPARATOR MODIFIER(rhs)) ? 1'b1 : 1'b0;
endmodule
