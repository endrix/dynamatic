// RUN: dynamatic-opt %s --handshake-set-unit-impl-attr="timing-models=%dynamatic_src_root/data/components.json" 2>&1 | FileCheck %s

// Without impl= the pass gives a float unit the portable FloPoCo cores. The
// default used to be "VIVADO", which the case-sensitive enum does not
// accept, so the pass failed ("Invalid FPU implementation: 'VIVADO'") on
// any function unless the caller named an implementation.

// CHECK-LABEL: handshake.func @f(
// CHECK: addf {{.*}}fpu_impl = #handshake<fpu_impl flopoco>
handshake.func @f(%a: !handshake.channel<f32>, %b: !handshake.channel<f32>, %start: !handshake.control<>) -> !handshake.channel<f32> {
  %r = addf %a, %b : <f32>
  end %r : <f32>
}
