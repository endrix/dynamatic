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
from generators.support.dependencies import combinational_reads  # noqa: E402


def observer(n: int, w: int) -> str:
    """The specification, and the free environment that exercises it.

    The observer keeps its own record of the round from the transfers it sees
    on the ports -- which inputs have given their token, whether the answer
    has been taken, the first payload to arrive carrying an action -- closes
    the round itself, and requires the unit to answer what that record says,
    at the cycle it says. Nothing here reads the unit's registers.
    """
    Z = f"0ud{w}_0"
    nl = "\n"
    ks = range(n)
    return f"""
MODULE main
  VAR
{nl.join(f"  i{k} : unsigned word [{w}];" for k in ks)}
{nl.join(f"  v{k} : boolean;" for k in ks)}
  rdy : boolean;
  dut : first{n}({", ".join(f"i{k}" for k in ks)}, \
{", ".join(f"v{k}" for k in ks)}, rdy);

  -- The observer's own record of the round.
{nl.join(f"  got{k} : boolean;" for k in ks)}
  answered : boolean;
  spec_set : boolean;
  spec_winner : unsigned word [{w}];
  -- the answer offered and not taken in the cycle before, for the protocol
  was_offered : boolean;
  was_outs : unsigned word [{w}];
  -- the environment holds an offered input until it is taken
{nl.join(f"  last_v{k} : boolean;" for k in ks)}
{nl.join(f"  last_i{k} : unsigned word [{w}];" for k in ks)}

  DEFINE
{nl.join(f"  x{k} := v{k} & dut.ins_{k}_ready;" for k in ks)}
  x_out := dut.outs_valid & rdy;
  -- a transfer is this round's unless the input gave its token already;
  -- then it is the next round's, which the round's last cycle may take
{nl.join(f"  now{k} := x{k} & !got{k};" for k in ks)}
{nl.join(f"  nxt{k} := x{k} & got{k};" for k in ks)}
  all_in := {" & ".join(f"(got{k} | now{k})" for k in ks)};
  -- An input carries an action when its token is taken and is not the
  -- reserved "nothing selected" zero.
{nl.join(f"  c{k} := now{k} & i{k} != {Z};" for k in ks)}
{nl.join(f"  cn{k} := nxt{k} & i{k} != {Z};" for k in ks)}
  carried := {" | ".join(f"c{k}" for k in ks)};
  arriving := case
{nl.join(f"    c{k} : i{k};" for k in ks)}
    TRUE : {Z};
  esac;
  next_carried := {" | ".join(f"cn{k}" for k in ks)};
  next_arriving := case
{nl.join(f"    cn{k} : i{k};" for k in ks)}
    TRUE : {Z};
  esac;
  -- the round closes once every input gave its token and the answer was
  -- taken
  closes := all_in & (answered | x_out);
  -- what the answer must be this round, once there is one
  winner := spec_set ? spec_winner : arriving;

  ASSIGN
{nl.join(f"  init(got{k}) := FALSE;{nl}  next(got{k}) := closes ? nxt{k} : (got{k} | now{k});" for k in ks)}
  -- in a closing cycle whose answer was out before, an answer taken is the
  -- next round's
  init(answered) := FALSE;
  next(answered) := closes ? (answered & x_out) : (answered | x_out);
  init(spec_set) := FALSE;
  next(spec_set) := closes ? next_carried : (spec_set | carried);
  init(spec_winner) := {Z};
  next(spec_winner) := closes ? next_arriving : ((!spec_set & carried) ? arriving : spec_winner);
  init(was_offered) := FALSE;
  next(was_offered) := dut.outs_valid & !rdy;
  init(was_outs) := {Z};
  next(was_outs) := dut.outs;
{nl.join(f"  init(last_v{k}) := FALSE;{nl}  next(last_v{k}) := v{k} & !dut.ins_{k}_ready;" for k in ks)}
{nl.join(f"  init(last_i{k}) := {Z};{nl}  next(last_i{k}) := i{k};" for k in ks)}

  -- a channel's valid is not withdrawn and its data does not change under it
{nl.join(f"  INVAR last_v{k} -> (v{k} & i{k} = last_i{k})" for k in ks)}

  -- SOUNDNESS: it emits the first payload that arrived carrying an action,
  -- or "nothing selected" once every input came without one.
  INVARSPEC NAME sound := (dut.outs_valid & !answered) -> dut.outs = winner
  INVARSPEC NAME nothing_only_at_close := (dut.outs_valid & !answered & dut.outs = {Z}) -> all_in
  -- EARLY: the answer is out the cycle a winner exists, or the cycle the
  -- round's last token came.
  INVARSPEC NAME decides_now := ((spec_set | carried | all_in) & !answered) -> dut.outs_valid
  -- ONE answer a round: after it, nothing until the round closes, and then
  -- only the next round's, which a carrying token taken in that cycle decides.
  INVARSPEC NAME once := (dut.outs_valid & answered) -> (closes & next_carried & dut.outs = next_arriving)
  -- THE ROUND CLOSES IN ITS LAST CYCLE: the next round's winner taken then
  -- is answered then.
  INVARSPEC NAME next_decides_now := (closes & answered & next_carried) -> dut.outs_valid
  -- CONSUMPTION ON ARRIVAL: an input that has not given this round's token
  -- is taken the cycle it is offered; one that has, only in the cycle the
  -- round closes, and that token is the next round's.
{nl.join(f"  INVARSPEC NAME on_arrival_{k} := dut.ins_{k}_ready <-> (!got{k} | closes)" for k in ks)}
  -- the answer, once offered, stays offered and unchanged until taken
  INVARSPEC NAME held := was_offered -> (dut.outs_valid & dut.outs = was_outs)
  -- NO DEADLOCK: an emission stays reachable from every reachable state.
  CTLSPEC NAME live := AG EF dut.outs_valid
"""


def find_checker(explicit):
    for c in (explicit, os.environ.get("NUSMV"), "NuSMV", "nuXmv"):
        if c and shutil.which(c) or (c and os.path.isfile(c) and os.access(c, os.X_OK)):
            return c
    return None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--size", type=int, default=3)
    ap.add_argument("--bitwidth", type=int, default=2)
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
        out = subprocess.run([checker, "-dynamic", path], capture_output=True,
                             text=True).stdout
    finally:
        os.unlink(path)

    specs = [l for l in out.splitlines() if l.startswith("-- specification")
             or l.startswith("-- invariant")]
    # NO VALID -> READY RING THROUGH THE UNIT: no input's ready reads that
    # input's valid, and the output's valid does not read the output's ready
    # (the completing round reads the other inputs and the answer's transfer,
    # as a join does) -- combinationally, through the model's DEFINEs.
    reads = combinational_reads(model, f"first{args.size}")
    for k in range(args.size):
        own = f"ins_{k}_valid" in reads[f"ins_{k}_ready"]
        specs.append(f"-- structure ins_{k}_ready reads not ins_{k}_valid  is {'false' if own else 'true'}")
    loop = "outs_ready" in reads["outs_valid"]
    specs.append(f"-- structure outs_valid reads not outs_ready  is {'false' if loop else 'true'}")
    bad = [l for l in specs if "is false" in l]
    for l in specs:
        print(("  FAIL " if "is false" in l else "  ok   ") + l[3:])
    print(f"\n  size {args.size}, bitwidth {args.bitwidth}: "
          f"{len(specs) - len(bad)} of {len(specs)} properties hold")
    if not specs:
        print(out, file=sys.stderr)
        return 2
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
