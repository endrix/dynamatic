// RUN: dynamatic-opt %s --lower-handshake-to-hw | FileCheck %s

// The order of the entries in the five RTL configurations is load-bearing:
// RTLConfiguration::getMatchingComponent takes the FIRST entry whose name and
// parameters match an instance, and the plain entry matches a module that
// carries the extra parameter too (a parameter an entry does not name is one
// it does not constrain). So each form's entry -- the race's
// REOPEN_AFTER_TAKEN, the commit's KILL_AT_VALID -- must come BEFORE the
// plain one of the same unit, and the plain one must name neither. Pinned
// here for every configuration: no other test reads the vivado one at all
// (export-rtl cannot: its `timing` parameters are not its) or the Verilog
// beta one.
// RUN: FileCheck %s --check-prefix=ORDER --input-file=%dynamatic_src_root/data/rtl-config-vhdl.json
// RUN: FileCheck %s --check-prefix=ORDER --input-file=%dynamatic_src_root/data/rtl-config-vhdl-vivado.json
// RUN: FileCheck %s --check-prefix=ORDER --input-file=%dynamatic_src_root/data/rtl-config-verilog.json
// RUN: FileCheck %s --check-prefix=ORDER --input-file=%dynamatic_src_root/data/rtl-config-verilog-beta.json
// RUN: FileCheck %s --check-prefix=ORDER-SMV --input-file=%dynamatic_src_root/data/rtl-config-smv.json

// ORDER:          "name": "handshake.race",
// ORDER:          "name": "REOPEN_AFTER_TAKEN",
// ORDER:          "name": "handshake.race",
// ORDER-NOT:      REOPEN_AFTER_TAKEN
// ORDER:          "name": "handshake.commit",
// ORDER:          "name": "KILL_AT_VALID",
// ORDER:          "name": "handshake.commit",
// ORDER-NOT:      KILL_AT_VALID

// The SMV configuration also has a race in a kill domain (KILL_RESET), so
// each of its two reopening entries comes before the two that do not reopen.
// ORDER-SMV:      "name": "handshake.race",
// ORDER-SMV:      "name": "REOPEN_AFTER_TAKEN",
// ORDER-SMV:      "name": "handshake.race",
// ORDER-SMV:      "name": "REOPEN_AFTER_TAKEN",
// ORDER-SMV:      "name": "handshake.race",
// ORDER-SMV-NOT:  REOPEN_AFTER_TAKEN
// ORDER-SMV:      "name": "handshake.race",
// ORDER-SMV-NOT:  REOPEN_AFTER_TAKEN
// ORDER-SMV:      "name": "handshake.commit",
// ORDER-SMV:      "name": "KILL_AT_VALID",
// ORDER-SMV:      "name": "handshake.commit",
// ORDER-SMV-NOT:  KILL_AT_VALID

// A commit whose kill comes when its token is first offered
// (`kill_at_valid`) and a race whose inputs reopen only after its answer was
// taken (`reopen_after_taken`) are other circuits than the plain ones: each
// is its own extern module, told apart by a parameter (KILL_AT_VALID = 1,
// REOPEN_AFTER_TAKEN = 1) that the plain unit does not carry, so that a plain
// commit's or race's module is what it was. The kill of either commit goes to
// its domain's units and stand-ins alike.

// CHECK-LABEL: hw.module @forms
// CHECK-DAG: hw.instance "race0" @[[REOPEN:handshake_race_[0-9]+]](flags_0: %a: {{.*}}, flags_1: %b: {{.*}}
// CHECK-DAG: hw.instance "race1" @[[PLAIN:handshake_race_[0-9]+]](flags_0: %c: {{.*}}, flags_1: %d: {{.*}}
// CHECK-DAG: %commit0.outs, %commit0.kill = hw.instance "commit0" @[[AT:handshake_commit_[0-9]+]](ins: %race0.outs: {{.*}}, clk: %clk: i1, rst: %rst: i1)
// CHECK-DAG: %commit1.outs, %commit1.kill = hw.instance "commit1" @[[TRANSFER:handshake_commit_[0-9]+]](ins: %race1.outs: {{.*}}, clk: %clk: i1, rst: %rst: i1)
// CHECK-DAG: hw.instance "buffer0" @{{.*}}(ins: %x: {{.*}}, clk: %clk: i1, rst: %commit0.kill: i1)
// CHECK-DAG: hw.instance "stand_in0" @{{.*}}(ins: %buffer0.outs: {{.*}}, kill_0: %commit0.kill: i1, clk: %clk: i1, rst: %rst: i1)
// CHECK-DAG: hw.instance "buffer1" @{{.*}}(ins: %y: {{.*}}, clk: %clk: i1, rst: %commit1.kill: i1)
// CHECK-DAG: hw.instance "stand_in1" @{{.*}}(ins: %buffer1.outs: {{.*}}, kill_0: %commit1.kill: i1, clk: %clk: i1, rst: %rst: i1)
// CHECK-DAG: hw.module.extern @[[REOPEN]]({{.*}}) attributes {hw.name = "handshake.race", hw.parameters = {CANDIDATES = "p1:f0/p2:f1:a0", DATA_TYPE = !handshake.channel<i2>, REOPEN_AFTER_TAKEN = 1 : ui32, SIZE_FLAGS = 2 : ui32, SIZE_TOKENS = 0 : ui32}}
// CHECK-DAG: hw.module.extern @[[PLAIN]]({{.*}}) attributes {hw.name = "handshake.race", hw.parameters = {CANDIDATES = "p1:f0/p2:f1:a0", DATA_TYPE = !handshake.channel<i2>, SIZE_FLAGS = 2 : ui32, SIZE_TOKENS = 0 : ui32}}
// CHECK-DAG: hw.module.extern @[[AT]]({{.*}}) attributes {hw.name = "handshake.commit", hw.parameters = {DATA_TYPE = !handshake.channel<i2>, KILL_AT_VALID = 1 : ui32}}
// CHECK-DAG: hw.module.extern @[[TRANSFER]]({{.*}}) attributes {hw.name = "handshake.commit", hw.parameters = {DATA_TYPE = !handshake.channel<i2>}}
handshake.func @forms(%a: !handshake.channel<i1>, %b: !handshake.channel<i1>,
                      %c: !handshake.channel<i1>, %d: !handshake.channel<i1>,
                      %x: !handshake.channel<i1>, %y: !handshake.channel<i1>,
                      %start: !handshake.control<>, ...)
    -> (!handshake.channel<i2>, !handshake.channel<i2>, !handshake.channel<i1>,
        !handshake.channel<i1>, !handshake.control<>)
    attributes {argNames = ["a", "b", "c", "d", "x", "y", "start"],
                resNames = ["dec0", "dec1", "flag0", "flag1", "end"]} {
  %r0 = race [] [%a, %b] {candidates = [
          {payload = 1 : ui2, flags = array<i64: 0>},
          {payload = 2 : ui2, flags = array<i64: 1>, after = array<i64: 0>}
        ], reopen_after_taken} : <i2>
  %r1 = race [] [%c, %d] {candidates = [
          {payload = 1 : ui2, flags = array<i64: 0>},
          {payload = 2 : ui2, flags = array<i64: 1>, after = array<i64: 0>}
        ]} : <i2>
  %o0, %k0 = commit %r0 {kill_at_valid} : <i2>
  %o1, %k1 = commit %r1 {domain = 1 : ui32} : <i2>
  %lx = buffer %x, bufferType = ONE_SLOT_BREAK_R, numSlots = 1, dvLatency = 0 {handshake.kill_domain = 0 : ui32} : <i1>
  %f0 = stand_in %lx, %k0 : <i1>
  %ly = buffer %y, bufferType = ONE_SLOT_BREAK_R, numSlots = 1, dvLatency = 0 {handshake.kill_domain = 1 : ui32} : <i1>
  %f1 = stand_in %ly, %k1 : <i1>
  end %o0, %o1, %f0, %f1, %start : <i2>, <i2>, <i1>, <i1>, <>
}
