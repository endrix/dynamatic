`timescale 1ns/1ps
// A testbench for handshake.race, used by race-iverilog.mlir: the unit under
// test is `dut`, generated with CANDIDATES
// "t0/p1:f0:u1:a0/p2:f2:a0/p16:f0:u0:a0,2/p4:f3,1:a0,2,3" (one 5-bit token,
// four flags), driven by the rounds of race-vectors.txt (the VHDL
// testbench's), one a cycle: the inputs are set, the combinational outputs
// checked, the clock ticks. Prints a MISMATCH line for each wrong cycle.
module tb;
  reg clk = 0, rst = 1;
  always #5 clk = ~clk;
  reg [4:0] tokens = 0;
  reg [0:0] tv = 0;
  reg [3:0] flags = 0, fv = 0;
  reg rdy = 0;
  wire [4:0] outs;
  wire [0:0] tr;
  wire [3:0] fr;
  wire ov;
  dut d(.clk(clk), .rst(rst), .tokens(tokens), .tokens_valid(tv), .tokens_ready(tr),
        .flags(flags), .flags_valid(fv), .flags_ready(fr),
        .outs(outs), .outs_valid(ov), .outs_ready(rdy));
  integer f, r, cycle, errs, k;
  integer e [0:17];
  reg [1023:0] junk;
  initial begin
    cycle = 0; errs = 0;
    f = $fopen("race-vectors.txt", "r");
    if (f == 0) begin $display("failure: no race-vectors.txt"); $finish; end
    @(posedge clk); @(posedge clk); #1 rst = 0;
    while (!$feof(f)) begin
      r = $fscanf(f, "%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d\n",
                  e[0], e[1], e[2], e[3], e[4], e[5], e[6], e[7], e[8], e[9],
                  e[10], e[11], e[12], e[13], e[14], e[15], e[16], e[17]);
      if (r == 18) begin
        // input 0 the token, 1 to 4 the flags
        tv[0] = e[0];
        tokens = e[5];
        for (k = 0; k < 4; k = k + 1) begin
          fv[k] = e[1 + k];
          flags[k] = e[6 + k];
        end
        rdy = e[10];
        #1;
        if (ov !== e[11][0] || (e[11] == 1 && outs !== e[12][4:0])
            || tr[0] !== e[13][0] || fr[0] !== e[14][0] || fr[1] !== e[15][0]
            || fr[2] !== e[16][0] || fr[3] !== e[17][0]) begin
          errs = errs + 1;
          $display("MISMATCH cycle %0d: outs_valid %b outs %0d tokens_ready %b flags_ready %b",
                   cycle, ov, outs, tr, fr);
        end
        @(posedge clk); #1;
        cycle = cycle + 1;
      end else begin
        r = $fgets(junk, f); // a comment line
      end
    end
    if (errs == 0) $display("race: %0d cycles as expected", cycle);
    else $display("failure: %0d mismatches", errs);
    $finish;
  end
endmodule
