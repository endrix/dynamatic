def generate_commit(name, params):
    """A wire that says when its token has passed (`handshake.commit`): `outs`
    is `ins`, valid, data and ready straight through, no register; `kill` is
    the transfer ORed with the reset -- the reset of the units the transfer
    stops (`handshake.kill_domain`), which take it in place of `rst`.

    `kill_at_valid` (1): the kill in the first cycle a token is offered,
    `ins_valid & ~killed`, `killed` one flip-flop ("offered and not taken
    last cycle", reset low), as the VHDL's.
    """
    bitwidth = params["bitwidth"]
    at_valid = int(params.get("kill_at_valid", 0))
    if params.get("extra_signals", None):
        raise ValueError(
            "handshake.commit passes its payload alone; a channel with extra "
            "signals would lose them (the op's verifier refuses it)")
    if at_valid not in (0, 1):
        raise ValueError(
            f"handshake.commit: kill_at_valid is 0 or 1, not {at_valid}")
    data_in = f"\n  input  [{bitwidth} - 1 : 0] ins," if bitwidth else ""
    data_out = f"\n  output [{bitwidth} - 1 : 0] outs," if bitwidth else ""
    data_wire = "\n  assign outs       = ins;" if bitwidth else ""
    if at_valid:
        kill = """
  // the token now offered was offered last cycle and not taken: it has had
  // its kill
  reg killed;
  always @(posedge clk) begin
    if (rst)
      killed <= 1'b0;
    else
      killed <= ins_valid & ~outs_ready;
  end
  assign kill       = rst | (ins_valid & ~killed);"""
    else:
        kill = "\n  assign kill       = rst | (ins_valid & outs_ready);"
    return f"""

// Module of commit

module {name}(
  input  clk,
  input  rst,
  // Input channel{data_in}
  input  ins_valid,
  output ins_ready,
  // Output channel{data_out}
  output outs_valid,
  input  outs_ready,
  // the transfer, as the reset of what it stops
  output kill
);
{data_wire}
  assign outs_valid = ins_valid;
  assign ins_ready  = outs_ready;{kill}

endmodule
"""
