// REQUIRES: ghdl
// RUN: rm -rf %t && mkdir -p %t
// RUN: dynamatic-opt %s --lower-handshake-to-hw > %t/genunits5.hw
// RUN: FileCheck %s --input-file=%t/genunits5.hw --check-prefix=HW
// RUN: export-rtl %t/genunits5.hw %t/vhdl %dynamatic_src_root/data/rtl-config-vhdl.json --dynamatic-path %dynamatic_src_root --hdl vhdl
// RUN: FileCheck %s --input-file=%t/vhdl/genunits5.vhd
// RUN: ls %t/vhdl | FileCheck %s --check-prefix=FILES
// RUN: cd %t/vhdl && ghdl -i --std=08 *.vhd && ghdl -m --std=08 genunits5

// The mux, the control merge, the bundle and the unbundle: generic entities
// (data/vhdl/handshake/generic). A mux and a control merge are one of two,
// with or without data; whether a mux keeps the slot behind its select
// (TEHB) is a generic. A bundle and an unbundle are pure wiring, one entity
// per port list: a control, a channel, and a channel that carries the
// queue's `space` (bundle) or `size` (unbundle). A unit on speculative
// channels, and a bundle or unbundle of a channel with any other extra
// signal, are generated.

// The conversion shows a bundle's and an unbundle's channel type, and the
// widths of a `size` and a `space` it carries.
// HW-DAG: hw.name = "handshake.unbundle", hw.parameters = {DATA_TYPE = !handshake.channel<i12, [size: i3]>, DATA_WIDTH = 12 : ui32, EXTRA_DOWN = "{\22size\22: 3}", EXTRA_UP = "{}", FORM = "channel", SIZE_WIDTH = 3 : ui32, SPACE_WIDTH = 0 : ui32}
// HW-DAG: hw.name = "handshake.bundle", hw.parameters = {DATA_TYPE = !handshake.channel<i12, [space: i3 (U)]>, DATA_WIDTH = 12 : ui32, EXTRA_DOWN = "{}", EXTRA_UP = "{\22space\22: 3}", FORM = "channel", SIZE_WIDTH = 0 : ui32, SPACE_WIDTH = 3 : ui32}
// HW-DAG: hw.name = "handshake.unbundle", hw.parameters = {DATA_TYPE = !handshake.control<>, DATA_WIDTH = 0 : ui32, EXTRA_DOWN = "{}", EXTRA_UP = "{}", FORM = "control", SIZE_WIDTH = 0 : ui32, SPACE_WIDTH = 0 : ui32}

// CHECK-DAG: mux0 : entity work.handshake_mux(arch) generic map(2, 12, 1, 1)
// CHECK-DAG: mux1 : entity work.handshake_mux(arch) generic map(3, 12, 2, 0)
// CHECK-DAG: mux2 : entity work.handshake_mux_dataless(arch) generic map(2, 1, 1)
// CHECK-DAG: mux3 : entity work.handshake_mux_dataless(arch) generic map(3, 2, 0)
// CHECK-DAG: mux4 : entity work.handshake_mux_{{[0-9]+}}(arch)
// CHECK-DAG: cmerge0 : entity work.handshake_control_merge_dataless(arch) generic map(2, 1)
// CHECK-DAG: cmerge1 : entity work.handshake_control_merge_dataless(arch) generic map(3, 2)
// CHECK-DAG: cmerge2 : entity work.handshake_control_merge(arch) generic map(2, 12, 1)
// CHECK-DAG: cmerge3 : entity work.handshake_control_merge_{{[0-9]+}}(arch)
// CHECK-DAG: unbundle0 : entity work.handshake_unbundle(arch) generic map(9)
// CHECK-DAG: bundle0 : entity work.handshake_bundle(arch) generic map(9)
// CHECK-DAG: unbundle1 : entity work.handshake_unbundle(arch) generic map(1)
// CHECK-DAG: bundle1 : entity work.handshake_bundle(arch) generic map(1)
// CHECK-DAG: unbundle2 : entity work.handshake_unbundle_size(arch) generic map(12, 3)
// CHECK-DAG: bundle2 : entity work.handshake_bundle_space(arch) generic map(12, 3)
// CHECK-DAG: unbundle3 : entity work.handshake_unbundle_control(arch)
// CHECK-DAG: bundle3 : entity work.handshake_bundle_control(arch)
// CHECK-DAG: unbundle4 : entity work.handshake_unbundle_size(arch) generic map(12, 1)
// CHECK-DAG: bundle4 : entity work.handshake_bundle_space(arch) generic map(12, 1)
// CHECK-DAG: unbundle5 : entity work.handshake_unbundle_{{[0-9]+}}(arch)
// CHECK-DAG: bundle5 : entity work.handshake_bundle_{{[0-9]+}}(arch)
// CHECK-DAG: unbundle6 : entity work.handshake_unbundle_{{[0-9]+}}(arch)

// A bare wire of one bit is a scalar, bound to element 0 of the entity's
// port.
// CHECK-DAG: data(0) => unbundle1_data
// CHECK-DAG: size(0) => unbundle4_size
// CHECK-DAG: space(0) => bundle4_space

// FILES:      handshake_bundle.vhd
// FILES-NEXT: handshake_bundle_{{[0-9]+}}.vhd
// FILES-NEXT: handshake_bundle_control.vhd
// FILES-NEXT: handshake_bundle_space.vhd
// FILES-NEXT: handshake_control_merge.vhd
// FILES-NEXT: handshake_control_merge_{{[0-9]+}}.vhd
// FILES-NEXT: handshake_control_merge_dataless.vhd
// FILES:      handshake_mux.vhd
// FILES-NEXT: handshake_mux_{{[0-9]+}}.vhd
// FILES-NEXT: handshake_mux_dataless.vhd
// FILES-NEXT: handshake_unbundle.vhd
// FILES-NEXT: handshake_unbundle_{{[0-9]+}}.vhd
// FILES-NEXT: handshake_unbundle_{{[0-9]+}}.vhd
// FILES-NEXT: handshake_unbundle_control.vhd
// FILES-NEXT: handshake_unbundle_size.vhd

handshake.func @genunits5(%a: !handshake.channel<i12>, %b: !handshake.channel<i12>, %sel: !handshake.channel<i1>, %sel2: !handshake.channel<i2>, %selc: !handshake.channel<i1>, %selc2: !handshake.channel<i2>, %x: !handshake.control<>, %y: !handshake.control<>, %z: !handshake.control<>, %s: !handshake.channel<i12, [spec: i1]>, %t: !handshake.channel<i12, [spec: i1]>, %ss: !handshake.channel<i1, [spec: i1]>, %r: !handshake.channel<i9>, %bit: !handshake.channel<i1>, %q: !handshake.channel<i12, [size: i3]>, %q1: !handshake.channel<i12, [size: i1]>, %qs: !handshake.channel<i12, [size: i2, spec: i1]>, %ctl: !handshake.control<>, %start: !handshake.control<>) -> (!handshake.channel<i12>, !handshake.control<>, !handshake.channel<i12, [spec: i1]>, !handshake.channel<i12>, !handshake.channel<i1>, !handshake.channel<i12, [spec: i1]>, !handshake.channel<i1, [spec: i1]>, !handshake.channel<i9>, !handshake.channel<i1>, !handshake.channel<i12, [space: i3 (U)]>, !handshake.channel<i12, [space: i1 (U)]>, !handshake.control<>, !handshake.channel<i12, [spec: i1]>, !handshake.control<>, !handshake.control<>) attributes {argNames = ["a", "b", "sel", "sel2", "selc", "selc2", "x", "y", "z", "s", "t", "ss", "r", "bit", "q", "q1", "qs", "ctl", "start"], resNames = ["om", "oj", "oms", "ocd", "oci", "ocs", "ocsi", "ob", "obit", "oq", "oq1", "octl", "osp", "oqs", "end"]} {
  %a0, %a1, %a2 = fork [3] %a {handshake.name = "fork0"} : <i12>
  %b0, %b1, %b2 = fork [3] %b {handshake.name = "fork1"} : <i12>
  %m0 = mux %sel [%a0, %b0] {handshake.name = "mux0"} : <i1>, [<i12>, <i12>] to <i12>
  %m1 = mux %sel2 [%m0, %a1, %b1] {handshake.name = "mux1", hw.parameters = {TEHB = 0 : i64}} : <i2>, [<i12>, <i12>, <i12>] to <i12>
  %x0, %x1, %x2, %x3 = fork [4] %x {handshake.name = "fork2"} : <>
  %y0, %y1, %y2 = fork [3] %y {handshake.name = "fork3"} : <>
  %z0, %z1 = fork [2] %z {handshake.name = "fork4"} : <>
  %m2 = mux %selc [%x0, %y0] {handshake.name = "mux2"} : <i1>, [<>, <>] to <>
  %m3 = mux %selc2 [%m2, %x1, %y1] {handshake.name = "mux3", hw.parameters = {TEHB = 0 : i64}} : <i2>, [<>, <>, <>] to <>
  %s0, %s1, %s2 = fork [3] %s {handshake.name = "fork5"} : <i12, [spec: i1]>
  %t0, %t1 = fork [2] %t {handshake.name = "fork6"} : <i12, [spec: i1]>
  %m4 = mux %ss [%s0, %t0] {handshake.name = "mux4"} : <i1, [spec: i1]>, [<i12, [spec: i1]>, <i12, [spec: i1]>] to <i12, [spec: i1]>
  %cm0, %ci0 = control_merge [%x2, %y2] {handshake.name = "cmerge0"} : [<>, <>] to <>, <i1>
  sink %ci0 {handshake.name = "sink0"} : <i1>
  %cm1, %ci1 = control_merge [%cm0, %x3, %z0] {handshake.name = "cmerge1"} : [<>, <>, <>] to <>, <i2>
  sink %ci1 {handshake.name = "sink1"} : <i2>
  %cm2, %ci2 = control_merge [%a2, %b2] {handshake.name = "cmerge2"} : [<i12>, <i12>] to <i12>, <i1>
  %cm3, %ci3 = control_merge [%s1, %t1] {handshake.name = "cmerge3"} : [<i12, [spec: i1]>, <i12, [spec: i1]>] to <i12, [spec: i1]>, <i1, [spec: i1]>
  %c0, %d0 = unbundle %r {handshake.name = "unbundle0"} : <i9> to _
  %o0 = bundle %c0, %d0 {handshake.name = "bundle0"} : _ to <i9>
  %c1, %d1 = unbundle %bit {handshake.name = "unbundle1"} : <i1> to _
  %o1 = bundle %c1, %d1 {handshake.name = "bundle1"} : _ to <i1>
  %c2, %d2, %size2 = unbundle %q {handshake.name = "unbundle2"} : <i12, [size: i3]> to _
  %o2, %space2 = bundle %c2, %d2 {handshake.name = "bundle2"} : _ to <i12, [space: i3 (U)]>
  %valid = unbundle %ctl [%ready] {handshake.name = "unbundle3"} : <> to _
  %o3, %ready = bundle %valid {handshake.name = "bundle3"} : _ to <>
  %c4, %d4, %size4 = unbundle %q1 {handshake.name = "unbundle4"} : <i12, [size: i1]> to _
  %o4, %space4 = bundle %c4, %d4 {handshake.name = "bundle4"} : _ to <i12, [space: i1 (U)]>
  %c5, %d5, %spec5 = unbundle %s2 {handshake.name = "unbundle5"} : <i12, [spec: i1]> to _
  %o5 = bundle %c5, %d5, %spec5 {handshake.name = "bundle5"} : _ to <i12, [spec: i1]>
  %c6, %d6, %size6, %spec6 = unbundle %qs {handshake.name = "unbundle6"} : <i12, [size: i2, spec: i1]> to _
  %j = join %m3, %cm1, %z1 {handshake.name = "join0"} : <>
  end {handshake.name = "end0"} %m1, %j, %m4, %cm2, %ci2, %cm3, %ci3, %o0, %o1, %o2, %o4, %o3, %o5, %c6, %start : <i12>, <>, <i12, [spec: i1]>, <i12>, <i1>, <i12, [spec: i1]>, <i1, [spec: i1]>, <i9>, <i1>, <i12, [space: i3 (U)]>, <i12, [space: i1 (U)]>, <>, <i12, [spec: i1]>, <>, <>
}
