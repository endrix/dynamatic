`timescale 1ns/1ps
// A testbench for the load that drops on a kill, used by
// load-kill-drop-iverilog.mlir: the unit under test is `dut`, 2-bit addresses
// and 8-bit words, driven by load-kill-drop-vectors.txt (the VHDL's outputs on
// the same inputs), one line a cycle: the inputs set, the combinational outputs
// checked, the clock ticks. Prints a MISMATCH line for each wrong cycle.
module tb;
  reg clk = 0, rst = 1;
  always #5 clk = ~clk;
  reg [1:0] addrIn = 0;
  reg [7:0] dataFromMem = 0;
  reg addrIn_valid = 0, addrOut_ready = 0, dataFromMem_valid = 0, dataOut_ready = 0, kill = 0;
  wire [1:0] addrOut;
  wire [7:0] dataOut;
  wire addrIn_ready, addrOut_valid, dataFromMem_ready, dataOut_valid;
  dut d(.clk(clk), .rst(rst), .addrIn(addrIn), .addrIn_valid(addrIn_valid),
        .addrIn_ready(addrIn_ready), .addrOut(addrOut), .addrOut_valid(addrOut_valid),
        .addrOut_ready(addrOut_ready), .dataFromMem(dataFromMem),
        .dataFromMem_valid(dataFromMem_valid), .dataFromMem_ready(dataFromMem_ready),
        .dataOut(dataOut), .dataOut_valid(dataOut_valid), .dataOut_ready(dataOut_ready),
        .kill(kill));
  integer f, r, cycle, errs;
  integer e [0:13];
  reg [8 * 256 - 1 : 0] line;
  initial begin
    cycle = 0; errs = 0;
    f = $fopen("load-kill-drop-vectors.txt", "r");
    if (f == 0) begin $display("failure: no load-kill-drop-vectors.txt"); $finish; end
    @(posedge clk); @(posedge clk); #1;
    while (!$feof(f)) begin
      // (a line is parsed only when read: at the end $fgets reads nothing)
      line = 0;
      r = $fgets(line, f);
      r = $sscanf(line, "%d %d %d %d %d %d %d %d %d %d %d %d %d %d",
                  e[0], e[1], e[2], e[3], e[4], e[5], e[6], e[7],
                  e[8], e[9], e[10], e[11], e[12], e[13]);
      if (r == 14) begin
        rst = e[0]; addrIn = e[1]; addrIn_valid = e[2]; addrOut_ready = e[3];
        dataFromMem = e[4]; dataFromMem_valid = e[5]; dataOut_ready = e[6]; kill = e[7];
        #1;
        if (addrIn_ready !== e[8][0] || addrOut_valid !== e[9][0]
            || (e[9] == 1 && addrOut !== e[10][1:0])
            || dataFromMem_ready !== e[11][0] || dataOut_valid !== e[12][0]
            || (e[12] == 1 && dataOut !== e[13][7:0])) begin
          errs = errs + 1;
          $display("MISMATCH cycle %0d: addrIn_ready %b addrOut_valid %b addrOut %0d dataFromMem_ready %b dataOut_valid %b dataOut %0d",
                   cycle, addrIn_ready, addrOut_valid, addrOut, dataFromMem_ready, dataOut_valid, dataOut);
        end
        @(posedge clk); #1;
        cycle = cycle + 1;
      end
    end
    if (errs == 0) $display("load kill drop: %0d cycles as expected", cycle);
    else $display("failure: %0d mismatches", errs);
    $finish;
  end
endmodule
