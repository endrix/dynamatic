`timescale 1ns/1ps
// A testbench for handshake.first, used by first-iverilog.mlir: the unit
// under test is `dut`, three inputs of two bits, driven by the rounds of
// first-vectors.txt (the VHDL testbench's), one a cycle: the inputs are set,
// the combinational outputs checked, the clock ticks. Prints a MISMATCH line
// for each wrong cycle.
module tb;
  reg clk = 0, rst = 1;
  always #5 clk = ~clk;
  reg [5:0] ins = 0;
  reg [2:0] iv = 0;
  reg rdy = 0;
  wire [1:0] outs;
  wire [2:0] ir;
  wire ov;
  dut d(.clk(clk), .rst(rst), .ins(ins), .ins_valid(iv), .ins_ready(ir),
        .outs(outs), .outs_valid(ov), .outs_ready(rdy));
  integer f, r, cycle, errs, k;
  integer e [0:11];
  reg [255:0] junk;
  initial begin
    cycle = 0; errs = 0;
    f = $fopen("first-vectors.txt", "r");
    if (f == 0) begin $display("failure: no first-vectors.txt"); $finish; end
    @(posedge clk); @(posedge clk); #1 rst = 0;
    while (!$feof(f)) begin
      r = $fscanf(f, "%d %d %d %d %d %d %d %d %d %d %d %d\n",
                  e[0], e[1], e[2], e[3], e[4], e[5], e[6], e[7], e[8], e[9], e[10], e[11]);
      if (r == 12) begin
        for (k = 0; k < 3; k = k + 1) begin
          iv[k] = e[k];
          ins[k * 2 +: 2] = e[3 + k];
        end
        rdy = e[6];
        #1;
        if (ov !== e[7][0] || (e[7] == 1 && outs !== e[8][1:0])
            || ir[0] !== e[9][0] || ir[1] !== e[10][0] || ir[2] !== e[11][0]) begin
          errs = errs + 1;
          $display("MISMATCH cycle %0d: outs_valid %b outs %0d ins_ready %b", cycle, ov, outs, ir);
        end
        @(posedge clk); #1;
        cycle = cycle + 1;
      end else begin
        r = $fgets(junk, f); // a comment line
      end
    end
    if (errs == 0) $display("first: %0d cycles as expected", cycle);
    else $display("failure: %0d mismatches", errs);
    $finish;
  end
endmodule
