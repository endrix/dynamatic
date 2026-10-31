#!/usr/bin/env python3
"""Model-check the `commit` SMV model against an INDEPENDENT specification.

A `commit` is a wire on its channel whose `kill` says when the round its token
decides ends. The observer reads the ports alone: the environment offers
tokens that keep the protocol (a token held, valid and payload, until taken;
then the next, or a bubble) to a consumer free to stall. The channel must be
a wire, and the kill:

  transfer (the default)   high exactly in the cycles a token transfers;
  --at-valid               (`kill_at_valid`) high exactly in the FIRST cycle
                           each token is offered: ONE kill a token, at or
                           before its transfer, never in a cycle with no
                           token, and the next token's first cycle a kill
                           again (the cycle after a transfer included).

Usage:
    python3 verify-commit.py [--bitwidth W] [--at-valid] [--checker PATH]
"""
import argparse
import os
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from generators.handshake import commit as commit_gen  # noqa: E402
from generators.support.utils import ATTR_BITWIDTH, SmvScalarType  # noqa: E402


def observer(w: int, at_valid: bool) -> str:
    data = w > 0
    t = SmvScalarType(w) if data else None
    args = ("ins, iv, rdy" if data else "iv, rdy")
    data_vars = f"  ins : {t};\n  last_ins : {t};\n" if data else ""
    data_assign = (f"  init(last_ins) := {t.format_constant(0)};\n"
                   "  next(last_ins) := ins;\n") if data else ""
    data_hold = "  INVAR waited -> ins = last_ins\n" if data else ""
    data_wire = "  INVARSPEC NAME data_wire := dut.outs = ins\n" if data else ""
    if at_valid:
        kill_specs = """  -- the kill in the first cycle of each token, and only then
  INVARSPEC NAME kill_first := dut.kill <-> (iv & !waited)
  -- one kill a token: none before its first cycle (k_tok counts the kills
  -- of the token now offered, this cycle's included), exactly one by its
  -- transfer, so at or before it
  INVARSPEC NAME one_kill := iv -> k_tok = 1
  INVARSPEC NAME no_kill_without_token := dut.kill -> iv
"""
    else:
        kill_specs = """  -- the kill in every cycle a token transfers, and only then
  INVARSPEC NAME kill_transfer := dut.kill <-> (iv & rdy)
"""
    return f"""
MODULE main
  VAR
  iv : boolean;
  rdy : boolean;
{data_vars}  dut : commit{w}({args});
  -- the token now offered was offered and not taken in the cycle before
  waited : boolean;
  -- the kills of the token now offered, before this cycle
  k_before : 0..2;

  DEFINE
  x := iv & rdy;
  k_tok := (waited ? k_before : 0) + (dut.kill ? 1 : 0);

  ASSIGN
  init(waited) := FALSE;
  next(waited) := iv & !rdy;
{data_assign}  init(k_before) := 0;
  next(k_before) := case
    k_tok > 2 : 2;
    TRUE : k_tok;
  esac;

  -- the producer keeps the protocol: a token offered and not taken stays
  INVAR waited -> iv
{data_hold}
  -- a wire on the channel
  INVARSPEC NAME valid_wire := dut.outs_valid = iv
  INVARSPEC NAME ready_wire := dut.ins_ready = rdy
{data_wire}{kill_specs}"""


def find_checker(explicit):
    for c in (explicit, os.environ.get("NUSMV"), "NuSMV", "nuXmv"):
        if c and shutil.which(c) or (c and os.path.isfile(c) and os.access(c, os.X_OK)):
            return c
    return None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--bitwidth", type=int, default=2)
    ap.add_argument("--at-valid", action="store_true")
    ap.add_argument("--checker", default=None)
    args = ap.parse_args()

    model = commit_gen.generate_commit(
        f"commit{args.bitwidth}",
        {ATTR_BITWIDTH: args.bitwidth, "kill_at_valid": int(args.at_valid)})
    text = model + observer(args.bitwidth, args.at_valid)

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
    form = "kill_at_valid" if args.at_valid else "transfer"
    print(f"\n  commit ({form}), bitwidth {args.bitwidth}: "
          f"{len(specs) - len(bad)} of {len(specs)} properties hold")
    if not specs:
        print(out, file=sys.stderr)
        return 2
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
