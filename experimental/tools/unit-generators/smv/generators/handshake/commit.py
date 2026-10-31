from generators.support.utils import *


def generate_commit(name, params):
    """A wire that says when its token has passed (`handshake.commit`), as a
    NuSMV model: `outs` is `ins`, valid and ready straight through, and `kill`
    is the transfer. The RTL ORs the reset into `kill` (it is the reset of
    the units the transfer stops); there is no reset in SMV, where those
    units start in their `init()` state as everything else does.

    `kill_at_valid` (1): the kill in the first cycle a token is offered,
    `ins_valid & !killed`, `killed` the RTL's flip-flop ("offered and not
    taken last cycle", FALSE at init).
    """
    data_type = SmvScalarType(params[ATTR_BITWIDTH])
    at_valid = int(params.get("kill_at_valid", 0))
    if at_valid not in (0, 1):
        raise ValueError(
            f"handshake.commit: kill_at_valid is 0 or 1, not {at_valid}")

    if at_valid:
        state = """
  VAR
  killed : boolean;

  ASSIGN
  init(killed) := FALSE;
  next(killed) := ins_valid & !outs_ready;
"""
        kill = "kill := ins_valid & !killed;"
    else:
        state = ""
        kill = "kill := ins_valid & outs_ready;"

    if data_type.bitwidth == 0:
        return f"""
MODULE {name}(ins_valid, outs_ready)
{state}
  -- output
  DEFINE
  outs_valid := ins_valid;
  ins_ready := outs_ready;
  {kill}
"""
    return f"""
MODULE {name}(ins, ins_valid, outs_ready)
{state}
  -- output
  DEFINE
  outs := ins;
  outs_valid := ins_valid;
  ins_ready := outs_ready;
  {kill}
"""
