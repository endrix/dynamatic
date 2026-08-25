`timescale 1ns/1ps

// Turns a valid into a control, handing back the ready that comes with it.
module bundle_control (
  // inputs
  input  clk,
  input  rst,
  input  valid,
  input  ctrl_ready,
  // outputs
  output ctrl_valid,
  output ready
);

  assign ctrl_valid = valid;
  assign ready      = ctrl_ready;

endmodule
