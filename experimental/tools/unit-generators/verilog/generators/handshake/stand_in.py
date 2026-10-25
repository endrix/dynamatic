def generate_stand_in(name, params):
    """Answers zero for a producer a commit stopped (`handshake.stand_in`):
    `outs` is `ins` while the producer answers; a kill ends the round, and if
    its token has not passed one zero is owed, offered from the next cycle
    until taken, `ins` waiting meanwhile. Two flip-flops, `sent` and `owe`.

    `kill` has `size` bits, the kills of all the commits of the producer's
    domain (a domain may have several): any of them high ends ONE round, the
    unit otherwise the same whatever their number. The rounds of a domain
    never overlap -- a round of the domain starts only after the previous
    commit of the domain has transferred -- so at most one bit is high in a
    cycle, and it ends the round this unit is in. (Were state B's round to
    start before state A's commit transferred, A's kill would wipe it with
    A's round, and B's reader would wait for ever for this unit's token.) The
    producer's promise, asserted in simulation ($fatal under `ifndef
    SYNTHESIS`).

    The precondition: no kill while a token is offered at `outs` and not
    taken. A kill while the zero is owed and not taken would owe a second
    one, which two bits cannot hold (one zero for two rounds, and the
    decision waits for ever for the other); a kill while the producer's own
    token is offered and not taken resets the producer under `valid`, and
    the token becomes a zero before it transfers. So the stand-in's one
    reader must take a token the cycle it arrives, with nothing between that
    can hold it back (an eager fork whose other reader stalls, a join). An
    always block between `synthesis translate_off` and `translate_on`
    asserts it in simulation ($fatal); synthesis skips it.
    """
    bitwidth = params["bitwidth"]
    size = params["size"]
    if size < 1:
        raise ValueError(
            "handshake.stand_in answers for a producer a commit stops, so it "
            "takes at least one kill")
    if bitwidth == 0:
        raise ValueError(
            "handshake.stand_in answers zero, so its channel carries data; a "
            "dataless stand-in would send a token nobody asked for")
    if params.get("extra_signals", None):
        raise ValueError(
            "handshake.stand_in passes its payload alone; a channel with "
            "extra signals would lose them (the op's verifier refuses it)")
    return f"""

// Module of stand_in

module {name}(
  input  clk,
  input  rst,
  // Input channel
  input  [{bitwidth} - 1 : 0] ins,
  input  ins_valid,
  output ins_ready,
  // the commits' transfers, one bit a commit: any ends the round
  input  [{size} - 1 : 0] kill,
  // Output channel
  output [{bitwidth} - 1 : 0] outs,
  output outs_valid,
  input  outs_ready
);
{stand_in_body(str(bitwidth))}
endmodule
"""


def stand_in_body(w):
    """The module's body, the width as text: a number here, the static
    module's parameter in data/verilog/handshake/stand_in.v."""
    return f"""
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
  assign outs       = owe ? {{{w}{{1'b0}}}} : ins;
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

  // The domain's promise, in simulation only: its rounds never overlap, so no
  // two of its commits transfer in one cycle (under reset every commit's kill
  // is high). `kill & (kill - 1)` is `kill` less its lowest bit set: not zero
  // when two or more are.
`ifndef SYNTHESIS
  always @(posedge clk)
    if (!rst && (kill & (kill - 1'b1)) != 0)
      $fatal(1, "stand_in %m: two commits of its kill domain transferred in one cycle (the domain's rounds overlap)");
`endif
"""
