// REQUIRES: ghdl
// RUN: rm -rf %t && mkdir -p %t && cd %t && ghdl -a --std=08 %dynamatic_src_root/data/vhdl/handshake/generic/handshake_queue.vhd %S/Inputs/handshake-queue-tb.vhd && ghdl -e --std=08 tb
// RUN: cd %t && ghdl -r --std=08 tb -gTOKENS=none 2>&1 | FileCheck %s --check-prefix=EMPTY
// RUN: cd %t && ghdl -r --std=08 tb -gTOKENS=11111101,00000111,00101010 2>&1 | FileCheck %s --check-prefix=THREE
// RUN: cd %t && ghdl -r --std=08 tb -gSLOTS=2 -gTOKENS=00000001,00000010 2>&1 | FileCheck %s --check-prefix=FULL
// RUN: cd %t && ghdl -r --std=08 tb -gW=70 -gSLOTS=1 -gTOKENS=0000000000000000000000000000000000000000000000000000000000000000000101 2>&1 | FileCheck %s --check-prefix=WIDE
// RUN: cd %t && for t in 00000001,00000010,00000011 0001 000000001 0000000x 00000001, ,00000001; do \
// RUN:   ! ghdl -r --std=08 tb -gSLOTS=2 -gTOKENS=$t 2>&1 || exit 1; done | FileCheck %s --check-prefix=BAD

// The tokens a generic queue holds at reset are a generic, the string the
// lowering writes: each token's bits at the data width, first out first,
// joined by commas, or "none". From reset the output is valid on the first
// of them, `size` counts them and `space` is the slots left; a token written
// afterwards comes out behind them.

// EMPTY:      after reset: size 0 space 4
// EMPTY-NOT:  token
// EMPTY:      empty: size 0 space 4
// EMPTY-NEXT: written: token 1 size 1

// THREE:      after reset: size 3 space 1
// THREE-NEXT: token 253
// THREE-NEXT: token 7
// THREE-NEXT: token 42
// THREE-NEXT: empty: size 0 space 4
// THREE-NEXT: written: token 1 size 1

// Full at reset: the tail wraps to slot 0, where the next token is written.
// FULL:      after reset: size 2 space 0
// FULL-NEXT: token 1
// FULL-NEXT: token 2
// FULL-NEXT: empty: size 0 space 2
// FULL-NEXT: written: token 1 size 1

// WIDE:      after reset: size 1 space 0
// WIDE-NEXT: token 5

// What the queue could not hold is refused when the design is elaborated:
// more tokens than slots, a token of another width or not in binary, an
// empty token.
// BAD:      handshake_queue: more initial tokens than slots
// BAD:      handshake_queue: INITIAL_TOKENS "0001" has a token narrower than the data
// BAD:      handshake_queue: INITIAL_TOKENS "000000001" has a token wider than the data
// BAD:      handshake_queue: INITIAL_TOKENS "0000000x" has a token that is not binary
// BAD:      handshake_queue: INITIAL_TOKENS "00000001," has a token narrower than the data
// BAD:      handshake_queue: INITIAL_TOKENS ",00000001" has a token narrower than the data
