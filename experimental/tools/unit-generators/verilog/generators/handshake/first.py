
def generate_first(name, params):
    """A first-wins merge with full consumption.

    `merge` forwards one input and consumes ONE token per firing. `first`
    consumes exactly one token on EVERY input per round and emits one, and the
    payload it emits is the first non-zero one to ARRIVE. Payload 0 is the
    reserved "nothing selected" value, which is what makes a winner
    distinguishable from a loser.

    Emitting early and consuming everything are opposite deadlines. The `seen`
    mask reconciles them: an input that has given its token is not ready again
    until the round closes, so the round boundary is local state and no
    round-start signal is needed anywhere.

    `ins_ready` is a function of REGISTERS ONLY, so this unit cannot close a
    valid -> ready -> valid ring the way a lazy fork can. Valid and data are
    combinational: latency zero, one round per cycle when every input is valid
    and the sink is ready.
    """
    size = params["size"]
    bitwidth = params["bitwidth"]

    if bitwidth == 0:
        raise ValueError(
            "handshake.first has no dataless form: the payload is what "
            "distinguishes a winner from a loser. A dataless first-wins unit "
            "is a join.")

    return _generate_first(name, size, bitwidth)


def _generate_first(name, size, bitwidth):
    return f"""

// Module of first

module {name}(
  input  clk,
  input  rst,
  // Input channels
  input  [{size} * {bitwidth} - 1 : 0] ins,
  input  [{size} - 1 : 0] ins_valid,
  output [{size} - 1 : 0] ins_ready,
  // Output channel
  output [{bitwidth} - 1 : 0] outs,
  output outs_valid,
  input  outs_ready
);

  // Round state.
  reg [{size} - 1 : 0]     seen;
  reg [{bitwidth} - 1 : 0] winner;
  reg                      has_win;
  reg                      emitted;

  wire [{size} - 1 : 0] taken     = ins_valid & ~seen;
  wire [{size} - 1 : 0] seen_next = seen | taken;

  // The first input carrying an action THIS cycle, by index order.
  reg                      cand_v;
  reg [{bitwidth} - 1 : 0] cand;
  integer i;
  always @(*) begin
    cand_v = 1'b0;
    cand   = {{{bitwidth}{{1'b0}}}};
    for (i = 0; i < {size}; i = i + 1) begin
      if (!cand_v && taken[i] && (ins[i * {bitwidth} +: {bitwidth}] != {{{bitwidth}{{1'b0}}}})) begin
        cand_v = 1'b1;
        cand   = ins[i * {bitwidth} +: {bitwidth}];
      end
    end
  end

  wire closing = (seen_next == {{{size}{{1'b1}}}});

  // Emit the instant a winner exists, or emit "nothing selected" when the
  // round closes without one.
  wire valid_i = (has_win | cand_v | closing) & ~emitted;
  wire fire    = valid_i & outs_ready;
  // The round is over once every input has given its token AND the output has
  // been taken. Those can happen in either order.
  wire done    = closing & (emitted | fire);

  always @(posedge clk) begin
    if (rst || done) begin
      seen    <= {{{size}{{1'b0}}}};
      winner  <= {{{bitwidth}{{1'b0}}}};
      has_win <= 1'b0;
      emitted <= 1'b0;
    end else begin
      seen <= seen_next;
      // A token taken while the sink is stalled is still TAKEN, so it is
      // latched here and held rather than lost.
      if (!has_win && cand_v) begin
        has_win <= 1'b1;
        winner  <= cand;
      end
      // Having emitted early, stay quiet while absorbing the stragglers.
      if (fire)
        emitted <= 1'b1;
    end
  end

  assign ins_ready  = ~seen;
  assign outs       = has_win ? winner : cand;
  assign outs_valid = valid_i;

endmodule
"""
