#!/usr/bin/env python3
"""handshake.race's requirement as an executable reference, written from the
op's description (not from the unit), and a vector file of random rounds for
race-ghdl.mlir and race-iverilog.mlir.

The shape: P(t, F(g1(a, not b), P(g2(c), g3(d, b)))) over one token t and
four flags a b c d, a 4-bit decision:
  candidate 0  the token t                            after -
  candidate 1  payload 1, a true and b false          after 0
  candidate 2  payload 2, c true                      after 0
  candidate 3  payload 4, d true and b true           after 0, 2
CANDIDATES "t0/p1:f0:u1:a0/p2:f2:a0/p4:f3,1:a0,2". Candidates 1 and 2 are
incomparable (F), so a tie between them goes to 1; 3 waits for 2's refusal and
t's; flag b is read by two candidates, once negated.

Usage: race_spec.py [cycles] > race-vectors.txt
"""
import random
import sys

CANDS = [
    {"token": 0, "flags": [], "unless": [], "after": []},
    {"payload": 1, "flags": [0], "unless": [1], "after": [0]},
    {"payload": 2, "flags": [2], "unless": [], "after": [0]},
    {"payload": 4, "flags": [3, 1], "unless": [], "after": [0, 2]},
]
NT, NF, W = 1, 4, 4
ENCODING = "t0/p1:f0:u1:a0/p2:f2:a0/p4:f3,1:a0,2"


TIES = [0]


def decide(arrived, value):
    """The answer the arrived inputs determine: a payload (the lowest-index
    winner's), 0 (every candidate refused), or None (not yet). Inputs are
    numbered tokens first, then flags; `value` a token's payload or a flag's
    bit."""
    def flag(f):
        i = NT + f
        return None if not arrived[i] else bool(value[i])

    enabled, refused = [], []
    for c in CANDS:
        lits = [flag(f) for f in c["flags"]] + \
               [None if flag(f) is None else not flag(f) for f in c["unless"]]
        if "token" in c:
            t = c["token"]
            lits.append(None if not arrived[t] else value[t] != 0)
        enabled.append(all(l is True for l in lits))
        refused.append(any(l is False for l in lits))
    winners = [k for k, c in enumerate(CANDS)
               if enabled[k] and all(refused[j] for j in c["after"])]
    if winners:
        TIES[0] = len(winners) > 1
        c = CANDS[winners[0]]
        return value[c["token"]] if "token" in c else c["payload"]
    if all(refused):
        return 0
    return None


class Spec:
    """The round as an observer sees it from the ports' transfers."""

    def __init__(s):
        n = NT + NF
        s.got = [False] * n      # gave this round's token
        s.val = [0] * n          # with this value
        s.answered = False       # this round's answer was taken
        s.held = None            # an answer offered and not taken

    def step(s, v, d, rdy):
        n = NT + NF
        now = [v[i] and not s.got[i] for i in range(n)]
        arrived = [s.got[i] or now[i] for i in range(n)]
        value = [s.val[i] if s.got[i] else d[i] for i in range(n)]
        allin = all(arrived)
        TIES[0] = False
        decided = decide(arrived, value)
        tie = TIES[0]
        answer = s.held if s.held is not None else decided
        valid_n = (not s.answered) and answer is not None
        closes = allin and (s.answered or (valid_n and rdy))
        ready = [(not s.got[i]) or closes for i in range(n)]
        nxt = [v[i] and s.got[i] and closes for i in range(n)]
        early_answer = decide(nxt, d) if s.answered and closes else None
        early = early_answer is not None
        ov = valid_n or early
        o = answer if valid_n else (early_answer if early else 0)
        x_out = ov and rdy
        if closes:
            s.got = nxt
            s.val = [d[i] if nxt[i] else 0 for i in range(n)]
            s.answered = early and x_out
            s.held = early_answer if (early and not x_out) else None
        else:
            for i in range(n):
                if now[i]:
                    s.got[i] = True
                    s.val[i] = d[i]
            if valid_n and not x_out:
                s.held = answer
            if x_out:
                s.answered = True
                s.held = None
        return ready, int(ov), o, {"decided_early": valid_n and not allin,
                                   "early_next": early, "stall": ov and not rdy,
                                   "zero_early": valid_n and answer == 0 and not allin,
                                   "dominated": valid_n and answer in (1, 2, 4),
                                   "tie": valid_n and s.held is None and tie}


def vectors(cycles, seed):
    random.seed(seed)
    n = NT + NF
    spec = Spec()
    v = [False] * n
    d = [0] * n
    lines, seen = [], {}
    for _ in range(cycles):
        for i in range(n):
            if not v[i] and random.random() < 0.5:
                v[i] = True
                d[i] = random.choice([0, 8]) if i < NT else random.randrange(2)
        rdy = random.random() < 0.7
        ready, ov, o, ev = spec.step(v, d, rdy)
        for key, hit in ev.items():
            seen[key] = seen.get(key, 0) + int(bool(hit))
        lines.append(" ".join(str(int(x)) for x in v) + " " + " ".join(map(str, d)) +
                     f" {int(rdy)} {ov} {o if ov else 0} " +
                     " ".join(str(int(r)) for r in ready))
        for i in range(n):
            if v[i] and ready[i]:
                v[i] = False
    return lines, seen


if __name__ == "__main__":
    cycles = int(sys.argv[1]) if len(sys.argv) > 1 else 600
    lines, seen = vectors(cycles, 7)
    print(f"# handshake.race {ENCODING}: one token (4 bits) and four flags,")
    print("# random rounds, one a line, expected from the requirement")
    print("# (race_spec.py). Columns: the five valids (token, then flags a b c d),")
    print("# the five values, outs_ready, then the expected outs_valid, outs")
    print("# (checked only when outs_valid is expected) and the five readies.")
    print("# Each input's token is held until taken. Cycles where: " +
          ", ".join(f"{k} {v}" for k, v in sorted(seen.items())))
    print("\n".join(lines))
