`timescale 1ns/1ps

// Splits a control into the valid it carries, given the ready to drive back.
module unbundle_control (
  // inputs
  input  clk,
  input  rst,
  input  ins_valid,
  input  ready,
  // outputs
  output ins_ready,
  output valid
);

  assign valid     = ins_valid;
  assign ins_ready = ready;

endmodule
