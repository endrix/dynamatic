from generators.support.utils import *


def generate_stand_in(name, params):
    """Answers zero for a producer a commit stopped (`handshake.stand_in`), as
    a NuSMV model, register for register the RTL generator's: `sent` (this
    round's token has passed; `kill` ends the round) and `owe` (a zero is
    owed: offered from the cycle after the kill until taken, `ins` waiting
    meanwhile).

    `size` kills, `kill_0` ..., the kills of all the commits of the
    producer's domain (a domain may have several): any of them high ends ONE
    round, `kill` their OR, the model otherwise the same whatever their
    number. The rounds of a domain never overlap -- a round of the domain
    starts only after the previous commit of the domain has transferred -- so
    at most one kill is high in a cycle, and it ends the round this unit is
    in. (Were state B's round to start before state A's commit transferred,
    A's kill would wipe it with A's round, and B's reader would wait for ever
    for this unit's token.) The producer's promise, which an observer states
    as an assumption (verify-stand-in.py) or checks (`many` of the domain's
    `kill_or`).
    """
    data_type = SmvScalarType(params[ATTR_BITWIDTH])
    size = params[ATTR_SIZE]
    if size < 1:
        raise ValueError(
            "handshake.stand_in answers for a producer a commit stops, so it "
            "takes at least one kill")
    kills = [f"kill_{i}" for i in range(size)]

    if data_type.bitwidth == 0:
        raise ValueError(
            "handshake.stand_in answers zero, so its channel carries data")

    zero = data_type.format_constant(0)
    return f"""
MODULE {name}(ins, ins_valid, {", ".join(kills)}, outs_ready)
  VAR
  sent : boolean;
  owe : boolean;

  DEFINE
  -- one round ends, whichever commit ends it
  kill := {" | ".join(kills)};
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
