// A unit's registers in the timing model: its port models (`inport`, from an
// input port into a register, its setup included; `outport`, from a register
// to an output port, its clock to output included), which the placer reads
// for a registered unit (path_inDelay, path_outDelay), and a buffer type's own
// entry (`handshake.buffer.ONE_SLOT_BREAK_R`), which times a buffer of that
// type in the IR. The model in Inputs holds the cases at a 0.5 ns period.
//
// REQUIRES: cbc
// RUN: dynamatic-opt %s --handshake-place-buffers="algorithm=fpga20 solver=cbc timeout=30 target-period=0.5 timing-models=%S/Inputs/register-timing-models.json spec-timing-models=%dynamatic_src_root/data/spec-timing.json" --remove-operation-names 2>/dev/null | FileCheck %s --check-prefix=FPGA20
// RUN: dynamatic-opt %s --handshake-place-buffers="algorithm=fpl22 solver=cbc timeout=30 target-period=0.5 timing-models=%S/Inputs/register-timing-models.json spec-timing-models=%dynamatic_src_root/data/spec-timing.json" --remove-operation-names 2>/dev/null | FileCheck %s --check-prefix=FPL22

// A registered unit's output starts at its register's delay to the port. The
// multiplier here (one cycle) holds it at 8 bits only, 0.4 ns; a 32-bit
// multiplier is wider than the entry and takes the widest, as a latency does,
// and with the subtract after it (0.2 ns) the path is 0.6 ns: a buffer goes
// between them. Read as no delay past the entry, the path was 0.2 and nothing
// was placed.
// FPGA20-LABEL: handshake.func @registered
// FPGA20:       muli
// FPGA20-NEXT:  buffer
// FPGA20-NEXT:  subi
// FPL22-LABEL:  handshake.func @registered
// FPL22:        muli
// FPL22-NEXT:   buffer
// FPL22-NEXT:   subi
handshake.func @registered(%a: !handshake.channel<i32>, %b: !handshake.channel<i32>, %c: !handshake.channel<i32>, %start: !handshake.control<>, ...) -> (!handshake.channel<i32>, !handshake.control<>) attributes {argNames = ["a", "b", "c", "start"], resNames = ["out", "end"], handshake.frequencies = []} {
  %m = muli %a, %b {handshake.bb = 0 : ui32} : <i32>
  %s = subi %m, %c {handshake.bb = 0 : ui32} : <i32>
  end %s, %start : <i32>, <>
}

// A transparent buffer in the IR is timed by its type's entry, whose valid
// passes in 0.45 ns, where the entry all six types share passes it in none.
// After an add's valid (0.2 ns) the path is 0.65 ns, and the placer cuts it
// before the buffer (fpl22 times the valid; fpga20, the data only, places
// nothing here).
// FPL22-LABEL:  handshake.func @typed_buffer
// FPL22:        addi
// FPL22-NEXT:   buffer {{.*}}bufferType = ONE_SLOT_BREAK_DV
// FPL22-NEXT:   buffer {{.*}}bufferType = ONE_SLOT_BREAK_R
handshake.func @typed_buffer(%a: !handshake.channel<i1>, %b: !handshake.channel<i1>, %start: !handshake.control<>, ...) -> (!handshake.channel<i1>, !handshake.control<>) attributes {argNames = ["a", "b", "start"], resNames = ["out", "end"], handshake.frequencies = []} {
  %s = addi %a, %b {handshake.bb = 0 : ui32} : <i1>
  %r = buffer %s, bufferType = ONE_SLOT_BREAK_R, numSlots = 1, dvLatency = 0 {handshake.bb = 0 : ui32} : <i1>
  end %r, %start : <i1>, <>
}
