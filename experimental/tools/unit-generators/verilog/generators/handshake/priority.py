
def generate_priority(name, params):
    """A priority merge that waits for its high input only.

    `hi` when it carries something, `lo` otherwise; payload 0 is "nothing
    selected". One token on each input per round, each taken the cycle it
    arrives; one answer per round: `hi` the cycle a non-zero `hi` arrives,
    whether `lo` has arrived or not, else `lo` once it is there. The round
    closes once both inputs are in and the answer has been taken. The VHDL
    generator's twin (tools/unit-generators/vhdl/.../priority.py): one data
    register holds the answer as far as it is known, a non-zero `hi` or else
    `lo`.
    """
    bitwidth = params["bitwidth"]
    if bitwidth == 0:
        raise ValueError(
            "handshake.priority has no dataless form: the payload is the "
            "answer, and zero is 'nothing selected'. A dataless priority is "
            "a join.")
    if params.get("extra_signals", None):
        raise ValueError(
            "handshake.priority holds its payload alone; a channel with "
            "extra signals would lose them (the op's verifier refuses it)")
    return _generate_priority(name, bitwidth)


def _generate_priority(name, bitwidth):
    return f"""

// Module of priority

module {name}(
  input  clk,
  input  rst,
  // Input channels
  input  [{bitwidth} - 1 : 0] hi,
  input  hi_valid,
  output hi_ready,
  input  [{bitwidth} - 1 : 0] lo,
  input  lo_valid,
  output lo_ready,
  // Output channel
  output [{bitwidth} - 1 : 0] outs,
  output outs_valid,
  input  outs_ready
);

  // Round state: which inputs have given their token, whether the answer has
  // been taken, whether a non-zero hi is in, and the answer so far.
  reg seen_hi, seen_lo, emitted, hi_nz_r;
  reg [{bitwidth} - 1 : 0] held;

  wire take_hi   = hi_valid & ~seen_hi;
  wire take_lo   = lo_valid & ~seen_lo;
  wire hi_here   = seen_hi | take_hi;
  wire lo_here   = seen_lo | take_lo;
  wire hi_now_nz = take_hi & (hi != {{{bitwidth}{{1'b0}}}});
  wire hi_nz     = hi_nz_r | hi_now_nz;

  // hi decides alone when it is non-zero; otherwise lo once it is here.
  wire valid_i = ~emitted & hi_here & (hi_nz | lo_here);
  wire fire    = valid_i & outs_ready;
  wire done    = hi_here & lo_here & (emitted | fire);

  always @(posedge clk) begin
    if (rst || done) begin
      seen_hi <= 1'b0;
      seen_lo <= 1'b0;
      emitted <= 1'b0;
      hi_nz_r <= 1'b0;
      held    <= {{{bitwidth}{{1'b0}}}};
    end else begin
      seen_hi <= hi_here;
      seen_lo <= lo_here;
      hi_nz_r <= hi_nz;
      // What the answer needs of an input taken while the sink is stalled:
      // a non-zero hi, else lo.
      if (hi_now_nz)
        held <= hi;
      else if (take_lo && !hi_nz_r)
        held <= lo;
      if (fire)
        emitted <= 1'b1;
    end
  end

  // Ready is a function of registers only.
  assign hi_ready   = ~seen_hi;
  assign lo_ready   = ~seen_lo;
  assign outs       = hi_now_nz ? hi : ((hi_nz_r || !take_lo) ? held : lo);
  assign outs_valid = valid_i;

endmodule
"""
