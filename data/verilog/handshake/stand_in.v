`timescale 1ns/1ps
// Answers zero for a producer a commit stopped (`handshake.stand_in`): `outs`
// is `ins` while the producer answers; a kill ends the round, and if its token
// has not passed one zero is owed, offered from the next cycle until taken,
// `ins` waiting meanwhile. Two flip-flops, `sent` and `owe`. `kill` has SIZE
// bits, one a commit (a domain may have several): any of them high ends ONE
// round; the commits of a domain never end two rounds in one cycle (the
// decisions they sit on are exclusive in time), the producer's promise. The
// zero is
// registered: offered in the kill cycle, `outs_valid` would depend on the
// decision's transfer, and that on the readies of the units this channel
// feeds, a combinational loop. The same circuit as
// data/vhdl/handshake/stand_in.vhd.
//
// The precondition: no kill while a token is offered at `outs` and not taken.
// A kill while the zero is owed and not taken would owe a second one, which
// two bits cannot hold (one zero for two rounds, and the decision waits for
// ever for the other); a kill while the producer's own token is offered and
// not taken resets the producer under `valid`, and the token becomes a zero
// before it transfers. So the stand-in's one reader must take a token the
// cycle it arrives, with nothing between that can hold it back (an eager fork
// whose other reader stalls, a join). Asserted in simulation ($fatal, between
// `synthesis translate_off` and `translate_on`); synthesis skips it.
module stand_in #(
  parameter SIZE = 1,
  parameter DATA_TYPE = 32
)(
  input  clk,
  input  rst,
  // Input channel
  input  [DATA_TYPE - 1 : 0] ins,
  input  ins_valid,
  output ins_ready,
  // the commits' transfers, one bit a commit: any ends the round
  input  [SIZE - 1 : 0] kill,
  // Output channel
  output [DATA_TYPE - 1 : 0] outs,
  output outs_valid,
  input  outs_ready
);

  reg sent, owe;
  // the producer's token goes through this cycle
  wire passed = ins_valid & outs_ready & ~owe;
  // one round ends, whichever commit ends it
  wire kill_any = |kill;

  always @(posedge clk) begin
    if (rst) begin
      sent <= 1'b0;
      owe  <= 1'b0;
    end else begin
      // A kill ends the round: the next one has sent nothing yet.
      sent <= kill_any ? 1'b0 : (sent | passed);
      // A round ended with its token not passed owes a zero; an owed zero is
      // paid when taken.
      owe  <= (kill_any & ~(sent | passed)) | (owe & ~outs_ready);
    end
  end

  assign outs_valid = owe | ins_valid;
  assign outs       = owe ? {DATA_TYPE{1'b0}} : ins;
  assign ins_ready  = outs_ready & ~owe;

  // The precondition, in simulation only: a round ends only when no token
  // waits at `outs`, neither the zero owed nor the producer's own.
  // synthesis translate_off
  always @(posedge clk)
    if (!rst && kill_any && !outs_ready) begin
      if (owe)
        $fatal(1, "stand_in %m: a round ended (kill) while the zero it owes was offered and not taken");
      if (ins_valid)
        $fatal(1, "stand_in %m: a round ended (kill) while the producer's token was offered and not taken");
    end
  // synthesis translate_on

endmodule
