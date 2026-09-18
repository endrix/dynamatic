`timescale 1ns/1ps
// One division at a time, one quotient bit per cycle: the Vitis IP's
// restoring step (a shifted remainder minus the divisor; the bit is the
// borrow's complement, the remainder the difference when it did not borrow)
// run DATA_TYPE times over one register set instead of DATA_TYPE stages, so
// the quotient is the IP's bit for bit, division by zero included (every
// step fails to borrow: all ones). The operands are joined and taken when
// the unit is idle and no quotient is waiting; the quotient is held until it
// is taken. A new division starts the cycle the quotient goes, DATA_TYPE + 1
// cycles after the operands. This is the same unit the VHDL generator writes
// for IMPL = "sequential" (tools/unit-generators/vhdl/generators/handshake/divui.py).
module divui_sequential #(
  parameter DATA_TYPE = 32
)(
  // inputs
  input  clk,
  input  rst,
  input  [DATA_TYPE - 1 : 0] lhs,
  input  lhs_valid,
  input  [DATA_TYPE - 1 : 0] rhs,
  input  rhs_valid,
  input  result_ready,
  // outputs
  output [DATA_TYPE - 1 : 0] result,
  output result_valid,
  output lhs_ready,
  output rhs_ready
);

  localparam COUNT_WIDTH = $clog2(DATA_TYPE + 1);

  wire join_valid;
  wire idle;
  wire accept;

  reg busy = 1'b0;
  reg done = 1'b0;
  reg [COUNT_WIDTH - 1 : 0] count = 0;
  reg [DATA_TYPE - 1 : 0] dividend = 0;
  reg [DATA_TYPE - 1 : 0] divisor = 0;
  reg [DATA_TYPE - 1 : 0] remd = 0;

  wire [DATA_TYPE - 1 : 0] comb;
  wire [DATA_TYPE : 0] cal;

  // the operands are taken together, when nothing is running and no
  // quotient is waiting (or it goes this cycle)
  assign idle = (~busy) & ((~done) | result_ready);

  join_type #(
    .SIZE(2)
  ) join_inputs (
    .ins_valid  ({rhs_valid, lhs_valid}),
    .outs_ready (idle),
    .ins_ready  ({rhs_ready, lhs_ready}),
    .outs_valid (join_valid)
  );

  assign accept = join_valid & idle;

  // one restoring step: the Vitis IP's, on registers instead of stages
  assign comb = {remd[DATA_TYPE - 2 : 0], dividend[DATA_TYPE - 1]};
  assign cal  = {1'b0, comb} - {1'b0, divisor};

  always @(posedge clk) begin
    if (rst) begin
      busy  <= 1'b0;
      done  <= 1'b0;
      count <= 0;
    end else begin
      if (done && result_ready)
        done <= 1'b0;
      if (accept) begin
        dividend <= lhs;
        divisor  <= rhs;
        remd     <= 0;
        count    <= 0;
        busy     <= 1'b1;
      end else if (busy) begin
        // the quotient bit shifts in from the right; after DATA_TYPE steps
        // the dividend register holds the quotient
        dividend <= {dividend[DATA_TYPE - 2 : 0], ~cal[DATA_TYPE]};
        if (cal[DATA_TYPE])
          remd <= comb;
        else
          remd <= cal[DATA_TYPE - 1 : 0];
        if (count == DATA_TYPE - 1) begin
          busy <= 1'b0;
          done <= 1'b1;
        end
        count <= count + 1;
      end
    end
  end

  assign result = dividend;
  assign result_valid = done;

endmodule
