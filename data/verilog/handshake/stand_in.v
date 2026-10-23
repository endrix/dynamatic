`timescale 1ns/1ps
// Answers zero for a producer a commit stopped (`handshake.stand_in`): `outs`
// is `ins` while the producer answers; `kill` ends the round, and if its token
// has not passed one zero is owed, offered from the next cycle until taken,
// `ins` waiting meanwhile. Two flip-flops, `sent` and `owe`. The zero is
// registered: offered in the kill cycle, `outs_valid` would depend on the
// decision's transfer, and that on the readies of the units this channel
// feeds, a combinational loop. The same circuit as
// data/vhdl/handshake/stand_in.vhd.
module stand_in #(
  parameter DATA_TYPE = 32
)(
  input  clk,
  input  rst,
  // Input channel
  input  [DATA_TYPE - 1 : 0] ins,
  input  ins_valid,
  output ins_ready,
  // the commit's transfer: the end of a round
  input  kill,
  // Output channel
  output [DATA_TYPE - 1 : 0] outs,
  output outs_valid,
  input  outs_ready
);

  reg sent, owe;
  // the producer's token goes through this cycle
  wire passed = ins_valid & outs_ready & ~owe;

  always @(posedge clk) begin
    if (rst) begin
      sent <= 1'b0;
      owe  <= 1'b0;
    end else begin
      // A kill ends the round: the next one has sent nothing yet.
      sent <= kill ? 1'b0 : (sent | passed);
      // A round ended with its token not passed owes a zero; an owed zero is
      // paid when taken.
      owe  <= (kill & ~(sent | passed)) | (owe & ~outs_ready);
    end
  end

  assign outs_valid = owe | ins_valid;
  assign outs       = owe ? {DATA_TYPE{1'b0}} : ins;
  assign ins_ready  = outs_ready & ~owe;

endmodule
