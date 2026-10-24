`timescale 1ns/1ps
// A priority merge that waits for its high input only.
//
// `hi` when it carries something, `lo` otherwise; payload 0 is "nothing
// selected". One token on each input per round, each taken the cycle it
// arrives; one answer per round: `hi` the cycle a non-zero `hi` arrives,
// whether `lo` has arrived or not, else `lo` once it is there. The round
// closes once both inputs are in and the answer has been taken, in the cycle
// it completes: the input that gave its token is ready again then and gives
// the next round's, and a non-zero next hi, with this round's answer out
// earlier, goes in that same cycle. Ready reads the other input's valid and
// outs_ready, as a join's does; valid and data out are combinational. The
// same circuit as data/vhdl/handshake/priority.vhd. The module is priority_merge:
// `priority` is a SystemVerilog keyword, and a tool reading this as
// SystemVerilog refuses it as a name.
module priority_merge # (
  parameter DATA_TYPE = 32
)(
  input  clk,
  input  rst,
  // Input channels
  input  [DATA_TYPE - 1 : 0] hi,
  input  hi_valid,
  output hi_ready,
  input  [DATA_TYPE - 1 : 0] lo,
  input  lo_valid,
  output lo_ready,
  // Output channel
  output [DATA_TYPE - 1 : 0] outs,
  output outs_valid,
  input  outs_ready
);

  // Round state: which inputs have given their token, whether the answer has
  // been taken, whether a non-zero hi is in, and the answer so far.
  reg seen_hi, seen_lo, emitted, hi_nz_r;
  reg [DATA_TYPE - 1 : 0] held;

  wire take_hi   = hi_valid & ~seen_hi;
  wire take_lo   = lo_valid & ~seen_lo;
  wire hi_here   = seen_hi | take_hi;
  wire lo_here   = seen_lo | take_lo;
  wire hi_is_nz  = (hi != {DATA_TYPE{1'b0}});
  wire hi_now_nz = take_hi & hi_is_nz;
  wire hi_nz     = hi_nz_r | hi_now_nz;

  // hi decides alone when it is non-zero; otherwise lo once it is here.
  wire valid_i = ~emitted & hi_here & (hi_nz | lo_here);
  wire fire    = valid_i & outs_ready;
  wire done    = hi_here & lo_here & (emitted | fire);

  // An input that has given its token is ready again the cycle the round
  // completes, which it reads from the OTHER input alone (its own token is
  // in): its ready never reads its own valid, and the output's valid never
  // reads the output's ready. The next round's tokens it takes then; with
  // the answer out earlier the output is free, and a non-zero hi among them
  // goes now.
  wire done_hi  = lo_here & (emitted | ((hi_nz_r | lo_here) & outs_ready));
  wire done_lo  = hi_here & (emitted | outs_ready);
  wire again_hi = hi_valid & seen_hi & done_hi;
  wire again_lo = lo_valid & seen_lo & done_lo;
  wire again_nz = again_hi & hi_is_nz;
  wire early    = hi_valid & seen_hi & lo_here & emitted & hi_is_nz;

  always @(posedge clk) begin
    if (rst) begin
      seen_hi <= 1'b0;
      seen_lo <= 1'b0;
      emitted <= 1'b0;
      hi_nz_r <= 1'b0;
      held    <= {DATA_TYPE{1'b0}};
    end else if (done) begin
      // The next round, from what it gave in this cycle.
      seen_hi <= again_hi;
      seen_lo <= again_lo;
      hi_nz_r <= again_nz;
      emitted <= early & outs_ready;
      if (again_nz)
        held <= hi;
      else if (again_lo)
        held <= lo;
      else
        held <= {DATA_TYPE{1'b0}};
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

  // Ready reads the other input's valid and outs_ready.
  assign hi_ready   = ~seen_hi | done_hi;
  assign lo_ready   = ~seen_lo | done_lo;
  assign outs       = (hi_now_nz | early) ? hi : ((hi_nz_r || !take_lo) ? held : lo);
  assign outs_valid = valid_i | early;

endmodule
