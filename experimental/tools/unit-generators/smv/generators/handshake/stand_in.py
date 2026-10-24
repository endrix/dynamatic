from generators.support.utils import *


def generate_stand_in(name, params):
    """Answers zero for a producer a commit stopped (`handshake.stand_in`), as
    a NuSMV model, register for register the RTL generator's: `sent` (this
    round's token has passed; `kill` ends the round) and `owe` (a zero is
    owed: offered from the cycle after the kill until taken, `ins` waiting
    meanwhile).
    """
    data_type = SmvScalarType(params[ATTR_BITWIDTH])

    if data_type.bitwidth == 0:
        raise ValueError(
            "handshake.stand_in answers zero, so its channel carries data")

    zero = data_type.format_constant(0)
    return f"""
MODULE {name}(ins, ins_valid, kill, outs_ready)
  VAR
  sent : boolean;
  owe : boolean;

  DEFINE
  -- the producer's token goes through this cycle
  passed := ins_valid & outs_ready & !owe;

  ASSIGN
  init(sent) := FALSE;
  -- A kill ends the round: the next one has sent nothing yet.
  next(sent) := kill ? FALSE : (sent | passed);
  init(owe) := FALSE;
  -- A round ended with its token not passed owes a zero; an owed zero is
  -- paid when taken.
  next(owe) := (kill & !(sent | passed)) | (owe & !outs_ready);

  -- output
  DEFINE
  outs_valid := owe | ins_valid;
  outs := owe ? {zero} : ins;
  ins_ready := outs_ready & !owe;
"""
