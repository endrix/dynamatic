// RUN: dynamatic-opt %s --lower-handshake-to-hw | FileCheck %s

// A unit that takes any number of inputs, or gives any number of outputs,
// with a single one. Its RTL declares the inputs (a fork's outputs) as an
// array, and the netlist printers tell an array's element from a plain port
// by the `_<index>` suffix of its name. The operations named a lone one
// without a suffix (`ins`, `outs`), which read as a plain port: the design
// did not elaborate in VHDL, and the SMV netlist named signals the unit's
// module does not define. They name it as the array's element 0, with or
// without extra signals on the channel. A port that is not one of an array
// keeps its name: a fork's input, a control merge's outputs, a buffer's;
// and a merge of two has `ins_0` and `ins_1` as before.

// CHECK-LABEL: hw.module @one(
// CHECK-DAG: hw.instance "merge0" @{{.*}}(ins_0: %a: {{.*}}) -> (outs:
// CHECK-DAG: hw.instance "mux0" @{{.*}}(index: %sel: {{.*}}, ins_0: %b: {{.*}}) -> (outs:
// CHECK-DAG: hw.instance "cmerge0" @{{.*}}(ins_0: %c: {{.*}}) -> (outs: {{.*}}, index:
// CHECK-DAG: hw.instance "blocker0" @{{.*}}(ins_0: %d: {{.*}}) -> (outs:
// CHECK-DAG: hw.instance "fork0" @{{.*}}(ins: %e: {{.*}}) -> (outs_0:
// CHECK-DAG: hw.instance "lfork0" @{{.*}}(ins: %f: {{.*}}) -> (outs_0:
// CHECK-DAG: hw.instance "first0" @{{.*}}(ins_0: %i: {{.*}}) -> (outs:
// CHECK-DAG: hw.instance "merge3" @{{.*}}(ins_0: %s: {{.*}}) -> (outs:
// CHECK-DAG: hw.instance "fork2" @{{.*}}(ins: %t: {{.*}}) -> (outs_0:
// CHECK-DAG: hw.instance "merge1" @{{.*}}(ins_0: %x: {{.*}}) -> (outs:
// CHECK-DAG: hw.instance "join0" @{{.*}}(ins_0: %y: {{.*}}) -> (outs:
// CHECK-DAG: hw.instance "fork1" @{{.*}}(ins: %z: {{.*}}) -> (outs_0:
// CHECK-DAG: hw.instance "merge2" @{{.*}}(ins_0: %g: {{.*}}, ins_1: %h: {{.*}}) -> (outs:
// CHECK-DAG: hw.instance "buffer0" @{{.*}}(ins: %merge2.outs: {{.*}}) -> (outs:

handshake.func @one(%a: !handshake.channel<i8>, %b: !handshake.channel<i8>, %c: !handshake.channel<i8>, %d: !handshake.channel<i8>, %e: !handshake.channel<i8>, %f: !handshake.channel<i8>, %g: !handshake.channel<i8>, %h: !handshake.channel<i8>, %i: !handshake.channel<i8>, %s: !handshake.channel<i8, [spec: i1]>, %t: !handshake.channel<i8, [spec: i1]>, %sel: !handshake.channel<i1>, %x: !handshake.control<>, %y: !handshake.control<>, %z: !handshake.control<>, %start: !handshake.control<>) -> (!handshake.channel<i8>, !handshake.channel<i8>, !handshake.channel<i8>, !handshake.channel<i1>, !handshake.channel<i8>, !handshake.channel<i8>, !handshake.channel<i8>, !handshake.channel<i8>, !handshake.channel<i8>, !handshake.channel<i8, [spec: i1]>, !handshake.channel<i8, [spec: i1]>, !handshake.control<>, !handshake.control<>, !handshake.control<>, !handshake.control<>) attributes {argNames = ["a", "b", "c", "d", "e", "f", "g", "h", "i", "s", "t", "sel", "x", "y", "z", "start"], resNames = ["om", "ox", "oc", "oi", "ob", "of0", "ol", "og", "ofi", "osm", "osf", "omc", "oj", "ofc", "end"]} {
  %m = merge %a {handshake.name = "merge0"} : <i8>
  %mx = mux %sel [%b] {handshake.name = "mux0"} : <i1>, [<i8>] to <i8>
  %cm, %ci = control_merge [%c] {handshake.name = "cmerge0"} : [<i8>] to <i8>, <i1>
  %bl = blocker %d {handshake.name = "blocker0"} : <i8>
  %fo = fork [1] %e {handshake.name = "fork0"} : <i8>
  %lf = lazy_fork [1] %f {handshake.name = "lfork0"} : <i8>
  %m2 = merge %g, %h {handshake.name = "merge2"} : <i8>
  %bf = buffer %m2, bufferType = ONE_SLOT_BREAK_DV, numSlots = 1, dvLatency = 1 {handshake.name = "buffer0"} : <i8>
  %fi = first %i {handshake.name = "first0"} : <i8>
  %sm = merge %s {handshake.name = "merge3"} : <i8, [spec: i1]>
  %sf = fork [1] %t {handshake.name = "fork2"} : <i8, [spec: i1]>
  %mc = merge %x {handshake.name = "merge1"} : <>
  %j = join %y {handshake.name = "join0"} : <>
  %fc = fork [1] %z {handshake.name = "fork1"} : <>
  end {handshake.name = "end0"} %m, %mx, %cm, %ci, %bl, %fo, %lf, %bf, %fi, %sm, %sf, %mc, %j, %fc, %start : <i8>, <i8>, <i8>, <i1>, <i8>, <i8>, <i8>, <i8>, <i8>, <i8, [spec: i1]>, <i8, [spec: i1]>, <>, <>, <>, <>
}
