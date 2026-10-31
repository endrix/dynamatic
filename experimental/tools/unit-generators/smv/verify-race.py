#!/usr/bin/env python3
"""Model-check the `race` SMV model against an INDEPENDENT specification.

The specification is an observer module written from the op's requirement
(HandshakeOps.td, RaceOp), not from the model: it keeps its own record of the
round from the transfers it sees on the ports -- which inputs gave their
token and with what value, whether the answer has been taken -- decides by
itself what that record determines (a candidate wins once enabled with every
candidate of its `after` refused; the lowest-index winner, or zero once every
candidate is refused), closes the round itself, and requires the unit to
answer what the record says, the cycle it says. Nothing here reads the
unit's registers.

Usage:
    python3 verify-race.py --shape NAME [--checker PATH]

The shapes are the nests a lowering makes: a chain of priorities, an F of
incomparable guards, a guard alone over flags and a negated flag, a mixed
nest with a token (the GHDL bench's), and a guard over a flag and its
negation (formation's P and not P) in an F under a priority. `--checker` defaults to $NUSMV,
then NuSMV, then nuXmv on PATH (see verify-first.py for a build).
"""
import argparse
import os
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from generators.handshake import race as race_gen  # noqa: E402
from generators.support.utils import ATTR_BITWIDTH, SmvScalarType  # noqa: E402
from generators.support.dependencies import combinational_reads  # noqa: E402

# name -> (tokens, flags, bitwidth, CANDIDATES)
SHAPES = {
    # P(a, P(b, c)): c after b and a
    "chain": (0, 3, 3, "p1:f0/p2:f1:a0/p4:f2:a0,1"),
    # F(a, b, c): incomparable, ties by index
    "f": (0, 3, 3, "p1:f0/p2:f1/p4:f2"),
    # a guard alone over a, b and not c, at one bit
    "guard": (0, 3, 1, "p1:f0,1:u2"),
    # P(t, F(g1(a, not b), P(g2(c), g3(d, b)))): the GHDL bench's nest
    # without its dead guard
    "mixed": (1, 4, 3, "t0/p1:f0:u1:a0/p2:f2:a0/p4:f3,1:a0,2"),
    # P(F(g0(s, a, not a), g1(b)), g2(a)): g0 a guard over P and not P (one
    # flag both ways), never enabled and refused once a arrives; g2 waits
    # for that and for g1's refusal
    "dead": (0, 3, 2, "p1:f1,0:u0/p2:f2/p3:f0:a0,1"),
}


def observer(name, nt, nf, w, cands):
    """The specification, and the free environment that exercises it."""
    ty = SmvScalarType(w)
    Z = ty.format_constant(0)
    n = nt + nf
    nl = "\n"

    def iname(i):
        return f"tokens_{i}" if i < nt else f"flags_{i - nt}"

    def dname(i):
        return f"t{i}" if i < nt else f"f{i - nt}"

    def nonzero(x):
        return x if w == 1 else f"{x} != {Z}"

    def itype(i):
        return str(ty) if i < nt else "boolean"

    args = [f"t{t}" for t in range(nt)] + [f"vt{t}" for t in range(nt)] + \
           [f"f{f}" for f in range(nf)] + [f"vf{f}" for f in range(nf)] + ["rdy"]

    def valid(i):
        return f"vt{i}" if i < nt else f"vf{i - nt}"

    def decision(p, arrived, value):
        """`{p}decided` and `{p}answer` from the record `arrived(i)`,
        `value(i)`: what the requirement says the round answers."""
        out = []
        for k, c in enumerate(cands):
            sat, contra = [], []
            for f in c["flags"]:
                i = nt + f
                sat.append(f"({arrived(i)} & {value(i)})")
                contra.append(f"({arrived(i)} & !{value(i)})")
            for f in c["unless"]:
                i = nt + f
                sat.append(f"({arrived(i)} & !{value(i)})")
                contra.append(f"({arrived(i)} & {value(i)})")
            if c["token"] is not None:
                t = c["token"]
                sat.append(f"({arrived(t)} & {nonzero(value(t))})")
                contra.append(f"({arrived(t)} & !({nonzero(value(t))}))")
            out.append(f"  {p}enabled{k} := {' & '.join(sat)};")
            out.append(f"  {p}refused{k} := {' | '.join(contra)};")
        for k, c in enumerate(cands):
            out.append(f"  {p}wins{k} := {p}enabled{k}" +
                       "".join(f" & {p}refused{j}" for j in c["after"]) + ";")
        out.append(f"  {p}someone := " + " | ".join(f"{p}wins{k}" for k in range(len(cands))) + ";")
        out.append(f"  {p}nobody := " + " & ".join(f"{p}refused{k}" for k in range(len(cands))) + ";")
        out.append(f"  {p}decided := {p}someone | {p}nobody;")
        out.append(f"  {p}answer := case")
        for k, c in enumerate(cands):
            pay = value(c["token"]) if c["token"] is not None else ty.format_constant(c["payload"])
            out.append(f"    {p}wins{k} : {pay};")
        out.append(f"    TRUE : {Z};")
        out.append("  esac;")
        return nl.join(out)

    return f"""
MODULE main
  VAR
{nl.join(f"  t{t} : {ty};" for t in range(nt))}
{nl.join(f"  f{f} : boolean;" for f in range(nf))}
{nl.join(f"  {valid(i)} : boolean;" for i in range(n))}
  rdy : boolean;
  dut : {name}({", ".join(args)});

  -- The observer's own record of the round.
{nl.join(f"  got{i} : boolean;" for i in range(n))}
{nl.join(f"  rec{i} : {itype(i)};" for i in range(n))}
  answered : boolean;
  -- the answer offered and not taken in the cycle before, for the protocol
  was_offered : boolean;
  was_outs : {ty};
  -- the environment holds an offered input until it is taken
{nl.join(f"  last_v{i} : boolean;" for i in range(n))}
{nl.join(f"  last_d{i} : {itype(i)};" for i in range(n))}

  DEFINE
{nl.join(f"  x{i} := {valid(i)} & dut.{iname(i)}_ready;" for i in range(n))}
  x_out := dut.outs_valid & rdy;
  -- a transfer is this round's unless the input gave its token already;
  -- then it is the next round's, which the round's last cycle may take
{nl.join(f"  now{i} := x{i} & !got{i};" for i in range(n))}
{nl.join(f"  nxt{i} := x{i} & got{i};" for i in range(n))}
{nl.join(f"  in{i} := got{i} | now{i};" for i in range(n))}
{nl.join(f"  val{i} := got{i} ? rec{i} : {dname(i)};" for i in range(n))}
  all_in := {" & ".join(f"in{i}" for i in range(n))};
  -- what the round's record determines
{decision("", lambda i: f"in{i}", lambda i: f"val{i}")}
  -- what the next round's tokens, taken in this round's last cycle, decide
{decision("n_", lambda i: f"nxt{i}", lambda i: dname(i))}
  -- the round closes once every input gave its token and the answer was
  -- taken
  closes := all_in & (answered | x_out);

  ASSIGN
{nl.join(f"  init(got{i}) := FALSE;{nl}  next(got{i}) := closes ? nxt{i} : in{i};" for i in range(n))}
{nl.join(f"  init(rec{i}) := {Z if i < nt else 'FALSE'};{nl}  next(rec{i}) := (closes ? nxt{i} : now{i}) ? {dname(i)} : rec{i};" for i in range(n))}
  -- in a closing cycle whose answer was out before, an answer taken is the
  -- next round's
  init(answered) := FALSE;
  next(answered) := closes ? (answered & x_out) : (answered | x_out);
  init(was_offered) := FALSE;
  next(was_offered) := dut.outs_valid & !rdy;
  init(was_outs) := {Z};
  next(was_outs) := dut.outs;
{nl.join(f"  init(last_v{i}) := FALSE;{nl}  next(last_v{i}) := {valid(i)} & !dut.{iname(i)}_ready;" for i in range(n))}
{nl.join(f"  init(last_d{i}) := {Z if i < nt else 'FALSE'};{nl}  next(last_d{i}) := {dname(i)};" for i in range(n))}

  -- a channel's valid is not withdrawn and its data does not change under it
{nl.join(f"  INVAR last_v{i} -> ({valid(i)} & {dname(i)} = last_d{i})" for i in range(n))}

  -- SOUNDNESS: the first offer of a round's answer is what the record
  -- decides: the lowest-index winner, or zero once every candidate is
  -- refused.
  INVARSPEC NAME sound := (dut.outs_valid & !answered & !was_offered) -> dut.outs = answer
  -- NOT BEFORE: nothing is offered before the record decides.
  INVARSPEC NAME not_before := (dut.outs_valid & !answered) -> decided
  -- EARLY: the answer is out the cycle the record decides, whatever has not
  -- arrived.
  INVARSPEC NAME decides_now := (decided & !answered) -> dut.outs_valid
  -- ONE answer a round: after it, nothing until the round closes, and then
  -- only the next round's, which the tokens taken in that cycle decide.
  INVARSPEC NAME once := (dut.outs_valid & answered) -> (closes & n_decided & dut.outs = n_answer)
  -- THE ROUND CLOSES IN ITS LAST CYCLE: a next round its tokens decide is
  -- answered then.
  INVARSPEC NAME next_decides_now := (closes & answered & n_decided) -> dut.outs_valid
  -- CONSUMPTION ON ARRIVAL: an input that has not given this round's token
  -- is taken the cycle it is offered; one that has, only in the cycle the
  -- round closes, and that token is the next round's.
{nl.join(f"  INVARSPEC NAME on_arrival_{i} := dut.{iname(i)}_ready <-> (!got{i} | closes)" for i in range(n))}
  -- the answer, once offered, stays offered and unchanged until taken
  INVARSPEC NAME held := was_offered -> (dut.outs_valid & dut.outs = was_outs)
  -- NO DEADLOCK: an answer stays reachable from every reachable state.
  CTLSPEC NAME live := AG EF dut.outs_valid
"""


def find_checker(explicit):
    for c in (explicit, os.environ.get("NUSMV"), "NuSMV", "nuXmv"):
        if c and shutil.which(c) or (c and os.path.isfile(c) and os.access(c, os.X_OK)):
            return c
    return None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--shape", choices=sorted(SHAPES), required=True)
    ap.add_argument("--checker", default=None)
    args = ap.parse_args()

    nt, nf, w, encoding = SHAPES[args.shape]
    name = f"race_{args.shape}"
    model = race_gen.generate_race(name, {
        "size_tokens": nt, "size_flags": nf, ATTR_BITWIDTH: w,
        "candidates": encoding})
    cands = race_gen.parse_candidates(encoding, nt, nf, w)
    text = model + observer(name, nt, nf, w, cands)

    checker = find_checker(args.checker)
    if not checker:
        print("No NuSMV or nuXmv found; see verify-first.py's docstring for a build.",
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
    # input's valid, and the output's valid does not read the output's ready,
    # combinationally, through the model's DEFINEs.
    reads = combinational_reads(model, name)
    for i in range(nt + nf):
        port = f"tokens_{i}" if i < nt else f"flags_{i - nt}"
        own = f"{port}_valid" in reads[f"{port}_ready"]
        specs.append(f"-- structure {port}_ready reads not {port}_valid  is {'false' if own else 'true'}")
    loop = "outs_ready" in reads["outs_valid"]
    specs.append(f"-- structure outs_valid reads not outs_ready  is {'false' if loop else 'true'}")
    bad = [l for l in specs if "is false" in l]
    for l in specs:
        print(("  FAIL " if "is false" in l else "  ok   ") + l[3:])
    print(f"\n  shape {args.shape} ({encoding}): "
          f"{len(specs) - len(bad)} of {len(specs)} properties hold")
    if len(specs) <= nt + nf + 1:
        print(out, file=sys.stderr)
        return 2
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
