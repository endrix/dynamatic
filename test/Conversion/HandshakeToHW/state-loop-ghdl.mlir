// REQUIRES: ghdl
// RUN: rm -rf %t && mkdir -p %t
// RUN: dynamatic-opt %s --lower-handshake-to-hw > %t/on.hw
// RUN: dynamatic-opt %s --lower-handshake-to-hw=state-registers=false > %t/off.hw
// RUN: export-rtl %t/on.hw %t/on %dynamatic_src_root/data/rtl-config-vhdl.json --dynamatic-path %dynamatic_src_root --hdl vhdl
// RUN: export-rtl %t/off.hw %t/off %dynamatic_src_root/data/rtl-config-vhdl.json --dynamatic-path %dynamatic_src_root --hdl vhdl
// RUN: FileCheck %s --input-file=%t/on/state.vhd
// RUN: FileCheck %s --input-file=%t/off/state.vhd --check-prefix=OFF
// RUN: ls %t/on | FileCheck %s --check-prefix=FILES
// RUN: cd %t/on && ghdl -i --std=08 --work=state_units *.vhd && ghdl -m --std=08 --work=state_units state
// RUN: cd %t/off && ghdl -i --std=08 --work=generic_units *.vhd && ghdl -m --std=08 --work=generic_units state
// RUN: cd %t && ghdl -a --std=08 -Pon -Poff %S/Inputs/state-loop-tb.vhd && ghdl --elab-run --std=08 -Pon -Poff tb --ieee-asserts=disable 2>&1 | FileCheck %s --check-prefix=SIM

// The state registers' units, run. Four state registers' loops (state-loop.mlir
// says what one is) of 1, 8, 33 and 64 bits, each with a reset value of its
// own, their next values computed from an input's bare data and from each
// other, and a slot that is no state's. The function is lowered and
// exported twice: as it is by default, the init and the slot of every loop
// on handshake_init_state and handshake_buffer_state, and with
// state-registers=false, on handshake_init and the oehb of any channel. The
// testbench holds the two exports together under random inputs, output
// readies and resets: every output, the four states among them, is the same
// in every cycle.

// CHECK-DAG: init0 : entity work.handshake_init_state(arch) generic map("1", 1)
// CHECK-DAG: buffer0 : entity work.handshake_buffer_state(arch) generic map(1)
// CHECK-DAG: init1 : entity work.handshake_init_state(arch) generic map("5", 8)
// CHECK-DAG: buffer1 : entity work.handshake_buffer_state(arch) generic map(8)
// CHECK-DAG: init2 : entity work.handshake_init_state(arch) generic map("4294967296", 33)
// CHECK-DAG: buffer2 : entity work.handshake_buffer_state(arch) generic map(33)
// CHECK-DAG: init3 : entity work.handshake_init_state(arch) generic map("18446744073709551615", 64)
// CHECK-DAG: buffer3 : entity work.handshake_buffer_state(arch) generic map(64)
// CHECK-DAG: buffer4 : entity work.oehb(arch) generic map(8)

// OFF-NOT: _state(arch)
// OFF-DAG: init0 : entity work.handshake_init(arch) generic map("1", 1)
// OFF-DAG: buffer0 : entity work.oehb(arch) generic map(1)
// OFF-DAG: init3 : entity work.handshake_init(arch) generic map("18446744073709551615", 64)
// OFF-DAG: buffer3 : entity work.oehb(arch) generic map(64)
// OFF-DAG: buffer4 : entity work.oehb(arch) generic map(8)

// One file for each of the two units, whatever the widths; no init of the
// function is the generic one, so its file is not written.
// FILES:     handshake_buffer_state.vhd
// FILES-NOT: handshake_init.vhd
// FILES:     handshake_init_state.vhd
// FILES:     oehb.vhd

// SIM: 20000 cycles agree, the states moved in {{[0-9]+}}, {{[0-9]+}} transfers of a state, {{[0-9]+}} resets
// SIM-NOT: differ

handshake.func @state(%d: !handshake.channel<i8>, %go: !handshake.control<>, ...)
    -> (!handshake.channel<i1>, !handshake.channel<i8>, !handshake.channel<i33>, !handshake.channel<i64>, !handshake.channel<i8>)
    attributes {argNames = ["d", "go"], resNames = ["f", "a", "w", "x", "p"]} {
  // four state registers: one bit, 8, 33 and 64 bits
  %fb = bundle %fc, %fnext {handshake.name = "bundle0"} : _ to <i1>
  %fi = init %fb {handshake.name = "init0", hw.parameters = {INIT_VALUE = 1 : i1}} : <i1>
  %fs = buffer %fi, bufferType = ONE_SLOT_BREAK_DV, numSlots = 1, dvLatency = 1 {handshake.name = "buffer0"} : <i1>
  %fc, %f = unbundle %fs {handshake.name = "unbundle0"} : <i1> to _

  %ab = bundle %ac, %anext {handshake.name = "bundle1"} : _ to <i8>
  %ai = init %ab {handshake.name = "init1", hw.parameters = {INIT_VALUE = 5 : i8}} : <i8>
  %as = buffer %ai, bufferType = ONE_SLOT_BREAK_DV, numSlots = 1, dvLatency = 1 {handshake.name = "buffer1"} : <i8>
  %ac, %a = unbundle %as {handshake.name = "unbundle1"} : <i8> to _

  %wb = bundle %wc, %wnext {handshake.name = "bundle2"} : _ to <i33>
  %wi = init %wb {handshake.name = "init2", hw.parameters = {INIT_VALUE = 4294967296 : i33}} : <i33>
  %ws = buffer %wi, bufferType = ONE_SLOT_BREAK_DV, numSlots = 1, dvLatency = 1 {handshake.name = "buffer2"} : <i33>
  %wc, %w = unbundle %ws {handshake.name = "unbundle2"} : <i33> to _

  %xb = bundle %xc, %xnext {handshake.name = "bundle3"} : _ to <i64>
  %xi = init %xb {handshake.name = "init3", hw.parameters = {INIT_VALUE = -1 : i64}} : <i64>
  %xs = buffer %xi, bufferType = ONE_SLOT_BREAK_DV, numSlots = 1, dvLatency = 1 {handshake.name = "buffer3"} : <i64>
  %xc, %x = unbundle %xs {handshake.name = "unbundle3"} : <i64> to _

  // the next values, from the input's bare data and the states
  %dc, %dd = unbundle %d {handshake.name = "unbundle4"} : <i8> to _
  %d0 = arith.trunci %dd : i8 to i1
  %fnext = arith.xori %f, %d0 : i1
  %anext = arith.addi %a, %dd : i8
  %a33 = arith.extui %a : i8 to i33
  %wnext = arith.xori %w, %a33 : i33
  %a64 = arith.extui %a : i8 to i64
  %xnext = arith.addi %x, %a64 : i64

  // the states read, each on a copy of `go`
  %go0, %go1, %go2, %go3, %go4 = fork [5] %go {handshake.name = "fork0"} : <>
  %fq = bundle %go0, %f {handshake.name = "bundle4"} : _ to <i1>
  %aq = bundle %go1, %a {handshake.name = "bundle5"} : _ to <i8>
  %wq = bundle %go2, %w {handshake.name = "bundle6"} : _ to <i33>
  %xq = bundle %go3, %x {handshake.name = "bundle7"} : _ to <i64>

  // and one slot that is no state's: the input, behind a join with `go`
  %j = join %dc, %go4 {handshake.name = "join0"} : <>
  %pd = bundle %j, %dd {handshake.name = "bundle8"} : _ to <i8>
  %p = buffer %pd, bufferType = ONE_SLOT_BREAK_DV, numSlots = 1, dvLatency = 1 {handshake.name = "buffer4"} : <i8>
  end %fq, %aq, %wq, %xq, %p : <i1>, <i8>, <i33>, <i64>, <i8>
}
