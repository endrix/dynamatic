`timescale 1ns/1ps
// A first-wins merge with full consumption.
//
// `merge` forwards one input and consumes ONE token per firing. `first`
// consumes exactly one token on EVERY input per round and emits one, and the
// payload it emits is the first non-zero one to ARRIVE. Payload 0 is reserved
// for "nothing selected", so a winner is distinguishable from a loser and an
// all-zero round emits zero. Simultaneous arrivals are resolved by index
// order, which is free to choose because the operands are incomparable.
//
// Emitting early and consuming everything are opposite deadlines. The `seen`
// mask reconciles them: an input that has given its token is not ready again
// until the round closes, so the round boundary is local state and no
// round-start signal is needed anywhere.
//
// The round closes in the cycle it completes: an input that has given its
// token is ready again the cycle the last one arrives with the answer taken or
// being taken, and gives the next round's; with the answer out earlier, a
// winner among those goes in that same cycle. `ins_ready` reads the other
// inputs' valid and outs_ready, as a join's does, never its own input's valid.
// Valid and data are combinational: latency zero, one round per cycle when
// every input is valid and the sink is ready. The same circuit as the
// verilog-beta generator's
// (experimental/tools/unit-generators/verilog/generators/handshake/first.py).
module first # (
  parameter SIZE = 2,
  parameter DATA_TYPE = 32
)(
  input  clk,
  input  rst,
  // Input channels
  input  [SIZE * DATA_TYPE - 1 : 0] ins,
  input  [SIZE - 1 : 0] ins_valid,
  output [SIZE - 1 : 0] ins_ready,
  // Output channel
  output [DATA_TYPE - 1 : 0] outs,
  output outs_valid,
  input  outs_ready
);

  // Round state.
  reg [SIZE - 1 : 0] seen;
  reg [DATA_TYPE - 1 : 0] winner;
  reg               has_win;
  reg               emitted;

  wire [SIZE - 1 : 0] taken     = ins_valid & ~seen;
  wire [SIZE - 1 : 0] seen_next = seen | taken;
  wire               closing   = (seen_next == {SIZE{1'b1}});

  // The first non-zero payload among the tokens taken THIS cycle, by index
  // order.
  reg               cand_v;
  reg [DATA_TYPE - 1 : 0] cand;
  reg [SIZE - 1 : 0] carries;
  integer i;
  always @(*) begin
    cand_v = 1'b0;
    cand   = {DATA_TYPE{1'b0}};
    for (i = 0; i < SIZE; i = i + 1) begin
      carries[i] = taken[i] && (ins[i * DATA_TYPE +: DATA_TYPE] != {DATA_TYPE{1'b0}});
      if (!cand_v && carries[i]) begin
        cand_v = 1'b1;
        cand   = ins[i * DATA_TYPE +: DATA_TYPE];
      end
    end
  end

  // Emit the instant a winner exists, or emit "nothing selected" when the
  // round closes without one.
  wire valid_i = (has_win | cand_v | closing) & ~emitted;
  wire fire    = valid_i & outs_ready;
  // The round is over once every input has given its token AND the output has
  // been taken. Those can happen in either order.
  wire done    = closing & (emitted | fire);

  // An input that has given its token is ready again the cycle the round
  // completes, which it reads from the OTHER inputs alone (its own token is
  // in): its ready never reads its own valid, and the output's valid never
  // reads the output's ready. The next round's tokens it takes then; with the
  // answer out earlier the output is free, and a winner among them goes now.
  reg [SIZE - 1 : 0] done_wo, again;
  reg               again_v, early;
  reg [DATA_TYPE - 1 : 0] cand_again, cand_early;
  reg               all_others, any_other;
  integer j, k;
  always @(*) begin
    again_v    = 1'b0;
    early      = 1'b0;
    cand_again = {DATA_TYPE{1'b0}};
    cand_early = {DATA_TYPE{1'b0}};
    for (k = 0; k < SIZE; k = k + 1) begin
      all_others = 1'b1;
      any_other  = 1'b0;
      for (j = 0; j < SIZE; j = j + 1)
        if (j != k) begin
          all_others = all_others & seen_next[j];
          any_other  = any_other | carries[j];
        end
      done_wo[k] = all_others & (emitted | ((has_win | any_other | all_others) & outs_ready));
      again[k]   = ins_valid[k] & seen[k] & done_wo[k];
      if (!again_v && again[k] && (ins[k * DATA_TYPE +: DATA_TYPE] != {DATA_TYPE{1'b0}})) begin
        again_v    = 1'b1;
        cand_again = ins[k * DATA_TYPE +: DATA_TYPE];
      end
      if (!early && ins_valid[k] && seen[k] && all_others && emitted &&
          (ins[k * DATA_TYPE +: DATA_TYPE] != {DATA_TYPE{1'b0}})) begin
        early      = 1'b1;
        cand_early = ins[k * DATA_TYPE +: DATA_TYPE];
      end
    end
  end

  always @(posedge clk) begin
    if (rst) begin
      seen    <= {SIZE{1'b0}};
      winner  <= {DATA_TYPE{1'b0}};
      has_win <= 1'b0;
      emitted <= 1'b0;
    end else if (done) begin
      // The next round, from what it gave in this cycle.
      seen    <= again;
      has_win <= again_v;
      winner  <= cand_again;
      emitted <= early & outs_ready;
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

  assign ins_ready  = ~seen | done_wo;
  assign outs       = emitted ? cand_early : (has_win ? winner : cand);
  assign outs_valid = valid_i | early;

endmodule
