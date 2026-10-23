#!/usr/bin/env python3
"""Model-check the `priority` SMV model against an INDEPENDENT specification.

`priority` is `hi` when `hi` carries something, `lo` otherwise, decided as
soon as the tokens it holds determine the answer (`esa.p` of the StreamBlocks
ESA dialect: wait for `hi`, never for `lo` when `hi` decides). The
specification is an observer written from that requirement, not from the
model: it keeps its own record of the round -- which inputs and whether the
answer have been transferred, and the payloads that came in -- from the
transfers it sees on the ports, closes the round itself, and the unit is
required to answer what that record says, at the cycle it says. Nothing here
reads the unit's registers.

Usage:
    python3 verify-priority.py [--bitwidth W] [--checker PATH]

`--checker` defaults to $NUSMV, then NuSMV, then nuXmv on PATH (see
verify-first.py for a NuSMV build).
"""
import argparse
import os
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from generators.handshake import priority as priority_gen  # noqa: E402
from generators.support.utils import ATTR_BITWIDTH, SmvScalarType  # noqa: E402
from generators.support.dependencies import combinational_reads  # noqa: E402


def observer(w: int) -> str:
    """The specification, and the free environment that exercises it."""
    t = SmvScalarType(w)
    Z = t.format_constant(0)
    nz = (lambda e: e) if w == 1 else (lambda e: f"{e} != {Z}")
    return f"""
MODULE main
  VAR
  hi : {t};
  lo : {t};
  hv : boolean;
  lv : boolean;
  rdy : boolean;
  dut : priority{w}(hi, hv, lo, lv, rdy);

  -- The observer's record of the round, from the transfers on the ports.
  got_hi : boolean;
  got_lo : boolean;
  answered : boolean;
  hi_val : {t};
  lo_val : {t};
  -- the answer offered and not taken in the cycle before, for the protocol
  was_offered : boolean;
  was_outs : {t};

  -- the environment holds an offered input until it is taken, as a channel
  -- does
  last_hv : boolean;
  last_lv : boolean;
  last_hi : {t};
  last_lo : {t};

  DEFINE
  x_hi := hv & dut.hi_ready;
  x_lo := lv & dut.lo_ready;
  x_out := dut.outs_valid & rdy;
  -- a transfer is this round's unless the input gave its token already;
  -- then it is the next round's, which the round's last cycle may take
  now_hi := x_hi & !got_hi;
  now_lo := x_lo & !got_lo;
  next_hi := x_hi & got_hi;
  next_lo := x_lo & got_lo;
  -- this round's inputs as known now, transfers of this cycle included
  hi_in := got_hi | now_hi;
  lo_in := got_lo | now_lo;
  hi_now := got_hi ? hi_val : hi;
  lo_now := got_lo ? lo_val : lo;
  hi_carries := hi_in & ({nz("hi_now")});
  -- the round closes once both inputs came and the answer was taken
  closes := hi_in & lo_in & (answered | x_out);
  -- the next round's hi, taken in the cycle this one closes, decides it
  next_carries := closes & next_hi & ({nz("hi")});

  ASSIGN
  init(got_hi) := FALSE;
  next(got_hi) := closes ? next_hi : hi_in;
  init(got_lo) := FALSE;
  next(got_lo) := closes ? next_lo : lo_in;
  -- in a closing cycle whose answer was out before, an answer taken is the
  -- next round's
  init(answered) := FALSE;
  next(answered) := closes ? (answered & x_out) : (answered | x_out);
  init(hi_val) := {Z};
  next(hi_val) := x_hi ? hi : hi_val;
  init(lo_val) := {Z};
  next(lo_val) := x_lo ? lo : lo_val;
  init(was_offered) := FALSE;
  next(was_offered) := dut.outs_valid & !rdy;
  init(was_outs) := {Z};
  next(was_outs) := dut.outs;
  init(last_hv) := FALSE;
  next(last_hv) := hv & !dut.hi_ready;
  init(last_lv) := FALSE;
  next(last_lv) := lv & !dut.lo_ready;
  init(last_hi) := {Z};
  next(last_hi) := hi;
  init(last_lo) := {Z};
  next(last_lo) := lo;

  -- a channel's valid is not withdrawn and its data does not change under it
  INVAR last_hv -> (hv & hi = last_hi)
  INVAR last_lv -> (lv & lo = last_lo)

  -- SOUNDNESS: the answer is hi when hi carries an action, lo otherwise.
  INVARSPEC NAME sound := (dut.outs_valid & !answered) -> (hi_carries ? dut.outs = hi_now : dut.outs = lo_now)
  -- hi is waited for, always: no answer before hi came.
  INVARSPEC NAME waits_hi := (dut.outs_valid & !answered) -> hi_in
  -- and lo is waited for when hi does not decide: `sound` compares against
  -- the raw lo wire before lo arrives, so alone it would pass a unit that
  -- answers a zero hi by passing that wire through.
  INVARSPEC NAME waits_lo := (dut.outs_valid & !answered & !hi_carries) -> lo_in
  -- lo is not waited for when hi decides: the answer is out the cycle a
  -- non-zero hi arrives.
  INVARSPEC NAME hi_decides_now := (hi_carries & !answered) -> dut.outs_valid
  -- with hi zero, the answer is out the cycle lo is here.
  INVARSPEC NAME lo_decides_now := (hi_in & !hi_carries & lo_in & !answered) -> dut.outs_valid
  -- ONE answer a round: after it, nothing until the round closes, and then
  -- only the next round's, which a non-zero hi taken in that cycle decides.
  INVARSPEC NAME once := (dut.outs_valid & answered) -> (next_carries & dut.outs = hi)
  -- THE ROUND CLOSES IN ITS LAST CYCLE: the next round's non-zero hi taken
  -- then is answered then (a round ended by a late lo costs the next one no
  -- cycle).
  INVARSPEC NAME next_decides_now := (next_carries & answered) -> dut.outs_valid
  -- CONSUMPTION ON ARRIVAL: an input that has not given this round's token
  -- is taken the cycle it is offered; one that has, only in the cycle the
  -- round closes, and that token is the next round's.
  INVARSPEC NAME hi_on_arrival := dut.hi_ready <-> (!got_hi | closes)
  INVARSPEC NAME lo_on_arrival := dut.lo_ready <-> (!got_lo | closes)
  -- the answer, once offered, stays offered and unchanged until taken
  INVARSPEC NAME held := was_offered -> (dut.outs_valid & dut.outs = was_outs)
  CTLSPEC NAME live := AG EF dut.outs_valid
"""


def find_checker(explicit):
    for c in (explicit, os.environ.get("NUSMV"), "NuSMV", "nuXmv"):
        if c and shutil.which(c) or (c and os.path.isfile(c) and os.access(c, os.X_OK)):
            return c
    return None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--bitwidth", type=int, default=2)
    ap.add_argument("--checker", default=None)
    args = ap.parse_args()

    model = priority_gen.generate_priority(
        f"priority{args.bitwidth}", {ATTR_BITWIDTH: args.bitwidth})
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

    specs = [l for l in out.splitlines() if l.startswith("-- invariant") or
             l.startswith("-- specification")]
    # NO VALID -> READY RING THROUGH THE UNIT: neither input's ready reads
    # that input's valid, and the output's valid does not read the output's
    # ready (the completing round reads the other input and the answer's
    # transfer, as a join does) -- combinationally, through the DEFINEs.
    reads = combinational_reads(model, f"priority{args.bitwidth}")
    for p in ("hi", "lo"):
        own = f"{p}_valid" in reads[f"{p}_ready"]
        specs.append(f"-- structure {p}_ready reads not {p}_valid  is {'false' if own else 'true'}")
    loop = "outs_ready" in reads["outs_valid"]
    specs.append(f"-- structure outs_valid reads not outs_ready  is {'false' if loop else 'true'}")
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
