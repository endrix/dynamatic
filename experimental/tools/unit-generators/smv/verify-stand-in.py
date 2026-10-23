#!/usr/bin/env python3
"""Model-check the `stand_in` SMV model against an INDEPENDENT specification.

`stand_in` answers zero for a producer a `commit` stopped: the units it feeds
must receive exactly one token a round from it, the producer's when it
answered, a zero when it was stopped first. The observer counts, from the
ports alone, the tokens that leave against the rounds that ended (the kills)
and requires the difference to say what the unit owes: one token a round,
real or zero, never both, never none. The environment is the one the round
gives the unit: a producer that answers at most once a round and holds what
it offers until taken (it is reset by the kill, so it may offer again from the
cycle after one), a consumer free to stall, and a kill that never comes while
a token of the unit is offered and not taken (the units it feeds absorb a late
token the cycle it comes, so the round's decision cannot pass meanwhile).

Usage:
    python3 verify-stand-in.py [--bitwidth W] [--checker PATH]
"""
import argparse
import os
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from generators.handshake import stand_in as stand_in_gen  # noqa: E402
from generators.support.utils import ATTR_BITWIDTH, SmvScalarType  # noqa: E402


def observer(w: int) -> str:
    t = SmvScalarType(w)
    Z = t.format_constant(0)
    return f"""
MODULE main
  VAR
  ins : {t};
  iv : boolean;
  kill : boolean;
  rdy : boolean;
  dut : stand_in{w}(ins, iv, kill, rdy);

  -- the producer's token of this round has gone in
  p_sent : boolean;
  -- tokens out less rounds ended: -1 a zero still owed, 0 even, 1 this
  -- round's token out already
  d : -2..2;
  -- the output offered and not taken in the cycle before
  was_offered : boolean;
  was_outs : {t};
  last_iv : boolean;
  last_ins : {t};

  DEFINE
  x_in := iv & dut.ins_ready;
  x_out := dut.outs_valid & rdy;
  step := d + (x_out ? 1 : 0) - (kill ? 1 : 0);

  ASSIGN
  init(p_sent) := FALSE;
  next(p_sent) := kill ? FALSE : (p_sent | x_in);
  init(d) := 0;
  -- saturated, so that the model is total: a wrong unit drives it to the
  -- bound and fails `one` there
  next(d) := case
    step < -2 : -2;
    step > 2 : 2;
    TRUE : step;
  esac;
  init(was_offered) := FALSE;
  next(was_offered) := dut.outs_valid & !rdy;
  init(was_outs) := {Z};
  next(was_outs) := dut.outs;
  init(last_iv) := FALSE;
  next(last_iv) := iv & !dut.ins_ready & !kill;
  init(last_ins) := {Z};
  next(last_ins) := ins;

  -- the producer: one answer a round, held until taken unless reset by a kill
  INVAR p_sent -> !iv
  INVAR last_iv -> (iv & ins = last_ins)
  -- the round: no kill while a token of the unit is offered and not taken
  INVAR kill -> !(dut.outs_valid & !rdy)

  -- ONE TOKEN A ROUND: never two, never none -- the difference is what is
  -- owed, and a zero is owed exactly when the round ended with nothing out.
  INVARSPEC NAME one := d >= -1 & d <= 1
  INVARSPEC NAME owed_iff_short := (d = -1) <-> dut.owe
  INVARSPEC NAME ahead_iff_sent := (d = 1) <-> (p_sent & !dut.owe)
  -- the owed token is a zero, offered from the cycle after the kill on
  INVARSPEC NAME zero := dut.owe -> (dut.outs_valid & dut.outs = {Z})
  -- otherwise the producer's token passes untouched
  INVARSPEC NAME passes := !dut.owe -> (dut.outs_valid = iv & (iv -> dut.outs = ins))
  -- the output keeps the protocol: offered, it stays offered and unchanged
  INVARSPEC NAME held := was_offered -> (dut.outs_valid & dut.outs = was_outs)
"""


def find_checker(explicit):
    for c in (explicit, os.environ.get("NUSMV"), "NuSMV", "nuXmv"):
        if c and shutil.which(c) or (c and os.path.isfile(c) and os.access(c, os.X_OK)):
            return c
    return None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--bitwidth", type=int, default=1)
    ap.add_argument("--checker", default=None)
    args = ap.parse_args()

    model = stand_in_gen.generate_stand_in(
        f"stand_in{args.bitwidth}", {ATTR_BITWIDTH: args.bitwidth})
    text = model + observer(args.bitwidth)

    checker = find_checker(args.checker)
    if not checker:
        print("No NuSMV or nuXmv found; see verify-first.py for a build.",
              file=sys.stderr)
        print(text)
        return 2

    with tempfile.NamedTemporaryFile("w", suffix=".smv", delete=False) as f:
        f.write(text)
        path = f.name
    try:
        out = subprocess.run([checker, path], capture_output=True, text=True).stdout
    finally:
        os.unlink(path)

    specs = [l for l in out.splitlines() if l.startswith("-- invariant")]
    bad = [l for l in specs if "is false" in l]
    for l in specs:
        print(("  FAIL " if "is false" in l else "  ok   ") + l[3:])
    print(f"\n  bitwidth {args.bitwidth}: {len(specs) - len(bad)} of "
          f"{len(specs)} properties hold")
    if not specs:
        print(out, file=sys.stderr)
        return 2
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
