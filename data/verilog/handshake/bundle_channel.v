`timescale 1ns/1ps

// Joins a control and a bare data signal back into a channel. The exact
// inverse of unbundle_channel.
module bundle_channel #(
  parameter DATA_WIDTH = 32
)(
  // inputs
  input  clk,
  input  rst,
  input  ctrl_valid,
  input  [DATA_WIDTH - 1 : 0] data,
  input  outs_ready,
  // outputs
  output ctrl_ready,
  output [DATA_WIDTH - 1 : 0] outs,
  output outs_valid
);

  assign outs_valid = ctrl_valid;
  assign ctrl_ready = outs_ready;
  assign outs       = data;

endmodule
