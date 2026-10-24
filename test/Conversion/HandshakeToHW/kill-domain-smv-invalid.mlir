// RUN: rm -rf %t && split-file %s %t
// RUN: dynamatic-opt %t/instance.mlir --lower-handshake-to-hw > %t/instance.hw
// RUN: not export-rtl %t/instance.hw %t/instance %dynamatic_src_root/data/rtl-config-smv.json --dynamatic-path %dynamatic_src_root --hdl smv 2>&1 | FileCheck %s --check-prefix=INSTANCE
// RUN: dynamatic-opt %t/no-entry.mlir --lower-handshake-to-hw > %t/no-entry.hw
// RUN: not export-rtl %t/no-entry.hw %t/no-entry %dynamatic_src_root/data/rtl-config-smv.json --dynamatic-path %dynamatic_src_root --hdl smv 2>&1 | FileCheck %s --check-prefix=NO-ENTRY

// THE SMV EXPORT REFUSES A KILL DOMAIN IT CANNOT MODEL, rather than write a
// model NuSMV rejects or one that cannot be reset.
//
// A module instance in a kill domain is reset by the commit's kill, and every
// unit inside it with it: the module's own SMV takes no reset, so the body is
// to be abstracted before it reaches SMV.
//
// A unit of a domain is modelled by its component's KILL_RESET entry, which
// takes the kill as its last parameter. A unit kind with no such entry (here
// an `addi`, which holds nothing, marked by hand) would match the plain entry,
// whose module takes one parameter fewer than the instance passes.

// INSTANCE: error: is reset by a commit's kill, and SMV has no model of a module whose units are reset by a wire of the module around it: abstract its body
// NO-ENTRY: error: is in a kill domain (reset by a commit's kill), and the SMV model it matches ('handshake.addi') takes no reset: add a KILL_RESET entry for it to the SMV configuration

//--- instance.mlir
handshake.func @body(%a: !handshake.channel<i1>, ...) -> (!handshake.channel<i1>)
    attributes {argNames = ["a"], resNames = ["out0"]} {
  %b = buffer %a, bufferType = ONE_SLOT_BREAK_R, numSlots = 1, dvLatency = 0 : <i1>
  end %b : <i1>
}
handshake.func @top(%a: !handshake.channel<i1>, %d: !handshake.channel<i3>, ...)
    -> (!handshake.channel<i1>, !handshake.channel<i3>)
    attributes {argNames = ["a", "d"], resNames = ["out0", "out1"]} {
  %r = instance @body(%a) {handshake.kill_domain = 0 : ui32} : (!handshake.channel<i1>) -> (!handshake.channel<i1>)
  %out, %kill = commit %d : <i3>
  %f = stand_in %r, %kill : <i1>
  end %f, %out : <i1>, <i3>
}

//--- no-entry.mlir
handshake.func @sum(%a: !handshake.channel<i2>, %b: !handshake.channel<i2>, %d: !handshake.channel<i3>, ...)
    -> (!handshake.channel<i2>, !handshake.channel<i3>)
    attributes {argNames = ["a", "b", "d"], resNames = ["flag", "dec"]} {
  %la = buffer %a, bufferType = ONE_SLOT_BREAK_R, numSlots = 1, dvLatency = 0 {handshake.kill_domain = 0 : ui32} : <i2>
  %lb = buffer %b, bufferType = ONE_SLOT_BREAK_R, numSlots = 1, dvLatency = 0 {handshake.kill_domain = 0 : ui32} : <i2>
  %s = addi %la, %lb {handshake.kill_domain = 0 : ui32} : <i2>
  %out, %kill = commit %d : <i3>
  %f = stand_in %s, %kill : <i2>
  end %f, %out : <i2>, <i3>
}
