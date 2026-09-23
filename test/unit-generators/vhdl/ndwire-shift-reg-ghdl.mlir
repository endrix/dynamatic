// REQUIRES: ghdl
// RUN: %export-vhdl
// RUN: python3 %dynamatic_src_root/tools/unit-generators/vhdl/vhdl-unit-generator.py -n ndwire_data -o %t/ndwire_data.vhd -t ndwire -p bitwidth=32 'extra_signals={}'
// RUN: python3 %dynamatic_src_root/tools/unit-generators/vhdl/vhdl-unit-generator.py -n ndwire_ctrl -o %t/ndwire_ctrl.vhd -t ndwire -p bitwidth=0 'extra_signals={}'
// RUN: python3 %dynamatic_src_root/tools/unit-generators/vhdl/vhdl-unit-generator.py -n ndwire_extra -o %t/ndwire_extra.vhd -t ndwire -p bitwidth=32 "extra_signals={'spec':1}"
// RUN: cd %t && ghdl -i --std=08 %dynamatic_src_root/data/vhdl/support/types.vhd *.vhd
// RUN: cd %t && ghdl -m --std=08 f
// RUN: cd %t && ghdl -m --std=08 ndwire_data
// RUN: cd %t && ghdl -m --std=08 ndwire_ctrl
// RUN: cd %t && ghdl -m --std=08 ndwire_extra

// The units the two generator fixes write are VHDL a tool reads: the
// SHIFT_REG_BREAK_DV buffers with data and with extra signals, under the
// exported top, and the non-deterministic wire with data, without and with
// extra signals, analysed and elaborated by GHDL. Before the fixes the
// buffers failed to generate and every ndwire failed to analyse.
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
