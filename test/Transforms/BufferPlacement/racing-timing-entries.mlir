// The race (`handshake.race`, a racing decision as one unit) is characterized
// too, by its inputs (2 to 128, the maximum over the nests a lowering makes;
// its CR is 0, since its readies read no data, where a false path once gave
// 0.234 ns):
// a priority over four tokens as three priority units in series no longer
// fits 0.25 ns (about 0.11 ns of 8-bit data each), and the placer cuts the
// chain; the same decision as one race of four (0.207 ns of data) does, and
// keeps no buffer.
//
// The racing units are characterized in the shipped ASAP7 SLVT model, not
// copied from other units: a first at every size of the sweep, a priority, a
// commit with its kill's delays (VK, RK), a stand-in at every number of kills
// from one, the load that drops on a kill, and the lowering's kill_or at every
// size; no entry of theirs is a copy (the copies said why in a `stand_in`
// note); the dropping load has the load's latency (one cycle: the same two
// slots), not the default's zero, which a placer would read as a wire. And
// the sized entries are what a placer reads, at their measured values: two
// first units of two inputs in a row fit 0.3 ns (0.128 ns of 8-bit data
// each), two of eight (0.195 ns each) do not, and the placer cuts between
// them; at 0.22 ns the two of two inputs no longer fit (the copied entry's
// 0.090 would have, twice), and the placer cuts between those too.
//
// REQUIRES: cbc
// RUN: FileCheck %s --check-prefix=ENTRIES --input-file=%dynamatic_src_root/data/components-asap7.json
// RUN: FileCheck %s --check-prefix=COMMIT --input-file=%dynamatic_src_root/data/components-asap7.json
// RUN: FileCheck %s --check-prefix=MEASURED --input-file=%dynamatic_src_root/data/components-asap7.json
// RUN: FileCheck %s --check-prefix=LOADLAT --input-file=%dynamatic_src_root/data/components-asap7.json
// RUN: FileCheck %s --check-prefix=RACECR --input-file=%dynamatic_src_root/data/components-asap7.json
// RUN: dynamatic-opt %s --handshake-place-buffers="algorithm=fpga20 solver=cbc timeout=30 target-period=0.3 timing-models=%dynamatic_src_root/data/components-asap7.json spec-timing-models=%dynamatic_src_root/data/spec-timing.json" --remove-operation-names 2>/dev/null | FileCheck %s
// RUN: dynamatic-opt %s --handshake-place-buffers="algorithm=fpga20 solver=cbc timeout=30 target-period=0.22 timing-models=%dynamatic_src_root/data/components-asap7.json spec-timing-models=%dynamatic_src_root/data/spec-timing.json" --remove-operation-names 2>/dev/null | FileCheck %s --check-prefix=TIGHT
// RUN: dynamatic-opt %s --handshake-place-buffers="algorithm=fpga20 solver=cbc timeout=30 target-period=0.25 timing-models=%dynamatic_src_root/data/components-asap7.json spec-timing-models=%dynamatic_src_root/data/spec-timing.json" --remove-operation-names 2>/dev/null | FileCheck %s --check-prefix=RACE

// ENTRIES-DAG: "handshake.first.size.2": {
// ENTRIES-DAG: "handshake.first.size.3": {
// ENTRIES-DAG: "handshake.first.size.4": {
// ENTRIES-DAG: "handshake.first.size.8": {
// ENTRIES-DAG: "handshake.first.size.16": {
// ENTRIES-DAG: "handshake.first.size.32": {
// ENTRIES-DAG: "handshake.first.size.64": {
// ENTRIES-DAG: "handshake.first.size.128": {
// ENTRIES-DAG: "handshake.first.size.256": {
// ENTRIES-DAG: "handshake.priority": {
// ENTRIES-DAG: "handshake.commit": {
// ENTRIES-DAG: "handshake.stand_in.size.1": {
// ENTRIES-DAG: "handshake.stand_in.size.2": {
// ENTRIES-DAG: "handshake.stand_in.size.3": {
// ENTRIES-DAG: "handshake.stand_in.size.4": {
// ENTRIES-DAG: "handshake.stand_in.size.8": {
// ENTRIES-DAG: "handshake.stand_in.size.16": {
// ENTRIES-DAG: "handshake.stand_in.size.32": {
// ENTRIES-DAG: "handshake.stand_in.size.64": {
// ENTRIES-DAG: "handshake.stand_in.size.128": {
// ENTRIES-DAG: "handshake.stand_in.size.256": {
// ENTRIES-DAG: "handshake.load.kill_drop": {
// ENTRIES-DAG: "kill_or.size.2": {
// ENTRIES-DAG: "kill_or.size.3": {
// ENTRIES-DAG: "kill_or.size.4": {
// ENTRIES-DAG: "kill_or.size.8": {
// ENTRIES-DAG: "kill_or.size.16": {
// ENTRIES-DAG: "kill_or.size.32": {
// ENTRIES-DAG: "kill_or.size.64": {
// ENTRIES-DAG: "kill_or.size.128": {
// ENTRIES-DAG: "kill_or.size.256": {
// ENTRIES-DAG: "handshake.race": {
// ENTRIES-DAG: "handshake.race.size.2": {
// ENTRIES-DAG: "handshake.race.size.3": {
// ENTRIES-DAG: "handshake.race.size.4": {
// ENTRIES-DAG: "handshake.race.size.8": {
// ENTRIES-DAG: "handshake.race.size.16": {
// ENTRIES-DAG: "handshake.race.size.32": {
// ENTRIES-DAG: "handshake.race.size.64": {
// ENTRIES-DAG: "handshake.race.size.128": {

// A race's readies read no data (done_wo: the other inputs' arrivals and the
// output's ready), so the characterization does not measure data into ready
// for it and every entry's CR is 0.
// RACECR:      "handshake.race": {
// RACECR-NOT:  "handshake.
// RACECR:        "CR": 0{{(\.0)?}},
// RACECR:      "handshake.race.size.4": {
// RACECR-NOT:  "handshake.
// RACECR:        "CR": 0{{(\.0)?}},
// RACECR:      "handshake.race.size.32": {
// RACECR-NOT:  "handshake.
// RACECR:        "CR": 0{{(\.0)?}},
// RACECR:      "handshake.race.size.128": {
// RACECR-NOT:  "handshake.
// RACECR:        "CR": 0{{(\.0)?}},

// COMMIT:      "handshake.commit": {
// COMMIT:        "VK":
// COMMIT-NEXT:   "RK":
// COMMIT:        "inport":

// MEASURED-NOT: {{^ *}}"stand_in": "

// LOADLAT:      "handshake.load.kill_drop": {
// LOADLAT-NEXT:   "latency": {
// LOADLAT-NEXT:     "0": {
// LOADLAT-NEXT:       "64": {
// LOADLAT-NEXT:         "1.0": 1.0

// CHECK-LABEL: handshake.func @two_way_firsts
// CHECK-NOT:   buffer
// CHECK:       end
// TIGHT-LABEL: handshake.func @two_way_firsts
// TIGHT:       first
// TIGHT-NEXT:  buffer
// TIGHT-NEXT:  first
handshake.func @two_way_firsts(%a: !handshake.channel<i8>, %b: !handshake.channel<i8>, %c: !handshake.channel<i8>, %start: !handshake.control<>, ...) -> (!handshake.channel<i8>, !handshake.control<>) attributes {argNames = ["a", "b", "c", "start"], resNames = ["out", "end"], handshake.frequencies = []} {
  %x = first %a, %b {handshake.bb = 0 : ui32} : <i8>
  %y = first %x, %c {handshake.bb = 0 : ui32} : <i8>
  end %y, %start : <i8>, <>
}

// CHECK-LABEL: handshake.func @eight_way_firsts
// CHECK:       first
// CHECK-NEXT:  buffer
// CHECK-NEXT:  first
handshake.func @eight_way_firsts(%a: !handshake.channel<i8>, %b: !handshake.channel<i8>, %c: !handshake.channel<i8>, %d: !handshake.channel<i8>, %e: !handshake.channel<i8>, %f: !handshake.channel<i8>, %g: !handshake.channel<i8>, %h: !handshake.channel<i8>, %i: !handshake.channel<i8>, %j: !handshake.channel<i8>, %k: !handshake.channel<i8>, %l: !handshake.channel<i8>, %m: !handshake.channel<i8>, %n: !handshake.channel<i8>, %o: !handshake.channel<i8>, %start: !handshake.control<>, ...) -> (!handshake.channel<i8>, !handshake.control<>) attributes {argNames = ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "start"], resNames = ["out", "end"], handshake.frequencies = []} {
  %x = first %a, %b, %c, %d, %e, %f, %g, %h {handshake.bb = 0 : ui32} : <i8>
  %y = first %x, %i, %j, %k, %l, %m, %n, %o {handshake.bb = 0 : ui32} : <i8>
  end %y, %start : <i8>, <>
}

// RACE-LABEL: handshake.func @priority_chain
// RACE:       priority
// RACE:       buffer
// RACE:       end
// RACE-LABEL: handshake.func @race_of_four
// RACE-NOT:   buffer
// RACE:       end
handshake.func @priority_chain(%a: !handshake.channel<i8>, %b: !handshake.channel<i8>, %c: !handshake.channel<i8>, %d: !handshake.channel<i8>, %start: !handshake.control<>, ...) -> (!handshake.channel<i8>, !handshake.control<>) attributes {argNames = ["a", "b", "c", "d", "start"], resNames = ["out", "end"], handshake.frequencies = []} {
  %x = priority %c, %d {handshake.bb = 0 : ui32} : <i8>
  %y = priority %b, %x {handshake.bb = 0 : ui32} : <i8>
  %z = priority %a, %y {handshake.bb = 0 : ui32} : <i8>
  end %z, %start : <i8>, <>
}

handshake.func @race_of_four(%a: !handshake.channel<i8>, %b: !handshake.channel<i8>, %c: !handshake.channel<i8>, %d: !handshake.channel<i8>, %start: !handshake.control<>, ...) -> (!handshake.channel<i8>, !handshake.control<>) attributes {argNames = ["a", "b", "c", "d", "start"], resNames = ["out", "end"], handshake.frequencies = []} {
  %z = race [%a, %b, %c, %d] [] {candidates = [{token = 0 : i64}, {token = 1 : i64, after = array<i64: 0>}, {token = 2 : i64, after = array<i64: 0, 1>}, {token = 3 : i64, after = array<i64: 0, 1, 2>}], handshake.bb = 0 : ui32} : <i8>
  end %z, %start : <i8>, <>
}
