#!/usr/bin/env python3
"""handshake.race's requirement as an executable reference, written from the
op's description (not from the unit), and a vector file of random rounds for
race-ghdl.mlir and race-iverilog.mlir (shape `nest`), race-alt-ghdl.mlir and
race-alt-iverilog.mlir (shape `alt`). Both shapes have one 5-bit token t and
four flags a b c d, so one testbench reads either file.

`nest`: P(t, F(g1(a, not b), P(g2(c), P(g0(a, not a), g3(d, b))))):
  candidate 0  the token t (0 or 8)                   after -
  candidate 1  payload 1, a true and b false          after 0
  candidate 2  payload 2, c true                      after 0
  candidate 3  payload 16, a true and a false         after 0, 2
  candidate 4  payload 4, d true and b true           after 0, 2, 3
CANDIDATES "t0/p1:f0:u1:a0/p2:f2:a0/p16:f0:u0:a0,2/p4:f3,1:a0,2,3".
Candidates 1 and 2 are incomparable (F), so a tie between them goes to 1; 4
waits for the refusals of 0, 2 and 3; flag b is read by two candidates, once
negated. Candidate 3 is a guard over P and not P (formation's shared flag
both ways): never enabled, refused once a arrives, so 4 waits for a too.

`alt`: F(P(h(b, not c), S), P(k(c, d), S)) with S = P(t, g(a)) read in both
places (a shared subtree, synthesis's W(y) through a fork), taken in once a
place -- so t is read by two candidates and g's payload is two:
  candidate 0  payload 16, b true and c false (h)     after -
  candidate 1  the token t (0 or 8)                   after 0
  candidate 2  payload 1, a true (g)                  after 0, 1
  candidate 3  payload 2, c true and d true (k)       after -
  candidate 4  the token t again                      after 3
  candidate 5  payload 1 again (g)                    after 3, 4
CANDIDATES "p16:f1:u2/t0:a0/p1:f0:a0,1/p2:f2,3/t0:a3/p1:f0:a3,4".
S's answer wins once h OR k is refused: candidates 4 and 5 are the
ALTERNATIVES of 1 and 2 (the same answer after other candidates), and win
alone when k is refused before h is decided (`later_alternative`).

Usage: race_spec.py [cycles [seed [shape]]] > race-vectors.txt
"""
import random
import sys

SHAPES = {
    "nest": {
        "cands": [
            {"token": 0, "flags": [], "unless": [], "after": []},
            {"payload": 1, "flags": [0], "unless": [1], "after": [0]},
            {"payload": 2, "flags": [2], "unless": [], "after": [0]},
            {"payload": 16, "flags": [0], "unless": [0], "after": [0, 2]},
            {"payload": 4, "flags": [3, 1], "unless": [], "after": [0, 2, 3]},
        ],
        "encoding": "t0/p1:f0:u1:a0/p2:f2:a0/p16:f0:u0:a0,2/p4:f3,1:a0,2,3",
        # the guard over a and not a
        "dead": 3,
        # the answers of candidates after another
        "dominated": (1, 2, 4),
        # the seed of the checked-in vectors: one whose stalls change an
        # answer (the "held" count), so that a unit without the hold fails
        "seed": 5,
    },
    "alt": {
        "cands": [
            {"payload": 16, "flags": [1], "unless": [2], "after": []},
            {"token": 0, "flags": [], "unless": [], "after": [0]},
            {"payload": 1, "flags": [0], "unless": [], "after": [0, 1]},
            {"payload": 2, "flags": [2, 3], "unless": [], "after": []},
            {"token": 0, "flags": [], "unless": [], "after": [3]},
            {"payload": 1, "flags": [0], "unless": [], "after": [3, 4]},
        ],
        "encoding": "p16:f1:u2/t0:a0/p1:f0:a0,1/p2:f2,3/t0:a3/p1:f0:a3,4",
        "dead": None,
        "dominated": (1, 8),
        # one whose stalls change an answer too, and in which a later
        # alternative answers alone most often
        "seed": 7,
    },
}
NT, NF, W = 1, 4, 5
SHAPE = SHAPES["nest"]
CANDS = SHAPE["cands"]
ENCODING = SHAPE["encoding"]
DEAD = SHAPE["dead"]


def use(shape):
    global SHAPE, CANDS, ENCODING, DEAD
    SHAPE = SHAPES[shape]
    CANDS = SHAPE["cands"]
    ENCODING = SHAPE["encoding"]
    DEAD = SHAPE["dead"]


TIES = [0]
# the lowest-index winner an alternative of an earlier candidate (which does
# not win), and two alternatives of one answer winning together
ALTS = [False, False]


def same_answer(c, d):
    return c.get("token", c.get("payload")) == d.get("token", d.get("payload")) \
        and ("token" in c) == ("token" in d)


def terms(arrived, value):
    """Each candidate's ENABLED and REFUSED over the arrived inputs: every
    literal of it true, or one false. Inputs are numbered tokens first, then
    flags; `value` a token's payload or a flag's bit."""
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
    return enabled, refused


def waits_on_dead(arrived, value):
    """A candidate after the dead guard waits for it alone: enabled, every
    other predecessor refused, the dead guard not yet (its flag not in)."""
    enabled, refused = terms(arrived, value)
    return not refused[DEAD] and any(
        enabled[k] and DEAD in c["after"] and
        all(refused[j] for j in c["after"] if j != DEAD)
        for k, c in enumerate(CANDS))


def decide(arrived, value):
    """The answer the arrived inputs determine: a payload (the lowest-index
    winner's), 0 (every candidate refused), or None (not yet)."""
    enabled, refused = terms(arrived, value)
    winners = [k for k, c in enumerate(CANDS)
               if enabled[k] and all(refused[j] for j in c["after"])]
    if winners:
        TIES[0] = len(winners) > 1
        c = CANDS[winners[0]]
        ALTS[0] = any(same_answer(CANDS[j], c) for j in range(winners[0]))
        ALTS[1] = any(same_answer(CANDS[j], CANDS[k])
                      for k in winners for j in winners if j < k)
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
        ALTS[0] = ALTS[1] = False
        decided = decide(arrived, value)
        tie = TIES[0]
        later_alt, together = ALTS
        # the hold matters: the answer offered under a stall is not what the
        # record decides now (a winner of lower index came in since)
        held = s.held is not None and decided != s.held
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
        events = {"decided_early": valid_n and not allin,
                  "early_next": early, "stall": ov and not rdy,
                  "zero_early": valid_n and answer == 0 and not allin,
                  "dominated": valid_n and answer in SHAPE["dominated"],
                  "tie": valid_n and s.held is None and tie,
                  "held": held}
        if DEAD is not None:
            events["dead_waits"] = waits_on_dead(arrived, value)
        if any(same_answer(c, d) for k, c in enumerate(CANDS) for d in CANDS[:k]):
            fresh = valid_n and s.held is None
            events["later_alternative"] = fresh and later_alt
            events["alternatives_together"] = fresh and together
        return ready, int(ov), o, events


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
    if len(sys.argv) > 3:
        use(sys.argv[3])
    seed = int(sys.argv[2]) if len(sys.argv) > 2 else SHAPE["seed"]
    lines, seen = vectors(cycles, seed)
    print(f"# handshake.race {ENCODING}: one token (5 bits) and four flags,")
    print("# random rounds, one a line, expected from the requirement")
    print("# (race_spec.py). Columns: the five valids (token, then flags a b c d),")
    print("# the five values, outs_ready, then the expected outs_valid, outs")
    print("# (checked only when outs_valid is expected) and the five readies.")
    print("# Each input's token is held until taken. Cycles where: " +
          ", ".join(f"{k} {v}" for k, v in sorted(seen.items())))
    print("\n".join(lines))
