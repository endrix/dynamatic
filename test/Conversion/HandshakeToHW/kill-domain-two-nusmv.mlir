// REQUIRES: nusmv
// RUN: rm -rf %t && split-file %s %t
// RUN: dynamatic-opt %t/two.mlir --lower-handshake-to-hw > %t/two.hw
// RUN: export-rtl %t/two.hw %t/out %dynamatic_src_root/data/rtl-config-smv.json --dynamatic-path %dynamatic_src_root --hdl smv
// RUN: cd %t/out && grep -hv '^#include' handshake_*.smv mem_to_bram_*.smv two.smv %t/main.smv > %t/all.smv
// RUN: NuSMV %t/all.smv | FileCheck %s

// TWO KILL DOMAINS, one commit each, exported to SMV and model-checked under
// free inputs: the circuit of kill-domain-two.mlir with its predicate's body
// left out (SMV takes no module instance in a domain, kill-domain-smv-invalid)
// and a slot the placer put after domain 0's latch instead. Each unit's model
// takes its own domain's commit's kill as its reset: the step after commit 0's
// transfer domain 0 is empty, after commit 1's domain 1, and a token the other
// domain's latch held, its reader not ready, is still there.

// CHECK-DAG: -- invariant (was_k0 -> (!u.buffer0.full & !u.buffer1.outs_valid_i))  is true
// CHECK-DAG: -- invariant (was_k1 -> !u.buffer2.full)  is true
// CHECK-DAG: -- invariant (((was_k1 & !was_k0) & held0) -> u.buffer0.full)  is true
// CHECK-DAG: -- invariant (((was_k0 & !was_k1) & held1) -> u.buffer2.full)  is true
// CHECK-NOT: is false

//--- two.mlir
handshake.func @two(%a: !handshake.channel<i2>, %c: !handshake.channel<i2>,
                    %d0: !handshake.channel<i3>, %d1: !handshake.channel<i3>,
                    %mem: memref<4xi8>, %memStart: !handshake.control<>,
                    %ctrlEnd: !handshake.control<>, %start: !handshake.control<>, ...)
    -> (!handshake.channel<i2>, !handshake.channel<i1>, !handshake.channel<i3>,
        !handshake.channel<i3>, !handshake.control<>, !handshake.control<>)
    attributes {argNames = ["a", "c", "d0", "d1", "mem", "memStart", "ctrlEnd", "start"],
                resNames = ["flag0", "flag1", "dec0", "dec1", "memEnd", "end"]} {
  %la = buffer %a, bufferType = ONE_SLOT_BREAK_R, numSlots = 1, dvLatency = 0 {handshake.kill_domain = 0 : ui32} : <i2>
  %placed = buffer %la, bufferType = ONE_SLOT_BREAK_DV, numSlots = 1, dvLatency = 1 : <i2>
  %o0, %k0 = commit %d0 : <i3>
  %flag0 = stand_in %placed, %k0 : <i2>
  %lc = buffer %c, bufferType = ONE_SLOT_BREAK_R, numSlots = 1, dvLatency = 0 {handshake.kill_domain = 1 : ui32} : <i2>
  %ldAddr, %ldData = load [%lc] %memData {handshake.bb = 0 : ui32, handshake.kill_domain = 1 : ui32} : <i2>, <i8>, <i2>, <i8>
  %memData, %memEnd = mem_controller [%mem : memref<4xi8>] %memStart (%ldAddr) %ctrlEnd {connectedBlocks = [0 : i32]} : (!handshake.channel<i2>) -> !handshake.channel<i8>
  %w = trunci %ldData {handshake.kill_domain = 1 : ui32} : <i8> to <i1>
  %o1, %k1 = commit %d1 {domain = 1 : ui32} : <i3>
  %flag1 = stand_in %w, %k1 : <i1>
  end %flag0, %flag1, %o0, %o1, %memEnd, %start : <i2>, <i1>, <i3>, <i3>, <>, <>
}

//--- main.smv
MODULE main
  VAR
  a : unsigned word [2];
  a_valid : boolean;
  c : unsigned word [2];
  c_valid : boolean;
  d0 : unsigned word [3];
  d0_valid : boolean;
  d1 : unsigned word [3];
  d1_valid : boolean;
  mem_loadData : unsigned word [8];
  memStart_valid : boolean;
  ctrlEnd_valid : boolean;
  start_valid : boolean;
  flag0_ready : boolean;
  flag1_ready : boolean;
  dec0_ready : boolean;
  dec1_ready : boolean;
  memEnd_ready : boolean;
  end_ready : boolean;
  u : two(self, a, a_valid, c, c_valid, d0, d0_valid, d1, d1_valid, mem_loadData,
          memStart_valid, ctrlEnd_valid, start_valid, flag0_ready, flag1_ready,
          dec0_ready, dec1_ready, memEnd_ready, end_ready);
  was_k0 : boolean;
  was_k1 : boolean;
  held0 : boolean;
  held1 : boolean;
  ASSIGN
  init(was_k0) := FALSE;
  next(was_k0) := u.commit0.kill;
  init(was_k1) := FALSE;
  next(was_k1) := u.commit1.kill;
  init(held0) := FALSE;
  next(held0) := u.buffer0.full & !u.buffer1.ins_ready;
  init(held1) := FALSE;
  next(held1) := u.buffer2.full & !u.load0.addrIn_ready;
  INVARSPEC NAME domain0_reset := was_k0 -> (!u.buffer0.full & !u.buffer1.outs_valid_i)
  INVARSPEC NAME domain1_reset := was_k1 -> !u.buffer2.full
  INVARSPEC NAME domain0_kept := (was_k1 & !was_k0 & held0) -> u.buffer0.full
  INVARSPEC NAME domain1_kept := (was_k0 & !was_k1 & held1) -> u.buffer2.full
