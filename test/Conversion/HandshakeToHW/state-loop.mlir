// RUN: dynamatic-opt %s --lower-handshake-to-hw --split-input-file | FileCheck %s
// RUN: dynamatic-opt %s --lower-handshake-to-hw=state-registers=false --split-input-file | FileCheck %s --check-prefix=OFF --implicit-check-not=STATE_LOOP

// A STATE REGISTER'S LOOP: a bundle of a control and the next value into an
// init, one ONE_SLOT_BREAK_DV slot, and an unbundle whose control is read by
// that bundle alone. Nothing outside the loop sees its valids and readies, so
// its token is in the slot at every cycle but the first: the lowering names
// the init and the slot (STATE_LOOP) and the RTL configuration gives them
// the units with that loop's logic only (state-loop-ghdl.mlir runs them).
// The name is on the units of such a loop and on no other: every function
// below but the first is one step away from the loop and keeps the init and
// the buffer of any channel. Off (state-registers=false), no unit has it.

// Two loops, of two widths and reset values, and a slot of the same type as
// the first loop's on a channel of its own: another module.
// CHECK-LABEL: hw.module @state(
// CHECK:         hw.instance "init0" @[[INIT8:handshake_init_[0-9]+]](
// CHECK:         hw.instance "buffer0" @[[SLOT8:handshake_buffer_[0-9]+]](
// CHECK:         hw.instance "init1" @[[INIT33:handshake_init_[0-9]+]](
// CHECK:         hw.instance "buffer1" @[[SLOT33:handshake_buffer_[0-9]+]](
// CHECK:         hw.instance "buffer2" @[[PLAIN:handshake_buffer_[0-9]+]](
// CHECK-DAG: hw.module.extern @[[INIT8]]({{.*}}hw.parameters = {DATA_TYPE = !handshake.channel<i8>, INITIAL_VALUE = "5", INIT_VALUE = 5 : i8, STATE_LOOP = 1 : ui32}}
// CHECK-DAG: hw.module.extern @[[SLOT8]]({{.*}}hw.parameters = {BUFFER_TYPE = "ONE_SLOT_BREAK_DV", DATA_TYPE = !handshake.channel<i8>, DV_LATENCY = 1 : ui32, NUM_SLOTS = 1 : ui32, STATE_LOOP = 1 : ui32}}
// CHECK-DAG: hw.module.extern @[[INIT33]]({{.*}}hw.parameters = {DATA_TYPE = !handshake.channel<i33>, INITIAL_VALUE = "4294967296", INIT_VALUE = {{.*}} : i33, STATE_LOOP = 1 : ui32}}
// CHECK-DAG: hw.module.extern @[[SLOT33]]({{.*}}hw.parameters = {BUFFER_TYPE = "ONE_SLOT_BREAK_DV", DATA_TYPE = !handshake.channel<i33>, DV_LATENCY = 1 : ui32, NUM_SLOTS = 1 : ui32, STATE_LOOP = 1 : ui32}}
// CHECK-DAG: hw.module.extern @[[PLAIN]]({{.*}}hw.parameters = {BUFFER_TYPE = "ONE_SLOT_BREAK_DV", DATA_TYPE = !handshake.channel<i8>, DV_LATENCY = 1 : ui32, NUM_SLOTS = 1 : ui32}}
// OFF-LABEL: hw.module @state(
handshake.func @state(%d: !handshake.channel<i8>, %go: !handshake.control<>, ...)
    -> (!handshake.channel<i8>, !handshake.channel<i33>, !handshake.channel<i8>)
    attributes {argNames = ["d", "go"], resNames = ["q", "r", "p"]} {
  %b = bundle %c, %next {handshake.name = "bundle0"} : _ to <i8>
  %i = init %b {handshake.name = "init0", hw.parameters = {INIT_VALUE = 5 : i8}} : <i8>
  %s = buffer %i, bufferType = ONE_SLOT_BREAK_DV, numSlots = 1, dvLatency = 1 {handshake.name = "buffer0"} : <i8>
  %c, %value = unbundle %s {handshake.name = "unbundle0"} : <i8> to _

  %wb = bundle %wc, %wnext {handshake.name = "bundle1"} : _ to <i33>
  %wi = init %wb {handshake.name = "init1", hw.parameters = {INIT_VALUE = 4294967296 : i33}} : <i33>
  %ws = buffer %wi, bufferType = ONE_SLOT_BREAK_DV, numSlots = 1, dvLatency = 1 {handshake.name = "buffer1"} : <i33>
  %wc, %wvalue = unbundle %ws {handshake.name = "unbundle1"} : <i33> to _

  %dc, %dd = unbundle %d {handshake.name = "unbundle2"} : <i8> to _
  %next = arith.addi %value, %dd : i8
  %wide = arith.extui %value : i8 to i33
  %wnext = arith.xori %wvalue, %wide : i33

  %go0, %go1, %go2 = fork [3] %go {handshake.name = "fork0"} : <>
  %q = bundle %go0, %value {handshake.name = "bundle2"} : _ to <i8>
  %r = bundle %go1, %wvalue {handshake.name = "bundle3"} : _ to <i33>
  %j = join %dc, %go2 {handshake.name = "join0"} : <>
  %pd = bundle %j, %dd {handshake.name = "bundle4"} : _ to <i8>
  %p = buffer %pd, bufferType = ONE_SLOT_BREAK_DV, numSlots = 1, dvLatency = 1 {handshake.name = "buffer2"} : <i8>
  end %q, %r, %p : <i8>, <i33>, <i8>
}

// -----

// The unbundle's control is read outside the loop too (a fork): the loop's
// token can be held from there.
// CHECK-LABEL: hw.module @control_read_outside(
// CHECK-NOT: STATE_LOOP
handshake.func @control_read_outside(%d: !handshake.channel<i8>, ...) -> (!handshake.channel<i8>)
    attributes {argNames = ["d"], resNames = ["q"]} {
  %b = bundle %c0, %next : _ to <i8>
  %i = init %b {hw.parameters = {INIT_VALUE = 5 : i8}} : <i8>
  %s = buffer %i, bufferType = ONE_SLOT_BREAK_DV, numSlots = 1, dvLatency = 1 : <i8>
  %c, %value = unbundle %s : <i8> to _
  %c0, %c1 = fork [2] %c : <>
  %dc, %dd = unbundle %d : <i8> to _
  %next = arith.addi %value, %dd : i8
  %j = join %dc, %c1 : <>
  %q = bundle %j, %value : _ to <i8>
  end %q : <i8>
}

// -----

// The bundle's control is not the unbundle's: the state's token comes from
// outside at every turn.
// CHECK-LABEL: hw.module @control_from_outside(
// CHECK-NOT: STATE_LOOP
handshake.func @control_from_outside(%d: !handshake.channel<i8>, %go: !handshake.control<>, ...)
    -> (!handshake.channel<i8>)
    attributes {argNames = ["d", "go"], resNames = ["q"]} {
  %b = bundle %go, %next : _ to <i8>
  %i = init %b {hw.parameters = {INIT_VALUE = 5 : i8}} : <i8>
  %s = buffer %i, bufferType = ONE_SLOT_BREAK_DV, numSlots = 1, dvLatency = 1 : <i8>
  %c, %value = unbundle %s : <i8> to _
  %dc, %dd = unbundle %d : <i8> to _
  %next = arith.addi %value, %dd : i8
  %j = join %dc, %c : <>
  %q = bundle %j, %value : _ to <i8>
  end %q : <i8>
}

// -----

// The slot is transparent (ONE_SLOT_BREAK_R): the loop has no register.
// CHECK-LABEL: hw.module @transparent_slot(
// CHECK-NOT: STATE_LOOP
handshake.func @transparent_slot(%d: !handshake.channel<i8>, %go: !handshake.control<>, ...)
    -> (!handshake.channel<i8>)
    attributes {argNames = ["d", "go"], resNames = ["q"]} {
  %b = bundle %c, %dd : _ to <i8>
  %i = init %b {hw.parameters = {INIT_VALUE = 5 : i8}} : <i8>
  %s = buffer %i, bufferType = ONE_SLOT_BREAK_R, numSlots = 1, dvLatency = 0 : <i8>
  %c, %value = unbundle %s : <i8> to _
  %dc, %dd = unbundle %d : <i8> to _
  %j = join %dc, %go : <>
  %q = bundle %j, %value : _ to <i8>
  end %q : <i8>
}

// -----

// Any other slot of one slot that registers the data: the units are the
// loop's with a ONE_SLOT_BREAK_DV slot and no other. (A slot that registers
// the ready too holds the token a cycle longer; an init named beside one
// would put out another value.)
// CHECK-LABEL: hw.module @ready_registered_slot(
// CHECK-NOT: STATE_LOOP
handshake.func @ready_registered_slot(%d: !handshake.channel<i8>, %go: !handshake.control<>, ...)
    -> (!handshake.channel<i8>)
    attributes {argNames = ["d", "go"], resNames = ["q"]} {
  %b = bundle %c, %next : _ to <i8>
  %i = init %b {hw.parameters = {INIT_VALUE = 5 : i8}} : <i8>
  %s = buffer %i, bufferType = ONE_SLOT_BREAK_DVR, numSlots = 1, dvLatency = 1 : <i8>
  %c, %value = unbundle %s : <i8> to _
  %dc, %dd = unbundle %d : <i8> to _
  %next = arith.addi %value, %dd : i8
  %j = join %dc, %go : <>
  %q = bundle %j, %value : _ to <i8>
  end %q : <i8>
}

// -----

// CHECK-LABEL: hw.module @fifo_slot(
// CHECK-NOT: STATE_LOOP
handshake.func @fifo_slot(%d: !handshake.channel<i8>, %go: !handshake.control<>, ...)
    -> (!handshake.channel<i8>)
    attributes {argNames = ["d", "go"], resNames = ["q"]} {
  %b = bundle %c, %next : _ to <i8>
  %i = init %b {hw.parameters = {INIT_VALUE = 5 : i8}} : <i8>
  %s = buffer %i, bufferType = FIFO_BREAK_DV, numSlots = 1, dvLatency = 1 : <i8>
  %c, %value = unbundle %s : <i8> to _
  %dc, %dd = unbundle %d : <i8> to _
  %next = arith.addi %value, %dd : i8
  %j = join %dc, %go : <>
  %q = bundle %j, %value : _ to <i8>
  end %q : <i8>
}

// -----

// CHECK-LABEL: hw.module @shift_register_slot(
// CHECK-NOT: STATE_LOOP
handshake.func @shift_register_slot(%d: !handshake.channel<i8>, %go: !handshake.control<>, ...)
    -> (!handshake.channel<i8>)
    attributes {argNames = ["d", "go"], resNames = ["q"]} {
  %b = bundle %c, %next : _ to <i8>
  %i = init %b {hw.parameters = {INIT_VALUE = 5 : i8}} : <i8>
  %s = buffer %i, bufferType = SHIFT_REG_BREAK_DV, numSlots = 1, dvLatency = 1 : <i8>
  %c, %value = unbundle %s : <i8> to _
  %dc, %dd = unbundle %d : <i8> to _
  %next = arith.addi %value, %dd : i8
  %j = join %dc, %go : <>
  %q = bundle %j, %value : _ to <i8>
  end %q : <i8>
}

// -----

// CHECK-LABEL: hw.module @counter_slot(
// CHECK-NOT: STATE_LOOP
handshake.func @counter_slot(%d: !handshake.channel<i8>, %go: !handshake.control<>, ...)
    -> (!handshake.channel<i8>)
    attributes {argNames = ["d", "go"], resNames = ["q"]} {
  %b = bundle %c, %next : _ to <i8>
  %i = init %b {hw.parameters = {INIT_VALUE = 5 : i8}} : <i8>
  %s = buffer %i, bufferType = COUNTER_BUFFER, numSlots = 1, dvLatency = 1 : <i8>
  %c, %value = unbundle %s : <i8> to _
  %dc, %dd = unbundle %d : <i8> to _
  %next = arith.addi %value, %dd : i8
  %j = join %dc, %go : <>
  %q = bundle %j, %value : _ to <i8>
  end %q : <i8>
}

// -----

// A second buffer between the slot and the unbundle: the slot's output is
// not the unbundle's input.
// CHECK-LABEL: hw.module @second_buffer(
// CHECK-NOT: STATE_LOOP
handshake.func @second_buffer(%d: !handshake.channel<i8>, %go: !handshake.control<>, ...)
    -> (!handshake.channel<i8>)
    attributes {argNames = ["d", "go"], resNames = ["q"]} {
  %b = bundle %c, %next : _ to <i8>
  %i = init %b {hw.parameters = {INIT_VALUE = 5 : i8}} : <i8>
  %s = buffer %i, bufferType = ONE_SLOT_BREAK_DV, numSlots = 1, dvLatency = 1 : <i8>
  %t = buffer %s, bufferType = ONE_SLOT_BREAK_R, numSlots = 1, dvLatency = 0 : <i8>
  %c, %value = unbundle %t : <i8> to _
  %dc, %dd = unbundle %d : <i8> to _
  %next = arith.addi %value, %dd : i8
  %j = join %dc, %go : <>
  %q = bundle %j, %value : _ to <i8>
  end %q : <i8>
}

// -----

// No slot: the init's output is the unbundle's input.
// CHECK-LABEL: hw.module @no_slot(
// CHECK-NOT: STATE_LOOP
handshake.func @no_slot(%d: !handshake.channel<i8>, %go: !handshake.control<>, ...)
    -> (!handshake.channel<i8>)
    attributes {argNames = ["d", "go"], resNames = ["q"]} {
  %b = bundle %c, %dd : _ to <i8>
  %i = init %b {hw.parameters = {INIT_VALUE = 5 : i8}} : <i8>
  %c, %value = unbundle %i : <i8> to _
  %dc, %dd = unbundle %d : <i8> to _
  %j = join %dc, %go : <>
  %q = bundle %j, %value : _ to <i8>
  end %q : <i8>
}

// -----

// A loop in a kill domain keeps the units of any channel. Its four units
// are in the domain together or not at all: where the slot alone is marked,
// the closure brings in the init (and the bundle and the unbundle), and both
// are reset by the commit's kill.
// CHECK-LABEL: hw.module @killed(
// CHECK:         hw.instance "init0" @{{.*}}(ins: {{.*}}, clk: %clk: i1, rst: %commit0.kill: i1)
// CHECK:         hw.instance "buffer0" @{{.*}}(ins: {{.*}}, clk: %clk: i1, rst: %commit0.kill: i1)
// CHECK-NOT: STATE_LOOP
handshake.func @killed(%d: !handshake.channel<i8>, %go: !handshake.control<>, %dec: !handshake.channel<i3>, ...)
    -> (!handshake.channel<i8>, !handshake.channel<i3>)
    attributes {argNames = ["d", "go", "dec"], resNames = ["q", "dec_out"]} {
  %b = bundle %c, %next {handshake.kill_domain = 0 : ui32} : _ to <i8>
  %i = init %b {handshake.name = "init0", handshake.kill_domain = 0 : ui32, hw.parameters = {INIT_VALUE = 5 : i8}} : <i8>
  %s = buffer %i, bufferType = ONE_SLOT_BREAK_DV, numSlots = 1, dvLatency = 1 {handshake.name = "buffer0", handshake.kill_domain = 0 : ui32} : <i8>
  %c, %value = unbundle %s {handshake.kill_domain = 0 : ui32} : <i8> to _
  %dc, %dd = unbundle %d : <i8> to _
  %next = arith.addi %value, %dd : i8
  %j = join %dc, %go : <>
  %q = bundle %j, %value : _ to <i8>
  %decision, %kill = commit %dec {handshake.name = "commit0", handshake.kill_source = 0 : ui32} : <i3>
  end %q, %decision : <i8>, <i3>
}

// -----

// CHECK-LABEL: hw.module @killed_slot(
// CHECK:         hw.instance "init0" @{{.*}}(ins: {{.*}}, clk: %clk: i1, rst: %commit0.kill: i1)
// CHECK:         hw.instance "buffer0" @{{.*}}(ins: {{.*}}, clk: %clk: i1, rst: %commit0.kill: i1)
// CHECK-NOT: STATE_LOOP
handshake.func @killed_slot(%d: !handshake.channel<i8>, %go: !handshake.control<>, %dec: !handshake.channel<i3>, ...)
    -> (!handshake.channel<i8>, !handshake.channel<i3>)
    attributes {argNames = ["d", "go", "dec"], resNames = ["q", "dec_out"]} {
  %b = bundle %c, %next : _ to <i8>
  %i = init %b {handshake.name = "init0", hw.parameters = {INIT_VALUE = 5 : i8}} : <i8>
  %s = buffer %i, bufferType = ONE_SLOT_BREAK_DV, numSlots = 1, dvLatency = 1 {handshake.name = "buffer0", handshake.kill_domain = 0 : ui32} : <i8>
  %c, %value = unbundle %s : <i8> to _
  %dc, %dd = unbundle %d : <i8> to _
  %next = arith.addi %value, %dd : i8
  %j = join %dc, %go : <>
  %q = bundle %j, %value : _ to <i8>
  %decision, %kill = commit %dec {handshake.name = "commit0", handshake.kill_source = 0 : ui32} : <i3>
  end %q, %decision : <i8>, <i3>
}

// -----

// The name is the lowering's own: one that came with the IR, on an init and
// a slot of no loop, is removed.
// CHECK-LABEL: hw.module @named_from_outside(
// CHECK:         hw.instance "init0" @[[LOOSE_INIT:handshake_init_[0-9]+]](
// CHECK:         hw.instance "buffer0" @[[LOOSE_SLOT:handshake_buffer_[0-9]+]](
// CHECK-DAG: hw.module.extern @[[LOOSE_INIT]]({{.*}}hw.parameters = {DATA_TYPE = !handshake.channel<i8>, INITIAL_VALUE = "5", INIT_VALUE = 5 : i8}}
// CHECK-DAG: hw.module.extern @[[LOOSE_SLOT]]({{.*}}hw.parameters = {BUFFER_TYPE = "ONE_SLOT_BREAK_DV", DATA_TYPE = !handshake.channel<i8>, DV_LATENCY = 1 : ui32, NUM_SLOTS = 1 : ui32}}
handshake.func @named_from_outside(%d: !handshake.channel<i8>, ...) -> (!handshake.channel<i8>)
    attributes {argNames = ["d"], resNames = ["q"]} {
  %i = init %d {handshake.name = "init0", hw.parameters = {INIT_VALUE = 5 : i8, STATE_LOOP = 1 : ui32}} : <i8>
  %q = buffer %i, bufferType = ONE_SLOT_BREAK_DV, numSlots = 1, dvLatency = 1 {handshake.name = "buffer0", hw.parameters = {STATE_LOOP = 1 : ui32}} : <i8>
  end %q : <i8>
}

// -----

// Two functions in one module, one instantiating the other: the loops of
// both are named, and their inits and slots, of one type and reset value,
// are one module each. An init and a slot of the same parameters on a
// channel of their own, in the same function as a loop, are other modules.
// CHECK-LABEL: hw.module @inner(
// CHECK:         hw.instance "init0" @[[LOOP_INIT:handshake_init_[0-9]+]](
// CHECK:         hw.instance "buffer0" @[[LOOP_SLOT:handshake_buffer_[0-9]+]](
// CHECK-LABEL: hw.module @outer(
// CHECK:         hw.instance "init1" @[[LOOP_INIT]](
// CHECK:         hw.instance "buffer1" @[[LOOP_SLOT]](
// CHECK:         hw.instance "init2" @[[OWN_INIT:handshake_init_[0-9]+]](
// CHECK:         hw.instance "buffer2" @[[OWN_SLOT:handshake_buffer_[0-9]+]](
// CHECK-DAG: hw.module.extern @[[LOOP_INIT]]({{.*}}hw.parameters = {DATA_TYPE = !handshake.channel<i8>, INITIAL_VALUE = "5", INIT_VALUE = 5 : i8, STATE_LOOP = 1 : ui32}}
// CHECK-DAG: hw.module.extern @[[LOOP_SLOT]]({{.*}}NUM_SLOTS = 1 : ui32, STATE_LOOP = 1 : ui32}}
// CHECK-DAG: hw.module.extern @[[OWN_INIT]]({{.*}}hw.parameters = {DATA_TYPE = !handshake.channel<i8>, INITIAL_VALUE = "5", INIT_VALUE = 5 : i8}}
// CHECK-DAG: hw.module.extern @[[OWN_SLOT]]({{.*}}NUM_SLOTS = 1 : ui32}}
handshake.func @inner(%d: !handshake.channel<i8>, ...) -> (!handshake.channel<i8>)
    attributes {argNames = ["d"], resNames = ["q"]} {
  %b = bundle %c, %next : _ to <i8>
  %i = init %b {handshake.name = "init0", hw.parameters = {INIT_VALUE = 5 : i8}} : <i8>
  %s = buffer %i, bufferType = ONE_SLOT_BREAK_DV, numSlots = 1, dvLatency = 1 {handshake.name = "buffer0"} : <i8>
  %c, %value = unbundle %s : <i8> to _
  %dc, %dd = unbundle %d : <i8> to _
  %next = arith.addi %value, %dd : i8
  %q = bundle %dc, %value : _ to <i8>
  end %q : <i8>
}

handshake.func @outer(%d: !handshake.channel<i8>, ...) -> (!handshake.channel<i8>, !handshake.channel<i8>)
    attributes {argNames = ["d"], resNames = ["q", "r"]} {
  %b = bundle %c, %next : _ to <i8>
  %i = init %b {handshake.name = "init1", hw.parameters = {INIT_VALUE = 5 : i8}} : <i8>
  %s = buffer %i, bufferType = ONE_SLOT_BREAK_DV, numSlots = 1, dvLatency = 1 {handshake.name = "buffer1"} : <i8>
  %c, %value = unbundle %s : <i8> to _
  %d0, %d1 = fork [2] %d : <i8>
  %dc, %dd = unbundle %d0 : <i8> to _
  %next = arith.addi %value, %dd : i8
  %q = bundle %dc, %value : _ to <i8>
  %pi = init %d1 {handshake.name = "init2", hw.parameters = {INIT_VALUE = 5 : i8}} : <i8>
  %ps = buffer %pi, bufferType = ONE_SLOT_BREAK_DV, numSlots = 1, dvLatency = 1 {handshake.name = "buffer2"} : <i8>
  %r = instance @inner(%ps) : (!handshake.channel<i8>) -> (!handshake.channel<i8>)
  end %q, %r : <i8>, <i8>
}
