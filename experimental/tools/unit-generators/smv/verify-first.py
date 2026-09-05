#!/usr/bin/env python3
"""Model-check the `first` SMV model against an INDEPENDENT specification.

`test.sh` checks that a generated model PARSES. This checks that `first` means
what it is supposed to mean, which for an arbiter is the whole question.

The specification is written in an observer module from the requirement, not
from the model, so the check is not circular: the observer remembers, by
itself, the first payload to arrive carrying an action in the current round,
and the unit is required to emit exactly that.

Usage:
    python3 verify-first.py [--size N] [--bitwidth W] [--checker PATH]

`--checker` defaults to $NUSMV, then NuSMV, then nuXmv on PATH. NuSMV is
LGPL and builds from source on macOS and Linux alike:

    git clone https://github.com/ETHZ-DYNAMO/NuSMV-2.7.0 nusmv
    cd nusmv && meson setup build && meson compile -C build

(the bundled build.sh forces `-static`, which macOS does not support; a plain
`meson setup build` is what works there.)
"""
import argparse
import os
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from generators.handshake import first as first_gen  # noqa: E402
from generators.support.utils import ATTR_SIZE, ATTR_BITWIDTH  # noqa: E402


def observer(n: int, w: int) -> str:
    """The specification, and the free environment that exercises it."""
    Z = f"0ud{w}_0"
    nl = "\n"
    return f"""
MODULE main
  VAR
{nl.join(f"  i{k} : unsigned word [{w}];" for k in range(n))}
{nl.join(f"  v{k} : boolean;" for k in range(n))}
  rdy : boolean;
  dut : first{n}({", ".join(f"i{k}" for k in range(n))}, \
{", ".join(f"v{k}" for k in range(n))}, rdy);

  -- The observer's own memory of the round. Nothing here reads the unit's
  -- answer; it derives what the answer MUST be.
  spec_set    : boolean;
  spec_winner : unsigned word [{w}];

  DEFINE
  -- An input carries an action when it is being taken and is not the reserved
  -- "nothing selected" zero.
{nl.join(f"  c{k} := v{k} & !dut.seen_{k} & i{k} != {Z};" for k in range(n))}
  carried := {" | ".join(f"c{k}" for k in range(n))};
  arriving := case
{nl.join(f"    c{k} : i{k};" for k in range(n))}
    TRUE : {Z};
  esac;

  ASSIGN
  init(spec_set) := FALSE;
  next(spec_set) := dut.done ? FALSE : (spec_set | carried);
  init(spec_winner) := {Z};
  next(spec_winner) := dut.done ? {Z} : ((!spec_set & carried) ? arriving : spec_winner);

  -- SOUNDNESS: it emits the first payload that arrived carrying an action.
  CTLSPEC AG ((dut.outs_valid & spec_set) -> dut.outs = spec_winner)
  -- It answers "nothing selected" only when nothing has carried one.
  CTLSPEC AG ((dut.outs_valid & !spec_set & !carried) -> dut.outs = {Z})
  -- It never invents a payload no input offered this round.
  CTLSPEC AG (dut.outs_valid -> (dut.outs = {Z} | dut.outs = spec_winner | dut.outs = arriving))
  -- At most one emission per round.
  CTLSPEC AG (dut.emitted -> !dut.outs_valid)
  -- FULL CONSUMPTION: a round closes only with every input having given a
  -- token, and closing resets all of them together.
  CTLSPEC AG (dut.done -> ({" & ".join(f"dut.seen_next_{k}" for k in range(n))}))
  CTLSPEC AG (dut.done -> AX ({" & ".join(
      [f"!dut.seen_{k}" for k in range(n)] + ["!dut.has_win", "!dut.emitted"])}))
  -- An input that has given its token is not ready again until the round
  -- closes. This is what removes the need for a round-start signal.
{nl.join(f"  CTLSPEC AG (dut.seen_{k} -> !dut.ins_{k}_ready)" for k in range(n))}
  -- NO DEADLOCK: an emission stays reachable from every reachable state.
  CTLSPEC AG EF dut.outs_valid
"""


def find_checker(explicit):
    for c in (explicit, os.environ.get("NUSMV"), "NuSMV", "nuXmv"):
        if c and shutil.which(c) or (c and os.path.isfile(c) and os.access(c, os.X_OK)):
            return c
    return None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--size", type=int, default=4)
    ap.add_argument("--bitwidth", type=int, default=3)
    ap.add_argument("--checker", default=None)
    args = ap.parse_args()

    model = first_gen.generate_first(
        f"first{args.size}",
        {ATTR_SIZE: args.size, ATTR_BITWIDTH: args.bitwidth})
    text = model + observer(args.size, args.bitwidth)

    checker = find_checker(args.checker)
    if not checker:
        print("No NuSMV or nuXmv found; see this file's docstring for a build.",
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

    specs = [l for l in out.splitlines() if l.startswith("-- specification")]
    bad = [l for l in specs if "is false" in l]
    for l in specs:
        print(("  FAIL " if "is false" in l else "  ok   ") + l[len("-- specification "):])
    print(f"\n  size {args.size}, bitwidth {args.bitwidth}: "
          f"{len(specs) - len(bad)} of {len(specs)} properties hold")
    if not specs:
        print(out, file=sys.stderr)
        return 2
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
