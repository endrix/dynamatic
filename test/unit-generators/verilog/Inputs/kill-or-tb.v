`timescale 1ns/1ps
// A testbench for kill-or-iverilog.mlir: `dut`, a kill_or of three kills (the
// generator's, or the static module under that name), driven with every
// combination of its inputs; its output must be their OR.
module tb;
  reg [2:0] ins = 0;
  wire outs;
  integer i, errs;
  dut d(.ins(ins), .outs(outs));
  initial begin
    errs = 0;
    for (i = 0; i < 8; i = i + 1) begin
      ins = i;
      #1;
      if (outs !== (i != 0)) begin
        errs = errs + 1;
        $display("MISMATCH inputs %0d: outs %b", i, outs);
      end
    end
    if (errs == 0) $display("kill_or: 8 combinations as expected");
    else $display("failure: %0d mismatches", errs);
    $finish;
  end
endmodule
