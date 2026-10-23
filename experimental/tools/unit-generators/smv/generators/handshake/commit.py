from generators.support.utils import *


def generate_commit(name, params):
    """A wire that says when its token has passed (`handshake.commit`), as a
    NuSMV model: `outs` is `ins`, valid and ready straight through, and `kill`
    is the transfer. The RTL ORs the reset into `kill` (it is the reset of
    the units the transfer stops); there is no reset in SMV, where those
    units start in their `init()` state as everything else does.
    """
    data_type = SmvScalarType(params[ATTR_BITWIDTH])

    if data_type.bitwidth == 0:
        return f"""
MODULE {name}(ins_valid, outs_ready)
  -- output
  DEFINE
  outs_valid := ins_valid;
  ins_ready := outs_ready;
  kill := ins_valid & outs_ready;
"""
    return f"""
MODULE {name}(ins, ins_valid, outs_ready)
  -- output
  DEFINE
  outs := ins;
  outs_valid := ins_valid;
  ins_ready := outs_ready;
  kill := ins_valid & outs_ready;
"""
