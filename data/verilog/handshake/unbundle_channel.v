`timescale 1ns/1ps

// Splits a channel into the control that carries its handshake and a bare
// data signal. Pure rewiring: it exists so a circuit can OBSERVE a channel's
// protocol signals, which is the one thing the channel abstraction cannot
// express, since reading a channel consumes it.
module unbundle_channel #(
  parameter DATA_WIDTH = 32
)(
  // inputs
  input  clk,
  input  rst,
  input  [DATA_WIDTH - 1 : 0] ins,
  input  ins_valid,
  input  ctrl_ready,
  // outputs
  output ins_ready,
  output ctrl_valid,
  output [DATA_WIDTH - 1 : 0] data
);

  assign ctrl_valid = ins_valid;
  assign ins_ready  = ctrl_ready;
  assign data       = ins;

endmodule
