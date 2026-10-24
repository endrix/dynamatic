`timescale 1ns/1ps
// A testbench for handshake.stand_in with two kills, used by
// stand-in-iverilog.mlir: the unit under test is `dut`, a 2-bit payload and a
// 2-bit kill, driven by stand-in2-vectors.txt (the VHDL's outputs on the same
// inputs), one line a cycle: the inputs set, the combinational outputs
// checked, the clock ticks. Prints a MISMATCH line for each wrong cycle. The
// unit's own assertion (its precondition) stops the simulation with a FATAL
// if a vector breaks it.
module tb;
  reg clk = 0, rst = 1;
  always #5 clk = ~clk;
  reg [1:0] ins = 0, k = 0;
  reg iv = 0, rdy = 0;
  wire [1:0] outs;
  wire ov, ir;
  dut d(.clk(clk), .rst(rst), .ins(ins), .ins_valid(iv), .ins_ready(ir), .kill(k),
        .outs(outs), .outs_valid(ov), .outs_ready(rdy));
  integer f, r, cycle, errs;
  integer e [0:8];
  reg [8 * 256 - 1 : 0] line;
  initial begin
    cycle = 0; errs = 0;
    f = $fopen("stand-in2-vectors.txt", "r");
    if (f == 0) begin $display("failure: no stand-in2-vectors.txt"); $finish; end
    @(posedge clk); @(posedge clk); #1;
    while (!$feof(f)) begin
      // (a line is parsed only when read: at the end $fgets reads nothing)
      line = 0;
      r = $fgets(line, f);
      r = $sscanf(line, "%d %d %d %d %d %d %d %d %d",
                  e[0], e[1], e[2], e[3], e[4], e[5], e[6], e[7], e[8]);
      if (r == 9) begin
        rst = e[0]; iv = e[1]; ins = e[2]; k = {e[4][0], e[3][0]}; rdy = e[5];
        #1;
        if (ov !== e[6][0] || (e[6] == 1 && outs !== e[7][1:0]) || ir !== e[8][0]) begin
          errs = errs + 1;
          $display("MISMATCH cycle %0d: outs_valid %b outs %0d ins_ready %b", cycle, ov, outs, ir);
        end
        @(posedge clk); #1;
        cycle = cycle + 1;
      end
    end
    if (errs == 0) $display("stand_in, two kills: %0d cycles as expected", cycle);
    else $display("failure: %0d mismatches", errs);
    $finish;
  end
endmodule
