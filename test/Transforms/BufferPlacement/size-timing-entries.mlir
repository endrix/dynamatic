// A unit whose delays grow with its size is timed by the entry for the
// smallest size at or above its own, `<name>.size.<N>`. The model in Inputs
// gives a fork of size 2 a 0.001 ns data path and one of size 3 a 1.5 ns one,
// so at a 2.0 ns period two forks in a row need a buffer between them only
// when the size-3 entry is read. A race is sized by the larger of its inputs
// and its candidates, and the model sizes it as the fork.
//
// REQUIRES: cbc
// RUN: dynamatic-opt %s --handshake-place-buffers="algorithm=fpga20 solver=cbc timeout=30 target-period=2.0 timing-models=%S/Inputs/size-timing-models.json spec-timing-models=%dynamatic_src_root/data/spec-timing.json" --remove-operation-names 2>/dev/null | FileCheck %s
// RUN: dynamatic-opt %s --handshake-place-buffers="algorithm=fpga20 solver=cbc timeout=30 target-period=2.0 timing-models=%S/Inputs/size-timing-models.json spec-timing-models=%dynamatic_src_root/data/spec-timing.json" -o /dev/null 2>&1 | FileCheck %s --check-prefix=REMARK

// Two forks of size 2: the size-2 entry's 0.001 ns fits twice over, and
// nothing is placed.
// CHECK-LABEL: handshake.func @two_way_forks
// CHECK-NOT:   buffer
// CHECK:       end
handshake.func @two_way_forks(%arg0: !handshake.channel<i32>, %start: !handshake.control<>, ...) -> (!handshake.channel<i32>, !handshake.control<>) attributes {argNames = ["a", "start"], resNames = ["out", "end"], handshake.frequencies = []} {
  %a:2 = fork [2] %arg0 {handshake.bb = 0 : ui32} : <i32>
  %b:2 = fork [2] %a#0 {handshake.bb = 0 : ui32} : <i32>
  sink %a#1 {handshake.bb = 0 : ui32} : <i32>
  sink %b#1 {handshake.bb = 0 : ui32} : <i32>
  end %b#0, %start : <i32>, <>
}

// Two forks of size 3: the size-3 entry is read, 1.5 + 1.5 ns does not fit
// in 2.0 ns, and the placer cuts between them.
// CHECK-LABEL: handshake.func @three_way_forks
// CHECK:       fork [3]
// CHECK:       buffer
// CHECK:       fork [3]
handshake.func @three_way_forks(%arg0: !handshake.channel<i32>, %start: !handshake.control<>, ...) -> (!handshake.channel<i32>, !handshake.control<>) attributes {argNames = ["a", "start"], resNames = ["out", "end"], handshake.frequencies = []} {
  %a:3 = fork [3] %arg0 {handshake.bb = 0 : ui32} : <i32>
  %b:3 = fork [3] %a#0 {handshake.bb = 0 : ui32} : <i32>
  sink %a#1 {handshake.bb = 0 : ui32} : <i32>
  sink %a#2 {handshake.bb = 0 : ui32} : <i32>
  sink %b#1 {handshake.bb = 0 : ui32} : <i32>
  sink %b#2 {handshake.bb = 0 : ui32} : <i32>
  end %b#0, %start : <i32>, <>
}

// A size past every one the model holds: the largest size's entry is used,
// and the remark says so, once however often the model is asked.
// REMARK: no timing model for "handshake.fork.size.4"; the entry for "handshake.fork.size.3", the largest size characterised, is used instead
// REMARK-NOT: "handshake.fork.size.4"
// CHECK-LABEL: handshake.func @four_way_forks
// CHECK:       fork [4]
// CHECK:       buffer
// CHECK:       fork [4]
handshake.func @four_way_forks(%arg0: !handshake.channel<i32>, %start: !handshake.control<>, ...) -> (!handshake.channel<i32>, !handshake.control<>) attributes {argNames = ["a", "start"], resNames = ["out", "end"], handshake.frequencies = []} {
  %a:4 = fork [4] %arg0 {handshake.bb = 0 : ui32} : <i32>
  %b:4 = fork [4] %a#0 {handshake.bb = 0 : ui32} : <i32>
  sink %a#1 {handshake.bb = 0 : ui32} : <i32>
  sink %a#2 {handshake.bb = 0 : ui32} : <i32>
  sink %a#3 {handshake.bb = 0 : ui32} : <i32>
  sink %b#1 {handshake.bb = 0 : ui32} : <i32>
  sink %b#2 {handshake.bb = 0 : ui32} : <i32>
  sink %b#3 {handshake.bb = 0 : ui32} : <i32>
  end %b#0, %start : <i32>, <>
}

// Two races in a row, each of two inputs (a token and a flag) and two
// candidates, P(t, g(a)): size 2, and nothing is placed.
// CHECK-LABEL: handshake.func @two_candidate_races
// CHECK-NOT:   buffer
// CHECK:       end
handshake.func @two_candidate_races(%t: !handshake.channel<i8>, %a: !handshake.channel<i1>, %b: !handshake.channel<i1>, %start: !handshake.control<>, ...) -> (!handshake.channel<i8>, !handshake.control<>) attributes {argNames = ["t", "a", "b", "start"], resNames = ["out", "end"], handshake.frequencies = []} {
  %x = race [%t] [%a] {candidates = [{token = 0 : i64}, {payload = 1 : ui8, flags = array<i64: 0>, after = array<i64: 0>}], handshake.bb = 0 : ui32} : <i8>
  %y = race [%x] [%b] {candidates = [{token = 0 : i64}, {payload = 2 : ui8, flags = array<i64: 0>, after = array<i64: 0>}], handshake.bb = 0 : ui32} : <i8>
  end %y, %start : <i8>, <>
}

// The same inputs with ALTERNATIVES: F(P(g(a), t), t), the token t read
// twice, after g and after nothing -- two inputs, three candidates. The
// candidates size each race: the size-3 entry is read, 1.5 + 1.5 ns does not
// fit in 2.0 ns, and the placer cuts between them.
// CHECK-LABEL: handshake.func @alternative_races
// CHECK:       race
// CHECK-NEXT:  buffer
// CHECK-NEXT:  race
handshake.func @alternative_races(%t: !handshake.channel<i8>, %a: !handshake.channel<i1>, %b: !handshake.channel<i1>, %start: !handshake.control<>, ...) -> (!handshake.channel<i8>, !handshake.control<>) attributes {argNames = ["t", "a", "b", "start"], resNames = ["out", "end"], handshake.frequencies = []} {
  %x = race [%t] [%a] {candidates = [{payload = 1 : ui8, flags = array<i64: 0>}, {token = 0 : i64, after = array<i64: 0>}, {token = 0 : i64}], handshake.bb = 0 : ui32} : <i8>
  %y = race [%x] [%b] {candidates = [{payload = 2 : ui8, flags = array<i64: 0>}, {token = 0 : i64, after = array<i64: 0>}, {token = 0 : i64}], handshake.bb = 0 : ui32} : <i8>
  end %y, %start : <i8>, <>
}
