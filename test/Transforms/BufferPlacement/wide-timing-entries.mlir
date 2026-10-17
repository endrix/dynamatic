// A unit wider than every width a model holds has no data delay: the lookup
// fails and the placer times the unit as no delay. The cell-library models
// are characterized up to 512 bits, so a 512-bit add on ASAP7 SLVT is timed
// by its 512-bit entry, 0.334 ns: at a 0.5 ns period one add fits and two in
// a row do not, and the placer cuts between them. Against a model that
// stops at 64 bits it would place nothing.
//
// REQUIRES: cbc
// RUN: dynamatic-opt %s --handshake-place-buffers="algorithm=fpga20 solver=cbc timeout=30 target-period=0.5 timing-models=%dynamatic_src_root/data/components-asap7.json spec-timing-models=%dynamatic_src_root/data/spec-timing.json" --remove-operation-names 2>/dev/null | FileCheck %s

// CHECK-LABEL: handshake.func @wide_adders
// CHECK:       addi
// CHECK-NEXT:  buffer
// CHECK-NEXT:  addi
// CHECK-NOT:   buffer
// CHECK:       end
handshake.func @wide_adders(%a: !handshake.channel<i512>, %b: !handshake.channel<i512>, %start: !handshake.control<>, ...) -> (!handshake.channel<i512>, !handshake.control<>) attributes {argNames = ["a", "b", "start"], resNames = ["out", "end"], handshake.frequencies = []} {
  %f:2 = fork [2] %b {handshake.bb = 0 : ui32} : <i512>
  %s0 = addi %a, %f#0 {handshake.bb = 0 : ui32} : <i512>
  %s1 = addi %s0, %f#1 {handshake.bb = 0 : ui32} : <i512>
  end %s1, %start : <i512>, <>
}
