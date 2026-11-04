// The truth table of a phi input's sum of paths has at most 24 conditions
// (BoolExpression::MAX_TRUTH_TABLE_VARIABLES).
//
// RUN: dynamatic-opt --force-memory-interface=force-mc=true --ftd-lower-cf-to-handshake --split-input-file --verify-diagnostics %s | FileCheck %s

// x is taken when 25 conditions all hold, y when one fails: the inputs are
// reached on paths over 25 conditions, and the pass fails with an error on the
// argument before any table is built (2^25 rows).

// expected-error @+1 {{failed to legalize operation 'func.func'}}
func.func @and25(%c0: i1, %c1: i1, %c2: i1, %c3: i1, %c4: i1, %c5: i1, %c6: i1, %c7: i1, %c8: i1, %c9: i1, %c10: i1, %c11: i1, %c12: i1, %c13: i1, %c14: i1, %c15: i1, %c16: i1, %c17: i1, %c18: i1, %c19: i1, %c20: i1, %c21: i1, %c22: i1, %c23: i1, %c24: i1, %x: i64, %y: i64) -> i64 {
  cf.cond_br %c0, ^b1, ^z
^b1:
  cf.cond_br %c1, ^b2, ^z
^b2:
  cf.cond_br %c2, ^b3, ^z
^b3:
  cf.cond_br %c3, ^b4, ^z
^b4:
  cf.cond_br %c4, ^b5, ^z
^b5:
  cf.cond_br %c5, ^b6, ^z
^b6:
  cf.cond_br %c6, ^b7, ^z
^b7:
  cf.cond_br %c7, ^b8, ^z
^b8:
  cf.cond_br %c8, ^b9, ^z
^b9:
  cf.cond_br %c9, ^b10, ^z
^b10:
  cf.cond_br %c10, ^b11, ^z
^b11:
  cf.cond_br %c11, ^b12, ^z
^b12:
  cf.cond_br %c12, ^b13, ^z
^b13:
  cf.cond_br %c13, ^b14, ^z
^b14:
  cf.cond_br %c14, ^b15, ^z
^b15:
  cf.cond_br %c15, ^b16, ^z
^b16:
  cf.cond_br %c16, ^b17, ^z
^b17:
  cf.cond_br %c17, ^b18, ^z
^b18:
  cf.cond_br %c18, ^b19, ^z
^b19:
  cf.cond_br %c19, ^b20, ^z
^b20:
  cf.cond_br %c20, ^b21, ^z
^b21:
  cf.cond_br %c21, ^b22, ^z
^b22:
  cf.cond_br %c22, ^b23, ^z
^b23:
  cf.cond_br %c23, ^b24, ^z
^b24:
  cf.cond_br %c24, ^s, ^z
^s:
  cf.br ^p(%x : i64)
^z:
  cf.br ^p(%y : i64)
// expected-error @+1 {{fast token delivery cannot build the gamma tree of this block argument: the paths to one of its inputs carry 25 branch conditions, more than the 24 a truth table of their sum is built over}}
^p(%v: i64):
  return %v : i64
}

// -----

// x is reached through arm A, an AND chain of 11 conditions whose false edges
// send y, or through arm B or C, chains of 6 and 5 reconverging diamonds. Its
// function needs 14 conditions (e, c0, c1 and arm A's) and its paths carry 25.
// Arm A's sum is minimized at the first path of arm B and keeps 13; the first
// path of arm C would take the sum past 24 with arm B's conditions, which
// cancel, still in it, so the sum is minimized there and arm B's leave it.
// The input lowers.
//
// CHECK-LABEL: handshake.func @gap(
// CHECK: mux {{.*}}ftd.GAMMA

func.func @gap(%e: i1, %c0: i1, %c1: i1, %a0: i1, %a1: i1, %a2: i1, %a3: i1, %a4: i1, %a5: i1, %a6: i1, %a7: i1, %a8: i1, %a9: i1, %a10: i1, %b0: i1, %b1: i1, %b2: i1, %b3: i1, %b4: i1, %b5: i1, %d0: i1, %d1: i1, %d2: i1, %d3: i1, %d4: i1, %x: i64, %y: i64) -> i64 {
  cf.cond_br %e, ^R, ^Z
^R:
  cf.cond_br %c0, ^A0, ^BC
^BC:
  cf.cond_br %c1, ^B0, ^D0
^A0:
  cf.cond_br %a0, ^A1, ^Z
^A1:
  cf.cond_br %a1, ^A2, ^Z
^A2:
  cf.cond_br %a2, ^A3, ^Z
^A3:
  cf.cond_br %a3, ^A4, ^Z
^A4:
  cf.cond_br %a4, ^A5, ^Z
^A5:
  cf.cond_br %a5, ^A6, ^Z
^A6:
  cf.cond_br %a6, ^A7, ^Z
^A7:
  cf.cond_br %a7, ^A8, ^Z
^A8:
  cf.cond_br %a8, ^A9, ^Z
^A9:
  cf.cond_br %a9, ^A10, ^Z
^A10:
  cf.cond_br %a10, ^S, ^Z
^B0:
  cf.cond_br %b0, ^B0t, ^B0f
^B0t:
  cf.br ^B1
^B0f:
  cf.br ^B1
^B1:
  cf.cond_br %b1, ^B1t, ^B1f
^B1t:
  cf.br ^B2
^B1f:
  cf.br ^B2
^B2:
  cf.cond_br %b2, ^B2t, ^B2f
^B2t:
  cf.br ^B3
^B2f:
  cf.br ^B3
^B3:
  cf.cond_br %b3, ^B3t, ^B3f
^B3t:
  cf.br ^B4
^B3f:
  cf.br ^B4
^B4:
  cf.cond_br %b4, ^B4t, ^B4f
^B4t:
  cf.br ^B5
^B4f:
  cf.br ^B5
^B5:
  cf.cond_br %b5, ^B5t, ^B5f
^B5t:
  cf.br ^S
^B5f:
  cf.br ^S
^D0:
  cf.cond_br %d0, ^D0t, ^D0f
^D0t:
  cf.br ^D1
^D0f:
  cf.br ^D1
^D1:
  cf.cond_br %d1, ^D1t, ^D1f
^D1t:
  cf.br ^D2
^D1f:
  cf.br ^D2
^D2:
  cf.cond_br %d2, ^D2t, ^D2f
^D2t:
  cf.br ^D3
^D2f:
  cf.br ^D3
^D3:
  cf.cond_br %d3, ^D3t, ^D3f
^D3t:
  cf.br ^D4
^D3f:
  cf.br ^D4
^D4:
  cf.cond_br %d4, ^D4t, ^D4f
^D4t:
  cf.br ^S
^D4f:
  cf.br ^S
^S:
  cf.br ^P(%x : i64)
^Z:
  cf.br ^P(%y : i64)
^P(%v: i64):
  return %v : i64
}
