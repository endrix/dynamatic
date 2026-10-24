def generate_kill_or(name, params):
    """The kill of a domain with several commits (`handshake.commit`): the OR
    of their kills, which HandshakeToHW gives the domain's units as their
    reset. `size` one-bit inputs, `ins`, one output, `outs`; combinational,
    no clock and no reset (each commit's kill has the reset in it already).
    Not a Handshake unit: the lowering's own, as mem_to_bram is.
    """
    size = params["size"]
    if size < 2:
        raise ValueError(
            "kill_or ORs the kills of a domain's commits, and the lowering "
            "builds one only for a domain with two or more")
    return f"""

// Module of kill_or

module {name}(
  // the kills of the domain's commits
  input  [{size} - 1 : 0] ins,
  // the domain's kill
  output outs
);
  assign outs = |ins;
endmodule
"""
