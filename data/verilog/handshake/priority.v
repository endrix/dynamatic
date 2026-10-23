`timescale 1ns/1ps
// A priority merge that waits for its high input only.
//
// `hi` when it carries something, `lo` otherwise; payload 0 is "nothing
// selected". One token on each input per round, each taken the cycle it
// arrives; one answer per round: `hi` the cycle a non-zero `hi` arrives,
// whether `lo` has arrived or not, else `lo` once it is there. The round
// closes once both inputs are in and the answer has been taken. Ready is a
// function of registers only; valid and data out are combinational. The same
// circuit as data/vhdl/handshake/priority.vhd. The module is priority_merge:
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

  reg seen_hi, seen_lo, emitted, hi_nz_r;
  reg [DATA_TYPE - 1 : 0] held;

  wire take_hi   = hi_valid & ~seen_hi;
  wire take_lo   = lo_valid & ~seen_lo;
  wire hi_here   = seen_hi | take_hi;
  wire lo_here   = seen_lo | take_lo;
  wire hi_now_nz = take_hi & (hi != {DATA_TYPE{1'b0}});
  wire hi_nz     = hi_nz_r | hi_now_nz;

  wire valid_i = ~emitted & hi_here & (hi_nz | lo_here);
  wire fire    = valid_i & outs_ready;
  wire done    = hi_here & lo_here & (emitted | fire);

  always @(posedge clk) begin
    if (rst || done) begin
      seen_hi <= 1'b0;
      seen_lo <= 1'b0;
      emitted <= 1'b0;
      hi_nz_r <= 1'b0;
      held    <= {DATA_TYPE{1'b0}};
    end else begin
      seen_hi <= hi_here;
      seen_lo <= lo_here;
      hi_nz_r <= hi_nz;
      if (hi_now_nz)
        held <= hi;
      else if (take_lo && !hi_nz_r)
        held <= lo;
      if (fire)
        emitted <= 1'b1;
    end
  end

  assign hi_ready   = ~seen_hi;
  assign lo_ready   = ~seen_lo;
  assign outs       = hi_now_nz ? hi : ((hi_nz_r || !take_lo) ? held : lo);
  assign outs_valid = valid_i;

endmodule
