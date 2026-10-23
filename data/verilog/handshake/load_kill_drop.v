`timescale 1ns/1ps
// A load whose requester a commit can stop (`handshake.load` under
// `handshake.kill_domain`). The memory controller cannot forget a granted read
// and an address in the load's own slot will be granted in its turn, so the
// load is not reset with the units it serves: it counts the words it owes them
// and, on `kill`, every word still owed is a dead evaluation's and is taken
// from the controller and offered to nobody. The same circuit as
// data/vhdl/handshake/load_kill_drop.vhd.
module load_kill_drop #(
  parameter DATA_TYPE = 32,
  parameter ADDR_TYPE = 32
)(
  input clk,
  input rst,
  // Address from Circuit Channel
  input  [ADDR_TYPE - 1 : 0] addrIn,
  input  addrIn_valid,
  output addrIn_ready,
  // Address to Interface Channel
  output [ADDR_TYPE - 1 : 0] addrOut,
  output addrOut_valid,
  input  addrOut_ready,
  // Data from Interface Channel
  input  [DATA_TYPE - 1 : 0] dataFromMem,
  input  dataFromMem_valid,
  output dataFromMem_ready,
  // Data from Memory Channel
  output [DATA_TYPE - 1 : 0] dataOut,
  output dataOut_valid,
  input  dataOut_ready,
  // the requester was stopped: what it is owed is dropped
  input  kill
);

  wire addr_ready, word_valid;
  reg [1 : 0] owed, drop;
  wire dropping = (drop != 2'd0);
  wire word_ready = dataOut_ready | dropping;

  tehb #(.DATA_TYPE(ADDR_TYPE)) addr_one_slot_break_r (
    .clk        (clk            ),
    .rst        (rst            ),
    .ins        (addrIn         ),
    .ins_valid  (addrIn_valid   ),
    .ins_ready  (addr_ready     ),
    .outs       (addrOut        ),
    .outs_valid (addrOut_valid  ),
    .outs_ready (addrOut_ready  )
  );

  tehb #(.DATA_TYPE(DATA_TYPE)) data_one_slot_break_r (
    .clk        (clk                ),
    .rst        (rst                ),
    .ins        (dataFromMem        ),
    .ins_valid  (dataFromMem_valid  ),
    .ins_ready  (dataFromMem_ready  ),
    .outs       (dataOut            ),
    .outs_valid (word_valid         ),
    .outs_ready (word_ready         )
  );

  assign addrIn_ready  = addr_ready;
  // A word owed to a stopped evaluation is taken and offered to nobody.
  assign dataOut_valid = word_valid & ~dropping;

  wire accepted = addrIn_valid & addr_ready;
  wire passed   = word_valid & word_ready;
  wire [1 : 0] owed_next = owed + {1'b0, accepted} - {1'b0, passed};

  always @(posedge clk) begin
    if (rst) begin
      owed <= 2'd0;
      drop <= 2'd0;
    end else begin
      owed <= owed_next;
      // Everything still owed after the kill cycle is the dead evaluation's:
      // an address accepted in it included, a word passed on in it not.
      if (kill)
        drop <= owed_next;
      else if (dropping && passed)
        drop <= drop - 2'd1;
    end
  end

endmodule
