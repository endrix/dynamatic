// A block argument whose inputs the GSA analysis cannot expand into a tree of
// gammas fails the pass with an error on the argument.
//
// RUN: not dynamatic-opt --force-memory-interface=force-mc=true --ftd-lower-cf-to-handshake --split-input-file %s 2>&1 | FileCheck %s

// A multi-way branch: its edges carry no condition, so no condition tells the
// two values of ^j apart.
//
// CHECK: :[[@LINE+10]]:4: error: fast token delivery cannot build the gamma tree of this block argument: no branch condition tells its inputs apart
func.func @switch(%v: i32, %x: i64, %y: i64) -> i64 {
  cf.switch %v : i32, [
    default: ^a,
    1: ^b
  ]
^a:
  cf.br ^j(%x : i64)
^b:
  cf.br ^j(%y : i64)
^j(%l: i64):
  return %l : i64
}

// -----

// An irreducible cycle, entered on both of its blocks.
//
// CHECK: :[[@LINE+12]]:4: error: fast token delivery cannot build the gamma tree of this block argument: a branch condition tells only some of its inputs apart
func.func @irreducible(%p: i1, %n: i32, %x: i32) -> i32 {
  %c1 = arith.constant 1 : i32
  cf.cond_br %p, ^a(%x : i32), ^b(%x : i32)
^a(%u: i32):
  %u2 = arith.addi %u, %c1 : i32
  %ca = arith.cmpi slt, %u2, %n : i32
  cf.cond_br %ca, ^b(%u2 : i32), ^e(%u2 : i32)
^b(%v: i32):
  %v2 = arith.addi %v, %c1 : i32
  %cb = arith.cmpi slt, %v2, %n : i32
  cf.cond_br %cb, ^a(%v2 : i32), ^e(%v2 : i32)
^e(%r: i32):
  return %r : i32
}
