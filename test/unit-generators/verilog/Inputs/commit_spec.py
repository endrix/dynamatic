#!/usr/bin/env python3
"""handshake.commit's kill as an executable reference, in both forms, written
from the op's description (not from the unit), and the vector files of
commit-iverilog.mlir and commit-ghdl.mlir.

  transfer        `kill` in every cycle a token transfers (`ins` valid and
                  `outs` ready), and under reset.
  at_valid        (`kill_at_valid`) `kill` in the FIRST cycle each token is
                  offered, and under reset: not in the later cycles a token
                  waits, nor at its transfer unless that is its first cycle.
                  The next token's first cycle is a kill again, the cycle
                  after a transfer included.

Either way the channel is a wire: `outs_valid` is `ins_valid`, `outs` is
`ins`, `ins_ready` is `outs_ready`.

The stimulus keeps the protocol: a token is held, valid and payload, until
taken, and a reset drops it (nothing is offered under reset). It has bubbles,
stalls of several cycles, tokens taken the cycle they come and tokens back to
back. One line a cycle: rst, ins_valid, ins, outs_ready, then the expected
outs_valid, outs, ins_ready and kill.

Usage: commit_spec.py transfer|at_valid [cycles [seed]] > vectors.txt
"""
import random
import sys


def vectors(form, cycles, seed):
    rng = random.Random(seed)
    lines, seen = [], {"first": 0, "waits": 0, "back_to_back": 0, "resets": 0,
                       "taken_at_once": 0}
    offering, payload = False, 0
    taken_last = False
    for t in range(cycles):
        rst = t < 2 or rng.random() < 0.03
        if rst:
            offering = False
        elif not offering and rng.random() < 0.6:
            offering, payload = True, rng.randrange(8)
            seen["back_to_back"] += int(taken_last)
        ready = rng.random() < 0.45
        valid = offering and not rst
        transfer = valid and ready
        # A token's first cycle: offered now, and not offered and left
        # untaken in the cycle before (the same token, then).
        first = valid and not waiting_before if t else valid
        if form == "transfer":
            kill = rst or transfer
        else:
            kill = rst or first
        seen["first"] += int(first)
        seen["waits"] += int(valid and not first)
        seen["taken_at_once"] += int(first and transfer)
        seen["resets"] += int(rst)
        lines.append(f"{int(rst)} {int(valid)} {payload if valid else 0} {int(ready)} "
                     f"{int(valid)} {payload if valid else 0} {int(ready)} {int(kill)}")
        waiting_before = valid and not ready
        taken_last = transfer
        if transfer:
            offering = False
    return lines, seen


if __name__ == "__main__":
    form = sys.argv[1]
    assert form in ("transfer", "at_valid"), form
    cycles = int(sys.argv[2]) if len(sys.argv) > 2 else 200
    seed = int(sys.argv[3]) if len(sys.argv) > 3 else 3
    lines, seen = vectors(form, cycles, seed)
    print(f"# handshake.commit ({form}), 3-bit payload: the requirement's outputs")
    print("# (commit_spec.py), one a cycle. Columns: rst, ins_valid, ins, outs_ready,")
    print("# then the expected outs_valid, outs, ins_ready and kill. Cycles where: " +
          ", ".join(f"{k} {v}" for k, v in sorted(seen.items())))
    print("\n".join(lines))
