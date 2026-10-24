`timescale 1ns/1ps
// A wire that says when its token has passed (`handshake.commit`): `outs` is
// `ins`, valid, data and ready straight through, no register. `kill` is the
// transfer ORed with the reset: the reset of the units the transfer stops
// (`handshake.kill_domain`), which take it in place of `rst`. The same circuit
// as data/vhdl/handshake/commit.vhd.
module commit #(
  parameter DATA_TYPE = 32
)(
  input  clk,
  input  rst,
  // Input channel
  input  [DATA_TYPE - 1 : 0] ins,
  input  ins_valid,
  output ins_ready,
  // Output channel
  output [DATA_TYPE - 1 : 0] outs,
  output outs_valid,
  input  outs_ready,
  // the transfer, as the reset of what it stops
  output kill
);

  assign outs       = ins;
  assign outs_valid = ins_valid;
  assign ins_ready  = outs_ready;
  assign kill       = rst | (ins_valid & outs_ready);

endmodule
