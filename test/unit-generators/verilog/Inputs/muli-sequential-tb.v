`timescale 1ns/1ps
// A testbench for muli_sequential (data/verilog/arith/muli_sequential.v),
// used by muli-sequential-iverilog.mlir: the low W bits of the product of
// random operands at S multiplier bits a cycle, the multiplier's bits from IW
// up zero when IW is above 0 (the unit's ITER_WIDTH), and the cycles a
// multiply takes, ceil(IW / S) (ceil(W / S) without IW). Prints a MISMATCH
// line for each wrong product, count or handshake.
module tb;
  parameter W = 8;
  parameter S = 3;
  parameter IW = 0;
  localparam MB = (IW == 0) ? W : IW;
  localparam ITERS = (MB + S - 1) / S;

  reg clk = 0, rst = 1;
  always #5 clk = ~clk;

  reg [W - 1 : 0] a = 0, b = 0;
  reg av = 0, bv = 0, pr = 0;
  wire ar, br, pv;
  wire [W - 1 : 0] p;

  muli_sequential #(.DATA_TYPE(W), .STEP(S), .ITER_WIDTH(IW)) u (
    .clk(clk), .rst(rst),
    .lhs(a), .lhs_valid(av), .lhs_ready(ar),
    .rhs(b), .rhs_valid(bv), .rhs_ready(br),
    .result(p), .result_valid(pv), .result_ready(pr));

  integer i, k, n, errs, checks;
  reg [W - 1 : 0] want;
  reg [127 : 0] ra, rb;

  initial begin
    errs = 0; checks = 0;
    @(posedge clk); @(posedge clk); #1 rst = 0;
    for (i = 0; i < 60; i = i + 1) begin
      ra = {$random, $random, $random, $random};
      rb = {$random, $random, $random, $random};
      if (i == 0) begin ra = {128{1'b1}}; rb = {128{1'b1}}; end
      if (i == 1) rb = 0;
      a = ra[W - 1 : 0];
      b = rb[W - 1 : 0];
      // The multiplier's bits from IW up are zero.
      for (k = MB; k < W; k = k + 1) b[k] = 1'b0;
      want = a * b;
      av = 1; bv = 1; pr = 0;
      #1;
      if (!(ar && br)) begin
        $display("MISMATCH %0d: the operands not taken by an idle unit", i);
        errs = errs + 1;
      end
      @(posedge clk); #1;
      av = 0; bv = 0;
      n = 0;
      while (!pv && n <= ITERS + 1) begin
        @(posedge clk); #1;
        n = n + 1;
      end
      checks = checks + 1;
      if (n != ITERS) begin
        $display("MISMATCH %0d: %0d cycles, not %0d", i, n, ITERS);
        errs = errs + 1;
      end
      if (p !== want) begin
        $display("MISMATCH %0d: %h * %h = %h, not %h", i, a, b, p, want);
        errs = errs + 1;
      end
      // Held until taken.
      @(posedge clk); #1;
      if (!pv || p !== want) begin
        $display("MISMATCH %0d: the product not held", i);
        errs = errs + 1;
      end
      pr = 1;
      @(posedge clk); #1;
      pr = 0;
      if (pv) begin
        $display("MISMATCH %0d: the product not gone once taken", i);
        errs = errs + 1;
      end
    end
    $display("muli_sequential W=%0d S=%0d IW=%0d: %0d multiplies, %0d mismatches",
             W, S, IW, checks, errs);
    $finish;
  end
endmodule
