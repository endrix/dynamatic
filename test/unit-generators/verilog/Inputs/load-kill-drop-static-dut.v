`timescale 1ns/1ps
// The static load that drops on a kill (data/verilog/handshake/load_kill_drop.v,
// the module the Verilog configuration emits) under the generator's name and
// widths, so that load-kill-drop-tb.v drives both.
module dut (
  input clk, input rst,
  input [1:0] addrIn, input addrIn_valid, output addrIn_ready,
  output [1:0] addrOut, output addrOut_valid, input addrOut_ready,
  input [7:0] dataFromMem, input dataFromMem_valid, output dataFromMem_ready,
  output [7:0] dataOut, output dataOut_valid, input dataOut_ready,
  input kill
);
  load_kill_drop #(.DATA_TYPE(8), .ADDR_TYPE(2)) l (
    .clk(clk), .rst(rst), .addrIn(addrIn), .addrIn_valid(addrIn_valid),
    .addrIn_ready(addrIn_ready), .addrOut(addrOut), .addrOut_valid(addrOut_valid),
    .addrOut_ready(addrOut_ready), .dataFromMem(dataFromMem),
    .dataFromMem_valid(dataFromMem_valid), .dataFromMem_ready(dataFromMem_ready),
    .dataOut(dataOut), .dataOut_valid(dataOut_valid), .dataOut_ready(dataOut_ready),
    .kill(kill));
endmodule
