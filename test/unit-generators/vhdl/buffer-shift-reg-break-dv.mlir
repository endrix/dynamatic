// RUN: %export-vhdl
// RUN: FileCheck %s -input-file %t/handshake_buffer_0.vhd --check-prefix=DATA
// RUN: FileCheck %s -input-file %t/handshake_buffer_1.vhd --check-prefix=EXTRA
// RUN: FileCheck %s -input-file %t/handshake_buffer_2.vhd --check-prefix=CTRLEXTRA

// SHIFT_REG_BREAK_DV with data. The data unit built its handshake from the
// dataless one without passing the slot count, so every buffer with data,
// and every dataless one with extra signals (which the signal manager
// concatenates into data), failed to generate with a TypeError.

// DATA: entity handshake_buffer_0_inner is
// DATA: type REG_VALID is array (0 to 3 - 1) of std_logic;
// DATA: entity handshake_buffer_0 is
// DATA: type REG_MEMORY is array (0 to 3 - 1) of std_logic_vector(32 - 1 downto 0);
// DATA: control : entity work.handshake_buffer_0_inner

// EXTRA: type REG_VALID is array (0 to 2 - 1) of std_logic;
// EXTRA: type REG_MEMORY is array (0 to 2 - 1) of std_logic_vector(33 - 1 downto 0);
// EXTRA: entity handshake_buffer_1 is

// CTRLEXTRA: type REG_VALID is array (0 to 2 - 1) of std_logic;
// CTRLEXTRA: type REG_MEMORY is array (0 to 2 - 1) of std_logic_vector(1 - 1 downto 0);
// CTRLEXTRA: entity handshake_buffer_2 is
module {
  hw.module @f(in %a : !handshake.channel<i32>, in %c : !handshake.channel<i32, [spec: i1]>, in %d : !handshake.control<[spec: i1]>, in %clk : i1, in %rst : i1, out out0 : !handshake.channel<i32>, out out1 : !handshake.channel<i32, [spec: i1]>, out out2 : !handshake.control<[spec: i1]>) {
    %buffer0.outs = hw.instance "buffer0" @handshake_buffer_0(ins: %a: !handshake.channel<i32>, clk: %clk: i1, rst: %rst: i1) -> (outs: !handshake.channel<i32>)
    %buffer1.outs = hw.instance "buffer1" @handshake_buffer_1(ins: %c: !handshake.channel<i32, [spec: i1]>, clk: %clk: i1, rst: %rst: i1) -> (outs: !handshake.channel<i32, [spec: i1]>)
    %buffer2.outs = hw.instance "buffer2" @handshake_buffer_2(ins: %d: !handshake.control<[spec: i1]>, clk: %clk: i1, rst: %rst: i1) -> (outs: !handshake.control<[spec: i1]>)
    hw.output %buffer0.outs, %buffer1.outs, %buffer2.outs : !handshake.channel<i32>, !handshake.channel<i32, [spec: i1]>, !handshake.control<[spec: i1]>
  }
  hw.module.extern @handshake_buffer_0(in %ins : !handshake.channel<i32>, in %clk : i1, in %rst : i1, out outs : !handshake.channel<i32>) attributes {hw.name = "handshake.buffer", hw.parameters = {BUFFER_TYPE = "SHIFT_REG_BREAK_DV", DATA_TYPE = !handshake.channel<i32>, DV_LATENCY = 3 : ui32, NUM_SLOTS = 3 : ui32}}
  hw.module.extern @handshake_buffer_1(in %ins : !handshake.channel<i32, [spec: i1]>, in %clk : i1, in %rst : i1, out outs : !handshake.channel<i32, [spec: i1]>) attributes {hw.name = "handshake.buffer", hw.parameters = {BUFFER_TYPE = "SHIFT_REG_BREAK_DV", DATA_TYPE = !handshake.channel<i32, [spec: i1]>, DV_LATENCY = 2 : ui32, NUM_SLOTS = 2 : ui32}}
  hw.module.extern @handshake_buffer_2(in %ins : !handshake.control<[spec: i1]>, in %clk : i1, in %rst : i1, out outs : !handshake.control<[spec: i1]>) attributes {hw.name = "handshake.buffer", hw.parameters = {BUFFER_TYPE = "SHIFT_REG_BREAK_DV", DATA_TYPE = !handshake.control<[spec: i1]>, DV_LATENCY = 2 : ui32, NUM_SLOTS = 2 : ui32}}
}
