// RUN: dynamatic-opt %s --handshake-set-unit-impl-attr="impl=vivado timing-models=%dynamatic_src_root/data/components.json" 2>&1 | FileCheck %s

// A unit wider than the widest bitwidth the timing model characterises (the
// multiplier's entries stop at 64) still has a latency: it is the unit's
// stage count, the number the generator is handed as LATENCY, and it does not
// change with the width. The lookup takes the widest entry and says so; the
// delay of such a unit stays unknown.

// CHECK: remark: TimingDatabase::getLatency: bitwidth 72 is above the widest characterised (64); the latency is the widest entry's
// CHECK-LABEL: handshake.func @wide(
// CHECK: muli {{.*}} {latency = 4 : i64} : <i72>
// CHECK: muli {{.*}} {latency = 4 : i64} : <i32>
handshake.func @wide(%a: !handshake.channel<i72>, %b: !handshake.channel<i72>, %c: !handshake.channel<i32>, %d: !handshake.channel<i32>, %start: !handshake.control<>) -> (!handshake.channel<i72>, !handshake.channel<i32>) {
  %p = muli %a, %b : <i72>
  %q = muli %c, %d : <i32>
  end %p, %q : <i72>, <i32>
}
