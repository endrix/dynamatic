#!/usr/bin/env python3
"""Model-check the SMV model of a load that drops on a kill against an
INDEPENDENT specification, on the memory controller's own read path.

The load (`handshake.load` under `handshake.kill_domain`) serves a requester a
`commit` can stop. The observer keeps the addresses the load accepted, oldest
first, each marked STALE once a kill has stopped the evaluation that asked for
it (an address accepted in the kill cycle is the stopped one's), and requires:
every word offered to the requester is the word of its oldest outstanding
address, and not a stale one -- no stale word -- and only a stale word is
ever dropped; at most three are outstanding (the load's two
bits); and the memory controller, which cannot forget a granted read, never
sees a request withdrawn before it is granted. The read path is the
controller's (memory_controller.py's read arbiter, one port) and a memory
whose word at address a is a.

Usage:
    python3 verify-load-kill-drop.py [--addr-bitwidth A] [--checker PATH]
"""
import argparse
import os
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from generators.handshake import load as load_gen  # noqa: E402
from generators.memory import memory_controller as mc_gen  # noqa: E402
from generators.support.utils import (ATTR_ADDR_BITWIDTH,  # noqa: E402
                                      ATTR_DATA_BITWIDTH, SmvScalarType)


def observer(a: int) -> str:
    t = SmvScalarType(a)
    Z = t.format_constant(0)
    depth = 4
    ks = range(depth)
    nl = "\n"
    def shift(arr, new, keep):
        return nl.join(
            f"  next(q_{arr}{k}) := case\n"
            f"    push & pop & q_n = {k + 1} : {new};\n"
            f"    pop : {keep(f'q_{arr}{k + 1}') if k + 1 < depth else new};\n"
            f"    push & q_n = {k} : {new};\n"
            f"    TRUE : {keep(f'q_{arr}{k}')};\n  esac;" for k in ks)
    return f"""
MODULE main
  VAR
  a : {t};
  av : boolean;
  rdy : boolean;
  kill : boolean;
  ld : load(a, av, arb.data_out_0, arb.valid_0, kill, arb.ready_0, rdy);
  arb : arbiter(ld.addrOut_valid, ld.addrOut, ld.dataFromMem_ready, mem);
  -- the memory's synchronous read: the word of the address enabled, the
  -- cycle after
  mem : {t};
  -- the addresses accepted and not yet answered, oldest first, and whether a
  -- kill has stopped the evaluation that asked for each
  q_n : 0..{depth};
{nl.join(f"  q_a{k} : {t};{nl}  q_s{k} : boolean;" for k in ks)}
  last_av : boolean;
  last_a : {t};
  last_aov : boolean;
  last_ao : {t};

  DEFINE
  push := av & ld.addrIn_ready;
  -- a word leaves the load: to the requester, or dropped
  pop := ld.word_valid & (rdy | ld.dropping);
  delivered := ld.dataOut_valid & rdy;
  dropped := pop & !delivered;

  ASSIGN
  init(mem) := {Z};
  next(mem) := arb.read_enable ? arb.read_address : mem;
  init(q_n) := 0;
  next(q_n) := case
    push & !pop & q_n < {depth} : q_n + 1;
    !push & pop & q_n > 0 : q_n - 1;
    TRUE : q_n;
  esac;
{nl.join(f"  init(q_a{k}) := {Z};{nl}  init(q_s{k}) := FALSE;" for k in ks)}
{shift('a', 'a', lambda v: v)}
{shift('s', 'kill', lambda v: f"({v} | kill)")}
  init(last_av) := FALSE;
  next(last_av) := av & !ld.addrIn_ready & !kill;
  init(last_a) := {Z};
  next(last_a) := a;
  init(last_aov) := FALSE;
  next(last_aov) := ld.addrOut_valid & !arb.ready_0;
  init(last_ao) := {Z};
  next(last_ao) := ld.addrOut;

  -- the requester holds the address it offers until taken, unless stopped
  INVAR last_av -> (av & a = last_a)

  -- NO STALE WORD: what is offered to the requester answers its oldest
  -- outstanding address, which no kill has stopped.
  INVARSPEC NAME fresh := ld.dataOut_valid -> (q_n > 0 & !q_s0 & ld.dataOut = q_a0)
  -- only a stale word is dropped
  INVARSPEC NAME drops_stale := dropped -> (q_n > 0 & q_s0)
  -- at most three words owed: the load's two bits hold the count
  INVARSPEC NAME bounded := q_n <= 3
  -- NO REQUEST WITHDRAWN: an address offered to the controller stays offered,
  -- unchanged, until granted
  INVARSPEC NAME no_withdraw := last_aov -> (ld.addrOut_valid & ld.addrOut = last_ao)
"""


def find_checker(explicit):
    for c in (explicit, os.environ.get("NUSMV"), "NuSMV", "nuXmv"):
        if c and shutil.which(c) or (c and os.path.isfile(c) and os.access(c, os.X_OK)):
            return c
    return None


def model(a: int) -> str:
    t = SmvScalarType(a)
    return (load_gen.generate_load("load", {ATTR_DATA_BITWIDTH: a, ATTR_ADDR_BITWIDTH: a,
                                            "kill_drop": 1}) +
            mc_gen._generate_read_memory_arbiter("arbiter", 1, t, t))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--addr-bitwidth", type=int, default=2)
    ap.add_argument("--checker", default=None)
    args = ap.parse_args()

    text = model(args.addr_bitwidth) + observer(args.addr_bitwidth)

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
        out = subprocess.run([checker, "-dynamic", path], capture_output=True,
                             text=True).stdout
    finally:
        os.unlink(path)

    specs = [l for l in out.splitlines() if l.startswith("-- invariant")]
    bad = [l for l in specs if "is false" in l]
    for l in specs:
        print(("  FAIL " if "is false" in l else "  ok   ") + l[3:])
    print(f"\n  address bitwidth {args.addr_bitwidth}: {len(specs) - len(bad)} of "
          f"{len(specs)} properties hold")
    if not specs:
        print(out, file=sys.stderr)
        return 2
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
