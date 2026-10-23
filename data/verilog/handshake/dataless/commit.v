`timescale 1ns/1ps
// `handshake.commit` on a control channel: valid and ready straight through,
// `kill` the transfer ORed with the reset (see ../commit.v).
module commit_dataless (
  input  clk,
  input  rst,
  // Input channel
  input  ins_valid,
  output ins_ready,
  // Output channel
  output outs_valid,
  input  outs_ready,
  // the transfer, as the reset of what it stops
  output kill
);

  assign outs_valid = ins_valid;
  assign ins_ready  = outs_ready;
  assign kill       = rst | (ins_valid & outs_ready);

endmodule
