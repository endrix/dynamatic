// RUN: %export-vhdl
// RUN: FileCheck %s -input-file %t/handshake_muli_0.vhd --check-prefix=SEQ
// RUN: FileCheck %s -input-file %t/handshake_muli_1.vhd --check-prefix=PIPE

// The two multipliers. IMPL=sequential adds STEP multiplier bits a cycle
// on one register set, the product held until taken; IMPL=pipelined is the
// one-cycle product behind the unit's latency in registers.

// SEQ: entity handshake_muli_0_join is
// SEQ: entity handshake_muli_0 is
// SEQ: signal busy, done : std_logic;
// SEQ: partial <= a_reg * b_reg(4 - 1 downto 0);
// SEQ: a_reg <= shift_left(a_reg, 4);
// SEQ: result_valid <= done;

// PIPE: entity handshake_muli_1_valid_buffer is
// PIPE: entity handshake_muli_1 is
// PIPE: mul <= std_logic_vector(resize(unsigned(std_logic_vector(signed(a_reg) * signed(b_reg))), 32));
module {
  hw.module @test(in %a : !handshake.channel<i32>, in %b : !handshake.channel<i32>, in %c : !handshake.channel<i32>, in %d : !handshake.channel<i32>, in %clk : i1, in %rst : i1, out out0 : !handshake.channel<i32>, out out1 : !handshake.channel<i32>) {
    %mul0.result = hw.instance "mul0" @handshake_muli_0(lhs: %a: !handshake.channel<i32>, rhs: %b: !handshake.channel<i32>, clk: %clk: i1, rst: %rst: i1) -> (result: !handshake.channel<i32>)
    %mul1.result = hw.instance "mul1" @handshake_muli_1(lhs: %c: !handshake.channel<i32>, rhs: %d: !handshake.channel<i32>, clk: %clk: i1, rst: %rst: i1) -> (result: !handshake.channel<i32>)
    hw.output %mul0.result, %mul1.result : !handshake.channel<i32>, !handshake.channel<i32>
  }
  hw.module.extern @handshake_muli_0(in %lhs : !handshake.channel<i32>, in %rhs : !handshake.channel<i32>, in %clk : i1, in %rst : i1, out result : !handshake.channel<i32>) attributes {hw.name = "handshake.muli", hw.parameters = {DATA_TYPE = !handshake.channel<i32>, IMPL = "sequential", LATENCY = 9 : ui32, STEP = 4 : ui32}}
  hw.module.extern @handshake_muli_1(in %lhs : !handshake.channel<i32>, in %rhs : !handshake.channel<i32>, in %clk : i1, in %rst : i1, out result : !handshake.channel<i32>) attributes {hw.name = "handshake.muli", hw.parameters = {DATA_TYPE = !handshake.channel<i32>, IMPL = "pipelined", LATENCY = 4 : ui32, STEP = 1 : ui32}}
}
