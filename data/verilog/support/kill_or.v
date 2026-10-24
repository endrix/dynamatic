`timescale 1ns/1ps
// The kill of a domain with several commits (`handshake.commit`): the OR of
// their kills, which HandshakeToHW gives the domain's units as their reset.
// SIZE one-bit inputs, one output; combinational, no clock and no reset (each
// commit's kill has the reset in it already). Not a Handshake unit: the
// lowering's own, as mem_to_bram is. The same circuit as
// data/vhdl/support/kill_or.vhd.
module kill_or #(
  parameter SIZE = 2
)(
  // the kills of the domain's commits
  input  [SIZE - 1 : 0] ins,
  // the domain's kill
  output outs
);
  assign outs = |ins;
endmodule
