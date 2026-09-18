// RUN: %export-smv
// RUN: FileCheck %s -input-file %t/handshake_muli_0.smv --check-prefix=SEQ
// RUN: FileCheck %s -input-file %t/handshake_muli_1.smv --check-prefix=PIPE

// The SMV model follows the op's own latency, and IMPL=sequential gets the
// model of a unit that runs one multiply at a time: the operands are taken
// when nothing is running and no product is waiting, the product comes
// LATENCY cycles later and is held until taken. The pipelined model takes a
// pair every cycle, which a sequential unit does not.

// SEQ: latency=9
// SEQ: impl="sequential"
// SEQ: VAR busy : boolean;
// SEQ: VAR step : 0..7;
// SEQ: DEFINE idle := !busy & (!done | outs_ready);
// SEQ: DEFINE outs_valid := done;

// PIPE: latency=4
// PIPE: impl="pipelined"
// PIPE: VAR inner_delay_buffer :
module {
  hw.module @test(in %a : !handshake.channel<i32>, in %b : !handshake.channel<i32>, in %c : !handshake.channel<i32>, in %d : !handshake.channel<i32>, in %clk : i1, in %rst : i1, out out0 : !handshake.channel<i32>, out out1 : !handshake.channel<i32>) {
    %mul0.result = hw.instance "mul0" @handshake_muli_0(lhs: %a: !handshake.channel<i32>, rhs: %b: !handshake.channel<i32>, clk: %clk: i1, rst: %rst: i1) -> (result: !handshake.channel<i32>)
    %mul1.result = hw.instance "mul1" @handshake_muli_1(lhs: %c: !handshake.channel<i32>, rhs: %d: !handshake.channel<i32>, clk: %clk: i1, rst: %rst: i1) -> (result: !handshake.channel<i32>)
    hw.output %mul0.result, %mul1.result : !handshake.channel<i32>, !handshake.channel<i32>
  }
  hw.module.extern @handshake_muli_0(in %lhs : !handshake.channel<i32>, in %rhs : !handshake.channel<i32>, in %clk : i1, in %rst : i1, out result : !handshake.channel<i32>) attributes {hw.name = "handshake.muli", hw.parameters = {DATA_TYPE = !handshake.channel<i32>, IMPL = "sequential", LATENCY = 9 : ui32, STEP = 4 : ui32}}
  hw.module.extern @handshake_muli_1(in %lhs : !handshake.channel<i32>, in %rhs : !handshake.channel<i32>, in %clk : i1, in %rst : i1, out result : !handshake.channel<i32>) attributes {hw.name = "handshake.muli", hw.parameters = {DATA_TYPE = !handshake.channel<i32>, IMPL = "pipelined", LATENCY = 4 : ui32, STEP = 1 : ui32}}
}
