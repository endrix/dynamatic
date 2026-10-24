
from generators.handshake.buffers.one_slot_break_r import generate_one_slot_break_r
from generators.handshake.buffers.fifo_break_dv import generate_fifo_break_dv


def generate_load(name, params):
    addr_bitwidth = params["addr_bitwidth"]
    data_bitwidth = params["data_bitwidth"]

    if params.get("kill_drop", 0):
        if params.get("extra_signals", None):
            raise ValueError(
                "a load that drops on a kill carries no extra signals: its "
                "words are counted, not tagged")
        return _generate_load_kill_drop(name, data_bitwidth, addr_bitwidth)
    return _generate_load(name, data_bitwidth, addr_bitwidth)


def load_kill_drop_body(addr_slot, data_slot):
    """The body of a load whose requester a commit can stop: the two slots
    (the modules or instances named), the words owed and the words to drop.
    The memory controller cannot forget a granted read and an address in the
    load's own slot will be granted in its turn, so the load is not reset with
    the units it serves; on `kill` every word still owed is a dead
    evaluation's, taken from the controller and offered to nobody. At most
    three are owed (the two slots and the controller's word register for the
    port): two bits."""
    return f"""
  wire addr_ready, word_valid;
  reg [1 : 0] owed, drop;
  wire dropping = (drop != 2'd0);
  wire word_ready = dataOut_ready | dropping;

  {addr_slot} addr_one_slot_break_r (
    .clk        (clk            ),
    .rst        (rst            ),
    .ins        (addrIn         ),
    .ins_valid  (addrIn_valid   ),
    .ins_ready  (addr_ready     ),
    .outs       (addrOut        ),
    .outs_valid (addrOut_valid  ),
    .outs_ready (addrOut_ready  )
  );

  {data_slot} data_one_slot_break_r (
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
  wire [1 : 0] owed_next = owed + {{1'b0, accepted}} - {{1'b0, passed}};

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
"""


def _generate_load_kill_drop(name, data_bitwidth, addr_bitwidth):
    one_slot_break_r_address_name = name + "_one_slot_break_r_address"
    one_slot_break_r_address = generate_one_slot_break_r(
        one_slot_break_r_address_name, {"bitwidth": addr_bitwidth})

    one_slot_break_r_data_name = name + "_one_slot_break_r_data"
    one_slot_break_r_data = generate_one_slot_break_r(
        one_slot_break_r_data_name, {"bitwidth": data_bitwidth})

    body = load_kill_drop_body(one_slot_break_r_address_name,
                               one_slot_break_r_data_name)
    return one_slot_break_r_address + one_slot_break_r_data + f"""

// Module of Load (dropping on a kill)
module {name}(
  input clk,
  input rst,
  // Address from Circuit Channel
  input  [{addr_bitwidth} - 1 : 0] addrIn,
  input  addrIn_valid,
  output addrIn_ready,
  // Address to Interface Channel
  output [{addr_bitwidth} - 1 : 0] addrOut,
  output addrOut_valid,
  input  addrOut_ready,
  // Data from Interface Channel
  input  [{data_bitwidth} - 1 : 0] dataFromMem,
  input  dataFromMem_valid,
  output dataFromMem_ready,
  // Data from Memory Channel
  output [{data_bitwidth} - 1 : 0] dataOut,
  output dataOut_valid,
  input  dataOut_ready,
  // the requester was stopped: what it is owed is dropped
  input  kill
);
{body}
endmodule
"""


def _generate_load(name, data_bitwidth, addr_bitwidth):

    one_slot_break_r_address_name = name + "_one_slot_break_r_address"
    one_slot_break_r_address = generate_one_slot_break_r(
        one_slot_break_r_address_name, {"bitwidth": addr_bitwidth})

    one_slot_break_r_data_name = name + "_one_slot_break_r_data"
    one_slot_break_r_data = generate_one_slot_break_r(
        one_slot_break_r_data_name, {"bitwidth": data_bitwidth})

    load_body = f"""

// Module of Load
module {name} #(
  parameter data_bitwidth = {data_bitwidth},
  parameter addr_bitwidth = {addr_bitwidth}
)(
  input clk,
  input rst,
  // Address from Circuit Channel
  input  [{addr_bitwidth} - 1 : 0] addrIn,
  input  addrIn_valid,
  output addrIn_ready,
  // Address to Interface Channel
  output [{addr_bitwidth} - 1 : 0] addrOut,
  output addrOut_valid,
  input  addrOut_ready,
  // Data from Interface Channel
  input  [{data_bitwidth} - 1 : 0] dataFromMem,
  input  dataFromMem_valid,
  output dataFromMem_ready,
  // Data from Memory Channel
  output [{data_bitwidth} - 1 : 0] dataOut,
  output dataOut_valid,
  input  dataOut_ready
);
  {one_slot_break_r_address_name} addr_one_slot_break_r (
    .clk        (clk            ),
    .rst        (rst            ),
    .ins        (addrIn         ),
    .ins_valid  (addrIn_valid   ),
    .ins_ready  (addrIn_ready   ),
    .outs       (addrOut        ),
    .outs_valid (addrOut_valid  ),
    .outs_ready (addrOut_ready  )
  );

  {one_slot_break_r_data_name} data_one_slot_break_r (
    .clk        (clk                ),
    .rst        (rst                ),
    .ins        (dataFromMem        ),
    .ins_valid  (dataFromMem_valid  ),
    .ins_ready  (dataFromMem_ready  ),
    .outs       (dataOut            ),
    .outs_valid (dataOut_valid      ),
    .outs_ready (dataOut_ready      )
  );

endmodule
"""

    return one_slot_break_r_address + one_slot_break_r_data + load_body
