// REQUIRES: ghdl
// RUN: rm -rf %t && mkdir -p %t && cd %t && for u in blocker bare mergectl join queue mux muxctl cmerge cmergectl; do \
// RUN:   sed -n "/^\/\/ BEGIN $u\$/,/^\/\/ END\$/p" %s > $u.mlir && dynamatic-opt $u.mlir --lower-handshake-to-hw > $u.hw || exit 1; \
// RUN:   export-rtl $u.hw $u %dynamatic_src_root/data/rtl-config-vhdl.json --dynamatic-path %dynamatic_src_root --hdl vhdl || exit 1; \
// RUN:   echo "design $u"; ls $u; (cd $u && ghdl -i --std=08 *.vhd && ghdl -m --std=08 alone) || exit 1; done | FileCheck %s

// A generic blocker, a merge without its slot, a join, a queue, a mux and a
// control merge each bring what they are built from, in a design that has no
// other user of it.

// CHECK:      design blocker
// CHECK:      handshake_blocker.vhd
// CHECK-NEXT: join.vhd
// CHECK-NEXT: logic.vhd
// CHECK-NEXT: types.vhd
// CHECK:      design bare
// CHECK:      handshake_merge.vhd
// CHECK-NEXT: tehb.vhd
// CHECK-NEXT: tehb_dataless.vhd
// CHECK-NEXT: types.vhd
// CHECK:      design mergectl
// CHECK:      handshake_merge_dataless.vhd
// CHECK-NEXT: tehb_dataless.vhd
// CHECK:      design join
// CHECK:      handshake_join.vhd
// CHECK-NEXT: join.vhd
// CHECK-NEXT: logic.vhd
// CHECK:      design queue
// CHECK:      handshake_queue.vhd
// CHECK:      design mux
// CHECK:      handshake_mux.vhd
// CHECK-NEXT: tehb.vhd
// CHECK-NEXT: tehb_dataless.vhd
// CHECK-NEXT: types.vhd
// CHECK:      design muxctl
// CHECK:      handshake_mux_dataless.vhd
// CHECK-NEXT: tehb_dataless.vhd
// CHECK:      design cmerge
// CHECK:      eager_fork_register_block.vhd
// CHECK-NEXT: fork_dataless.vhd
// CHECK-NEXT: handshake_control_merge.vhd
// CHECK-NEXT: handshake_merge.vhd
// CHECK-NEXT: logic.vhd
// CHECK-NEXT: tehb.vhd
// CHECK-NEXT: tehb_dataless.vhd
// CHECK-NEXT: types.vhd
// CHECK:      design cmergectl
// CHECK:      eager_fork_register_block.vhd
// CHECK-NEXT: fork_dataless.vhd
// CHECK-NEXT: handshake_control_merge_dataless.vhd
// CHECK-NEXT: handshake_merge_dataless.vhd
// CHECK-NEXT: logic.vhd
// CHECK-NEXT: tehb.vhd
// CHECK-NEXT: tehb_dataless.vhd

// BEGIN blocker
handshake.func @alone(%a: !handshake.channel<i12>, %b: !handshake.channel<i12>) -> !handshake.channel<i12> attributes {argNames = ["a", "b"], resNames = ["o"]} {
  %k = blocker %a, %b {handshake.name = "blocker0"} : <i12>
  end {handshake.name = "end0"} %k : <i12>
}
// END
// BEGIN bare
handshake.func @alone(%a: !handshake.channel<i12>, %b: !handshake.channel<i12>) -> !handshake.channel<i12> attributes {argNames = ["a", "b"], resNames = ["o"]} {
  %m = merge %a, %b {handshake.name = "merge0", hw.parameters = {TEHB = 0 : i64}} : <i12>
  end {handshake.name = "end0"} %m : <i12>
}
// END
// BEGIN mergectl
handshake.func @alone(%x: !handshake.control<>, %y: !handshake.control<>) -> !handshake.control<> attributes {argNames = ["x", "y"], resNames = ["o"]} {
  %m = merge %x, %y {handshake.name = "merge0"} : <>
  end {handshake.name = "end0"} %m : <>
}
// END
// BEGIN join
handshake.func @alone(%x: !handshake.control<>, %y: !handshake.control<>) -> !handshake.control<> attributes {argNames = ["x", "y"], resNames = ["o"]} {
  %j = join %x, %y {handshake.name = "join0"} : <>
  end {handshake.name = "end0"} %j : <>
}
// END
// BEGIN queue
handshake.func @alone(%a: !handshake.channel<i12, [space: i2 (U)]>) -> !handshake.channel<i12, [size: i2]> attributes {argNames = ["a"], resNames = ["o"]} {
  %q = handshake.queue %a {handshake.name = "queue0", numSlots = 2 : i64} : !handshake.channel<i12, [space: i2 (U)]> to !handshake.channel<i12, [size: i2]>
  end {handshake.name = "end0"} %q : <i12, [size: i2]>
}
// END
// BEGIN mux
handshake.func @alone(%s: !handshake.channel<i1>, %a: !handshake.channel<i12>, %b: !handshake.channel<i12>) -> !handshake.channel<i12> attributes {argNames = ["s", "a", "b"], resNames = ["o"]} {
  %m = mux %s [%a, %b] {handshake.name = "mux0"} : <i1>, [<i12>, <i12>] to <i12>
  end {handshake.name = "end0"} %m : <i12>
}
// END
// BEGIN muxctl
handshake.func @alone(%s: !handshake.channel<i1>, %x: !handshake.control<>, %y: !handshake.control<>) -> !handshake.control<> attributes {argNames = ["s", "x", "y"], resNames = ["o"]} {
  %m = mux %s [%x, %y] {handshake.name = "mux0"} : <i1>, [<>, <>] to <>
  end {handshake.name = "end0"} %m : <>
}
// END
// BEGIN cmerge
handshake.func @alone(%a: !handshake.channel<i12>, %b: !handshake.channel<i12>) -> (!handshake.channel<i12>, !handshake.channel<i1>) attributes {argNames = ["a", "b"], resNames = ["o", "i"]} {
  %m, %i = control_merge [%a, %b] {handshake.name = "cmerge0"} : [<i12>, <i12>] to <i12>, <i1>
  end {handshake.name = "end0"} %m, %i : <i12>, <i1>
}
// END
// BEGIN cmergectl
handshake.func @alone(%x: !handshake.control<>, %y: !handshake.control<>) -> (!handshake.control<>, !handshake.channel<i1>) attributes {argNames = ["x", "y"], resNames = ["o", "i"]} {
  %m, %i = control_merge [%x, %y] {handshake.name = "cmerge0"} : [<>, <>] to <>, <i1>
  end {handshake.name = "end0"} %m, %i : <>, <i1>
}
// END
