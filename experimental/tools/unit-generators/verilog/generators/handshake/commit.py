def generate_commit(name, params):
    """A wire that says when its token has passed (`handshake.commit`): `outs`
    is `ins`, valid, data and ready straight through, no register; `kill` is
    the transfer ORed with the reset -- the reset of the units the transfer
    stops (`handshake.kill_domain`), which take it in place of `rst`.
    """
    bitwidth = params["bitwidth"]
    if params.get("extra_signals", None):
        raise ValueError(
            "handshake.commit passes its payload alone; a channel with extra "
            "signals would lose them (the op's verifier refuses it)")
    data_in = f"\n  input  [{bitwidth} - 1 : 0] ins," if bitwidth else ""
    data_out = f"\n  output [{bitwidth} - 1 : 0] outs," if bitwidth else ""
    data_wire = "\n  assign outs       = ins;" if bitwidth else ""
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
  assign ins_ready  = outs_ready;
  assign kill       = rst | (ins_valid & outs_ready);

endmodule
"""
