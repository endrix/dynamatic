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
// `ins_ready` is a function of REGISTERS ONLY -- nothing here reads outs_ready
// or any ins_valid -- so this unit cannot close a valid -> ready -> valid ring
// the way a lazy fork can. Valid and data are combinational: latency zero, one
// round per cycle when every input is valid and the sink is ready.
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
  reg [SIZE - 1 : 0]      seen;
  reg [DATA_TYPE - 1 : 0] winner;
  reg                     has_win;
  reg                     emitted;

  wire [SIZE - 1 : 0] taken     = ins_valid & ~seen;
  wire [SIZE - 1 : 0] seen_next = seen | taken;

  // The first non-zero payload among the tokens taken THIS cycle, by index
  // order.
  reg                     cand_v;
  reg [DATA_TYPE - 1 : 0] cand;
  integer i;
  always @(*) begin
    cand_v = 1'b0;
    cand   = {DATA_TYPE{1'b0}};
    for (i = 0; i < SIZE; i = i + 1) begin
      if (!cand_v && taken[i] && (ins[i * DATA_TYPE +: DATA_TYPE] != {DATA_TYPE{1'b0}})) begin
        cand_v = 1'b1;
        cand   = ins[i * DATA_TYPE +: DATA_TYPE];
      end
    end
  end

  wire closing = (seen_next == {SIZE{1'b1}});

  // Emit the instant a winner exists, or emit "nothing selected" when the
  // round closes without one.
  wire valid_i = (has_win | cand_v | closing) & ~emitted;
  wire fire    = valid_i & outs_ready;
  // The round is over once every input has given its token AND the output has
  // been taken. Those can happen in either order.
  wire done    = closing & (emitted | fire);

  always @(posedge clk) begin
    if (rst || done) begin
      seen    <= {SIZE{1'b0}};
      winner  <= {DATA_TYPE{1'b0}};
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
