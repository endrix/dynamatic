// RUN: dynamatic-opt %s --lower-handshake-to-hw | FileCheck %s

// A KILL DOMAIN WITH THREE COMMITS beside one with two, in one module
// (handshake.commit): the OR the lowering builds is as wide as the domain's
// commits, one kill_or extern a size. Domain 3 has a commit on each of three
// decisions (d0, d1, d2), domain 4 a commit on d0 and on d1, each in series
// after domain 3's. Domain 3's latch is reset by kill_domain3 = kill_or_3 of
// its three commits' kills, domain 4's by kill_domain4 = kill_or_2 of its
// two; each domain's stand-in takes all its domain's kills (stand-in externs
// of SIZE 3 and 2). Nothing in the lowering is specific to two commits.

// CHECK-LABEL: hw.module @three
// CHECK-DAG: hw.instance "buffer0" @{{.*}}(ins: %a3: {{.*}}, clk: %clk: i1, rst: %[[K3:kill_domain3.outs]]: i1)
// CHECK-DAG: hw.instance "buffer1" @{{.*}}(ins: %a4: {{.*}}, clk: %clk: i1, rst: %[[K4:kill_domain4.outs]]: i1)
// CHECK-DAG: %commit0.outs, %commit0.kill = hw.instance "commit0" @{{.*}}(ins: %d0: {{.*}}, clk: %clk: i1, rst: %rst: i1)
// CHECK-DAG: %commit1.outs, %commit1.kill = hw.instance "commit1" @{{.*}}(ins: %commit0.outs: {{.*}}, clk: %clk: i1, rst: %rst: i1)
// CHECK-DAG: %commit2.outs, %commit2.kill = hw.instance "commit2" @{{.*}}(ins: %d1: {{.*}}, clk: %clk: i1, rst: %rst: i1)
// CHECK-DAG: %commit3.outs, %commit3.kill = hw.instance "commit3" @{{.*}}(ins: %commit2.outs: {{.*}}, clk: %clk: i1, rst: %rst: i1)
// CHECK-DAG: %commit4.outs, %commit4.kill = hw.instance "commit4" @{{.*}}(ins: %d2: {{.*}}, clk: %clk: i1, rst: %rst: i1)
// CHECK-DAG: %[[K3]] = hw.instance "kill_domain3" @[[OR3:kill_or_3]](ins_0: %commit0.kill: i1, ins_1: %commit2.kill: i1, ins_2: %commit4.kill: i1) -> (outs: i1)
// CHECK-DAG: %[[K4]] = hw.instance "kill_domain4" @[[OR2:kill_or_2]](ins_0: %commit1.kill: i1, ins_1: %commit3.kill: i1) -> (outs: i1)
// CHECK-DAG: hw.instance "stand_in0" @[[SI3:.*]](ins: %buffer0.outs: {{.*}}, kill_0: %commit0.kill: i1, kill_1: %commit2.kill: i1, kill_2: %commit4.kill: i1, clk: %clk: i1, rst: %rst: i1)
// CHECK-DAG: hw.instance "stand_in1" @[[SI2:.*]](ins: %buffer1.outs: {{.*}}, kill_0: %commit1.kill: i1, kill_1: %commit3.kill: i1, clk: %clk: i1, rst: %rst: i1)
// CHECK-NOT: handshake.kill_domain
// CHECK-NOT: handshake.kill_source
// CHECK-DAG: hw.module.extern @[[SI3]](in %ins : {{.*}}, in %kill_0 : i1, in %kill_1 : i1, in %kill_2 : i1, in %clk : i1, in %rst : i1, {{.*}}) attributes {hw.name = "handshake.stand_in", hw.parameters = {DATA_TYPE = !handshake.channel<i1>, SIZE = 3 : ui32}}
// CHECK-DAG: hw.module.extern @[[SI2]](in %ins : {{.*}}, in %kill_0 : i1, in %kill_1 : i1, in %clk : i1, in %rst : i1, {{.*}}) attributes {hw.name = "handshake.stand_in", hw.parameters = {DATA_TYPE = !handshake.channel<i1>, SIZE = 2 : ui32}}
// CHECK-DAG: hw.module.extern @[[OR3]](in %ins_0 : i1, in %ins_1 : i1, in %ins_2 : i1, out outs : i1) attributes {hw.name = "kill_or", hw.parameters = {SIZE = 3 : ui32}}
// CHECK-DAG: hw.module.extern @[[OR2]](in %ins_0 : i1, in %ins_1 : i1, out outs : i1) attributes {hw.name = "kill_or", hw.parameters = {SIZE = 2 : ui32}}

handshake.func @three(%a3: !handshake.channel<i1>, %a4: !handshake.channel<i1>,
                      %d0: !handshake.channel<i3>, %d1: !handshake.channel<i3>,
                      %d2: !handshake.channel<i3>, %start: !handshake.control<>, ...)
    -> (!handshake.channel<i1>, !handshake.channel<i1>, !handshake.channel<i3>,
        !handshake.channel<i3>, !handshake.channel<i3>, !handshake.control<>)
    attributes {argNames = ["a3", "a4", "d0", "d1", "d2", "start"],
                resNames = ["f3", "f4", "o0", "o1", "o2", "end"]} {
  %l3 = buffer %a3, bufferType = ONE_SLOT_BREAK_R, numSlots = 1, dvLatency = 0 {handshake.kill_domain = 3 : ui32} : <i1>
  %l4 = buffer %a4, bufferType = ONE_SLOT_BREAK_R, numSlots = 1, dvLatency = 0 {handshake.kill_domain = 4 : ui32} : <i1>
  // d0 and d1 stop domains 3 and 4, d2 domain 3 only
  %x0, %k0 = commit %d0 {domain = 3 : ui32} : <i3>
  %y0, %j0 = commit %x0 {domain = 4 : ui32} : <i3>
  %x1, %k1 = commit %d1 {domain = 3 : ui32} : <i3>
  %y1, %j1 = commit %x1 {domain = 4 : ui32} : <i3>
  %x2, %k2 = commit %d2 {domain = 3 : ui32} : <i3>
  %f3 = stand_in %l3, %k0, %k1, %k2 : <i1>
  %f4 = stand_in %l4, %j0, %j1 : <i1>
  end %f3, %f4, %y0, %y1, %x2, %start : <i1>, <i1>, <i3>, <i3>, <i3>, <>
}
