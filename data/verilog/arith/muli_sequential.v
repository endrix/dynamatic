`timescale 1ns/1ps
// One multiply at a time, STEP multiplier bits a cycle: each cycle adds the
// multiplicand times the next STEP bits of the multiplier, shifted, to the
// accumulator, all modulo 2^DATA_TYPE -- the low DATA_TYPE bits of the
// product, which are what the unit returns whatever the operands' sign (the
// two's complement of the low bits is the same). The operands are joined and
// taken when the unit is idle and no product is waiting; the product is held
// until taken; ceil(DATA_TYPE / STEP) + 1 cycles a multiply. STEP multiplier
// bits a cycle cost STEP rows of adders. This is the same unit the VHDL
// generator writes for IMPL = "sequential"
// (tools/unit-generators/vhdl/generators/handshake/muli.py).
module muli_sequential #(
  parameter DATA_TYPE = 32,
  parameter STEP = 1
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

  localparam ITERATIONS = (DATA_TYPE + STEP - 1) / STEP;
  localparam PADDED = ITERATIONS * STEP;
  localparam COUNT_WIDTH = $clog2(ITERATIONS + 1);

  wire join_valid;
  wire idle;
  wire accept;

  reg busy = 1'b0;
  reg done = 1'b0;
  reg [COUNT_WIDTH - 1 : 0] count = 0;
  reg [DATA_TYPE - 1 : 0] a_reg = 0;
  reg [PADDED - 1 : 0] b_reg = 0;
  reg [DATA_TYPE - 1 : 0] acc = 0;

  wire [DATA_TYPE + STEP - 1 : 0] partial;

  // the operands are taken together, when nothing is running and no
  // product is waiting (or it goes this cycle)
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

  // the multiplicand, already shifted, times the next STEP multiplier bits
  assign partial = a_reg * b_reg[STEP - 1 : 0];

  always @(posedge clk) begin
    if (rst) begin
      busy  <= 1'b0;
      done  <= 1'b0;
      count <= 0;
    end else begin
      if (done && result_ready)
        done <= 1'b0;
      if (accept) begin
        a_reg <= lhs;
        b_reg <= rhs;
        acc   <= 0;
        count <= 0;
        busy  <= 1'b1;
      end else if (busy) begin
        acc   <= acc + partial[DATA_TYPE - 1 : 0];
        a_reg <= a_reg << STEP;
        b_reg <= b_reg >> STEP;
        if (count == ITERATIONS - 1) begin
          busy <= 1'b0;
          done <= 1'b1;
        end
        count <= count + 1;
      end
    end
  end

  assign result = acc;
  assign result_valid = done;

endmodule
