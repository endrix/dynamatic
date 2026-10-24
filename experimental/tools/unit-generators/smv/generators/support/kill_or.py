from generators.support.utils import *


def generate_kill_or(name, params):
    """The kill of a domain with several commits (`handshake.commit`), as a
    NuSMV model: the OR of their kills, which HandshakeToHW gives the
    domain's units as their reset (their KILL_RESET models take it as their
    last parameter). `size` inputs, `ins_0` ..., one output, `outs`;
    combinational. Not a Handshake unit: the lowering's own.

    `many` is no output but an observer's handle on the domain's promise: two
    or more of its commits transfer in this cycle. The rounds of a domain
    never overlap (`handshake.commit`), so a model of the circuit's producer
    can state `INVARSPEC !<domain's kill_or>.many`; the unit itself is the
    same whatever it is.
    """
    size = params[ATTR_SIZE]
    if size < 2:
        raise ValueError(
            "kill_or ORs the kills of a domain's commits, and the lowering "
            "builds one only for a domain with two or more")
    ins = [f"ins_{i}" for i in range(size)]
    return f"""
MODULE {name}({", ".join(ins)})
  -- output
  DEFINE
  outs := {" | ".join(ins)};
  -- (an observer's: two or more of the domain's commits in this cycle, which
  -- the domain's promise excludes)
  many := count({", ".join(ins)}) > 1;
"""
