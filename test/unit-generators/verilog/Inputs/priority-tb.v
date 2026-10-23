`timescale 1ns/1ps
// A testbench for handshake.priority, used by priority-iverilog.mlir: the
// unit under test is `dut`, 4 bits wide, driven by the rounds of
// priority-vectors.txt (the same rounds as the VHDL testbench), one a cycle:
// the inputs are set, the combinational outputs checked, the clock ticks.
// Prints a MISMATCH line for each wrong cycle and exits 1 on any.
module tb;
  reg clk = 0, rst = 1;
  always #5 clk = ~clk;
  reg [3:0] hi = 0, lo = 0;
  reg hv = 0, lv = 0, rdy = 0;
  wire [3:0] outs;
  wire hr, lr, ov;
  dut d(.clk(clk), .rst(rst), .hi(hi), .hi_valid(hv), .hi_ready(hr),
        .lo(lo), .lo_valid(lv), .lo_ready(lr),
        .outs(outs), .outs_valid(ov), .outs_ready(rdy));
  integer f, r, cycle, errs;
  integer a_hv, a_hi, a_lv, a_lo, a_r, e_ov, e_o, e_hr, e_lr;
  reg [255:0] junk;
  initial begin
    cycle = 0; errs = 0;
    f = $fopen("priority-vectors.txt", "r");
    if (f == 0) begin $display("failure: no priority-vectors.txt"); $finish; end
    @(posedge clk); @(posedge clk); #1 rst = 0;
    while (!$feof(f)) begin
      r = $fscanf(f, "%d %d %d %d %d %d %d %d %d\n",
                  a_hv, a_hi, a_lv, a_lo, a_r, e_ov, e_o, e_hr, e_lr);
      if (r == 9) begin
        hv = a_hv; hi = a_hi; lv = a_lv; lo = a_lo; rdy = a_r;
        #1;
        if (hr !== e_hr[0] || lr !== e_lr[0] || ov !== e_ov[0]
            || (e_ov == 1 && outs !== e_o[3:0])) begin
          errs = errs + 1;
          $display("MISMATCH cycle %0d: hi_ready %b lo_ready %b outs_valid %b outs %0d, expected %0d %0d %0d %0d",
                   cycle, hr, lr, ov, outs, e_hr, e_lr, e_ov, e_o);
        end
        @(posedge clk); #1;
        cycle = cycle + 1;
      end else begin
        r = $fgets(junk, f); // a comment line
      end
    end
    if (errs == 0) $display("priority: %0d cycles as expected", cycle);
    else $display("failure: %0d mismatches", errs);
    $finish;
  end
endmodule
