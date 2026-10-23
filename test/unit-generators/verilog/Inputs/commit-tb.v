`timescale 1ns/1ps
// A testbench for handshake.commit, used by commit-iverilog.mlir: the unit under
// test is `dut`, a 3-bit payload (or none, with DATALESS defined: the payload
// columns are then not driven nor checked), driven by commit-vectors.txt (the
// VHDL's outputs on the same inputs), one line a cycle: the inputs set, the
// outputs checked, the clock ticks. Prints a MISMATCH line for each wrong
// cycle.
module tb;
  reg clk = 0, rst = 1;
  always #5 clk = ~clk;
  reg iv = 0, rdy = 0;
  wire ov, ir, kill;
`ifdef DATALESS
  dut d(.clk(clk), .rst(rst), .ins_valid(iv), .ins_ready(ir),
        .outs_valid(ov), .outs_ready(rdy), .kill(kill));
`else
  reg [2:0] ins = 0;
  wire [2:0] outs;
  dut d(.clk(clk), .rst(rst), .ins(ins), .ins_valid(iv), .ins_ready(ir),
        .outs(outs), .outs_valid(ov), .outs_ready(rdy), .kill(kill));
`endif
  integer f, r, cycle, errs;
  integer e [0:7];
  reg [8 * 256 - 1 : 0] line;
  reg bad;
  initial begin
    cycle = 0; errs = 0;
    f = $fopen("commit-vectors.txt", "r");
    if (f == 0) begin $display("failure: no commit-vectors.txt"); $finish; end
    while (!$feof(f)) begin
      // (a line is parsed only when read: at the end $fgets reads nothing)
      line = 0;
      r = $fgets(line, f);
      r = $sscanf(line, "%d %d %d %d %d %d %d %d",
                  e[0], e[1], e[2], e[3], e[4], e[5], e[6], e[7]);
      if (r == 8) begin
        rst = e[0]; iv = e[1]; rdy = e[3];
`ifndef DATALESS
        ins = e[2];
`endif
        #1;
        bad = ov !== e[4][0] || ir !== e[6][0] || kill !== e[7][0];
`ifndef DATALESS
        bad = bad || outs !== e[5][2:0];
`endif
        if (bad) begin
          errs = errs + 1;
          $display("MISMATCH cycle %0d: outs_valid %b ins_ready %b kill %b", cycle, ov, ir, kill);
        end
        @(posedge clk); #1;
        cycle = cycle + 1;
      end
    end
    if (errs == 0) $display("commit: %0d cycles as expected", cycle);
    else $display("failure: %0d mismatches", errs);
    $finish;
  end
endmodule
