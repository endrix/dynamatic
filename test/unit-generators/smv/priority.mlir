// RUN: %export-smv
// RUN: FileCheck %s -input-file %t/handshake_priority_0.smv
// RUN: FileCheck %s -input-file %t/handshake_priority_1.smv --check-prefix=BIT

// export-rtl instantiates the priority with the ports in its order (each
// input's data then its valid, then the output's ready) and the generator
// answers with that interface: a non-zero `hi` decides alone, the cycle it
// arrives; each input is ready while it has not given this round's token.

// CHECK: MODULE handshake_priority_0(hi, hi_valid, lo, lo_valid, outs_ready)
// CHECK: held : unsigned word [3];
// CHECK: hi_now_nz := take_hi & (hi != 0ud3_0);
// CHECK: valid_i := !emitted & hi_here & (hi_nz | lo_here);
// CHECK: hi_ready := !seen_hi;
// CHECK: lo_ready := !seen_lo;

// One bit: the payload is a boolean, compared as one.
// BIT: held : boolean;
// BIT: hi_now_nz := take_hi & (hi);
module {
  hw.module @test(in %a : !handshake.channel<i3>, in %b : !handshake.channel<i3>, in %c : !handshake.channel<i1>, in %d : !handshake.channel<i1>, in %clk : i1, in %rst : i1, out out0 : !handshake.channel<i3>, out out1 : !handshake.channel<i1>) {
    %p0.outs = hw.instance "p0" @handshake_priority_0(hi: %a: !handshake.channel<i3>, lo: %b: !handshake.channel<i3>, clk: %clk: i1, rst: %rst: i1) -> (outs: !handshake.channel<i3>)
    %p1.outs = hw.instance "p1" @handshake_priority_1(hi: %c: !handshake.channel<i1>, lo: %d: !handshake.channel<i1>, clk: %clk: i1, rst: %rst: i1) -> (outs: !handshake.channel<i1>)
    hw.output %p0.outs, %p1.outs : !handshake.channel<i3>, !handshake.channel<i1>
  }
  hw.module.extern @handshake_priority_0(in %hi : !handshake.channel<i3>, in %lo : !handshake.channel<i3>, in %clk : i1, in %rst : i1, out outs : !handshake.channel<i3>) attributes {hw.name = "handshake.priority", hw.parameters = {DATA_TYPE = !handshake.channel<i3>}}
  hw.module.extern @handshake_priority_1(in %hi : !handshake.channel<i1>, in %lo : !handshake.channel<i1>, in %clk : i1, in %rst : i1, out outs : !handshake.channel<i1>) attributes {hw.name = "handshake.priority", hw.parameters = {DATA_TYPE = !handshake.channel<i1>}}
}
