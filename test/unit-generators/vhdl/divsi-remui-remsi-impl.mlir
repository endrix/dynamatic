// RUN: %export-vhdl
// RUN: FileCheck %s -input-file %t/handshake_divsi_0.vhd --check-prefix=DIVSI-SEQ --implicit-check-not=vitis_hls_wrapper
// RUN: FileCheck %s -input-file %t/handshake_divsi_1.vhd --check-prefix=DIVSI-PIPE
// RUN: FileCheck %s -input-file %t/handshake_remui_0.vhd --check-prefix=REMUI-SEQ --implicit-check-not=vitis_hls_wrapper --implicit-check-not=lhs_mag
// RUN: FileCheck %s -input-file %t/handshake_remsi_0.vhd --check-prefix=REMSI-SEQ --implicit-check-not=vitis_hls_wrapper
// RUN: FileCheck %s -input-file %t/handshake_remsi_1.vhd --check-prefix=REMSI-PIPE

// The sequential signed division and the two remainders. One register set
// stepped BITWIDTH times, the quotient register leaving a division and the
// remainder register leaving a remainder; a signed unit divides the
// magnitudes and negates the result, the quotient when the operands' signs
// differ and the remainder when the dividend is negative. The pipelined
// units are the Vitis cores behind a valid buffer of the unit's latency.

// DIVSI-SEQ: entity handshake_divsi_0_join is
// DIVSI-SEQ: entity handshake_divsi_0 is
// DIVSI-SEQ: signal busy, done : std_logic;
// DIVSI-SEQ: signal lhs_mag, rhs_mag : unsigned(32 - 1 downto 0);
// DIVSI-SEQ: lhs_mag <= (not unsigned(lhs)) + 1 when lhs(32 - 1) = '1' else unsigned(lhs);
// DIVSI-SEQ: cal  <= ('0' & comb) - ('0' & divisor);
// DIVSI-SEQ: negate   <= lhs(32 - 1) xor rhs(32 - 1);
// DIVSI-SEQ: result       <= std_logic_vector((not dividend) + 1) when negate = '1'
// DIVSI-SEQ: result_valid <= done;

// DIVSI-PIPE: entity handshake_divsi_1_valid_buffer is
// DIVSI-PIPE: divsi_vitis_hls_wrapper_U1 : entity work.divsi_vitis_hls_wrapper

// REMUI-SEQ: entity handshake_remui_0 is
// REMUI-SEQ: cal  <= ('0' & comb) - ('0' & divisor);
// REMUI-SEQ: dividend <= unsigned(lhs);
// REMUI-SEQ: result       <= std_logic_vector(remd);

// REMSI-SEQ: entity handshake_remsi_0 is
// REMSI-SEQ: signal lhs_mag, rhs_mag : unsigned(32 - 1 downto 0);
// REMSI-SEQ: negate   <= lhs(32 - 1);
// REMSI-SEQ: result       <= std_logic_vector((not remd) + 1) when negate = '1'

// REMSI-PIPE: entity handshake_remsi_1_valid_buffer is
// REMSI-PIPE: remsi_vitis_hls_wrapper_U1 : entity work.remsi_vitis_hls_wrapper
module {
  hw.module @test(in %a : !handshake.channel<i32>, in %b : !handshake.channel<i32>, in %clk : i1, in %rst : i1, out out0 : !handshake.channel<i32>, out out1 : !handshake.channel<i32>, out out2 : !handshake.channel<i32>, out out3 : !handshake.channel<i32>, out out4 : !handshake.channel<i32>) {
    %div0.result = hw.instance "div0" @handshake_divsi_0(lhs: %a: !handshake.channel<i32>, rhs: %b: !handshake.channel<i32>, clk: %clk: i1, rst: %rst: i1) -> (result: !handshake.channel<i32>)
    %div1.result = hw.instance "div1" @handshake_divsi_1(lhs: %a: !handshake.channel<i32>, rhs: %b: !handshake.channel<i32>, clk: %clk: i1, rst: %rst: i1) -> (result: !handshake.channel<i32>)
    %rem0.result = hw.instance "rem0" @handshake_remui_0(lhs: %a: !handshake.channel<i32>, rhs: %b: !handshake.channel<i32>, clk: %clk: i1, rst: %rst: i1) -> (result: !handshake.channel<i32>)
    %rem1.result = hw.instance "rem1" @handshake_remsi_0(lhs: %a: !handshake.channel<i32>, rhs: %b: !handshake.channel<i32>, clk: %clk: i1, rst: %rst: i1) -> (result: !handshake.channel<i32>)
    %rem2.result = hw.instance "rem2" @handshake_remsi_1(lhs: %a: !handshake.channel<i32>, rhs: %b: !handshake.channel<i32>, clk: %clk: i1, rst: %rst: i1) -> (result: !handshake.channel<i32>)
    hw.output %div0.result, %div1.result, %rem0.result, %rem1.result, %rem2.result : !handshake.channel<i32>, !handshake.channel<i32>, !handshake.channel<i32>, !handshake.channel<i32>, !handshake.channel<i32>
  }
  hw.module.extern @handshake_divsi_0(in %lhs : !handshake.channel<i32>, in %rhs : !handshake.channel<i32>, in %clk : i1, in %rst : i1, out result : !handshake.channel<i32>) attributes {hw.name = "handshake.divsi", hw.parameters = {DATA_TYPE = !handshake.channel<i32>, IMPL = "sequential", LATENCY = 33 : ui32}}
  hw.module.extern @handshake_divsi_1(in %lhs : !handshake.channel<i32>, in %rhs : !handshake.channel<i32>, in %clk : i1, in %rst : i1, out result : !handshake.channel<i32>) attributes {hw.name = "handshake.divsi", hw.parameters = {DATA_TYPE = !handshake.channel<i32>, IMPL = "pipelined", LATENCY = 35 : ui32}}
  hw.module.extern @handshake_remui_0(in %lhs : !handshake.channel<i32>, in %rhs : !handshake.channel<i32>, in %clk : i1, in %rst : i1, out result : !handshake.channel<i32>) attributes {hw.name = "handshake.remui", hw.parameters = {DATA_TYPE = !handshake.channel<i32>, IMPL = "sequential", LATENCY = 33 : ui32}}
  hw.module.extern @handshake_remsi_0(in %lhs : !handshake.channel<i32>, in %rhs : !handshake.channel<i32>, in %clk : i1, in %rst : i1, out result : !handshake.channel<i32>) attributes {hw.name = "handshake.remsi", hw.parameters = {DATA_TYPE = !handshake.channel<i32>, IMPL = "sequential", LATENCY = 33 : ui32}}
  hw.module.extern @handshake_remsi_1(in %lhs : !handshake.channel<i32>, in %rhs : !handshake.channel<i32>, in %clk : i1, in %rst : i1, out result : !handshake.channel<i32>) attributes {hw.name = "handshake.remsi", hw.parameters = {DATA_TYPE = !handshake.channel<i32>, IMPL = "pipelined", LATENCY = 35 : ui32}}
}
