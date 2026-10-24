from generators.support.utils import *


def generate_first(name, params):
    """A first-wins merge with full consumption, as a NuSMV model.

    `merge` forwards one input and consumes ONE token per firing. `first`
    consumes exactly one token on EVERY input per round and emits one, and the
    payload it emits is the first non-zero one to ARRIVE. Payload 0 is the
    reserved "nothing selected" value, which is what makes a winner
    distinguishable from a loser.

    The state is the round: `seen` records which inputs have already given
    their token, `winner` and `has_win` hold an answer found before the round
    closed, and `emitted` remembers that the answer has already been taken.
    There is no reset input in SMV, so `init()` carries what `rst` carries in
    the RTL.

    The round closes in the cycle it completes: an input that gave its token
    is ready again the cycle the last one arrives with the answer taken or
    being taken, and gives the next round's (`again`); with the answer out
    earlier, a winner among those is answered in that same cycle (the RTL
    generator, register for register).
    """
    size = params[ATTR_SIZE]
    data_type = SmvScalarType(params[ATTR_BITWIDTH])

    if data_type.bitwidth == 0:
        raise ValueError(
            "handshake.first has no dataless form: the payload is what "
            "distinguishes a winner from a loser. A dataless first-wins unit "
            "is a join.")

    zero = data_type.format_constant(0)
    ins = ", ".join([f"ins_{n}" for n in range(size)])
    valids = ", ".join([f"ins_{n}_valid" for n in range(size)])

    # An input carries an action when it is being taken this cycle and its
    # payload is not the reserved zero.
    carries = [f"(taken_{n} & ins_{n} != {zero})" for n in range(size)]
    carries_again = [f"(again_{n} & ins_{n} != {zero})" for n in range(size)]
    carries_early = [f"(early_{n} & ins_{n} != {zero})" for n in range(size)]

    def others(fmt, k, join, empty):
        terms = [fmt.format(j=j) for j in range(size) if j != k]
        return f" {join} ".join(terms) if terms else empty

    return f"""
MODULE {name}({ins}, {valids}, outs_ready)
  VAR
  {"\n  ".join([f"seen_{n} : boolean;" for n in range(size)])}
  winner : {data_type};
  has_win : boolean;
  emitted : boolean;

  DEFINE
  -- Each input gives exactly one token per round: once seen, not ready again
  -- until the round completes -- and then at once, in the cycle it does.
  {"\n  ".join([f"taken_{n} := ins_{n}_valid & !seen_{n};" for n in range(size)])}
  {"\n  ".join([f"seen_next_{n} := seen_{n} | taken_{n};" for n in range(size)])}
  closing := {" & ".join([f"seen_next_{n}" for n in range(size)])};

  -- The first input carrying an action THIS cycle, by index order.
  -- Simultaneous arrivals are incomparable, so any of them is a conformant
  -- winner.
  cand_v := {" | ".join(carries)};
  cand := case
    {"\n    ".join([f"{carries[n]} : ins_{n};" for n in range(size)])}
    TRUE : {zero};
  esac;

  -- Emit the instant a winner exists, or emit "nothing selected" when the
  -- round closes without one.
  valid_i := (has_win | cand_v | closing) & !emitted;
  fire := valid_i & outs_ready;
  -- The round is over once every input has given its token AND the output has
  -- been taken. Those can happen in either order.
  done := closing & (emitted | fire);

  -- An input that has given its token is ready again the cycle the round
  -- completes, which it reads from the OTHER inputs alone (its own token is
  -- in): its ready never reads its own valid, and the output's valid never
  -- reads the output's ready.
  {"\n  ".join([f"closing_wo_{k} := {others('seen_next_{j}', k, '&', 'TRUE')};" for k in range(size)])}
  {"\n  ".join([f"done_wo_{k} := closing_wo_{k} & (emitted | (has_win | {others('(taken_{j} & ins_{j} != ' + zero + ')', k, '|', 'FALSE')} | closing_wo_{k}) & outs_ready);" for k in range(size)])}
  -- The next round's tokens, on the inputs that gave this round's already;
  -- with the answer out earlier the output is free, and a winner among them
  -- goes now.
  {"\n  ".join([f"again_{n} := ins_{n}_valid & seen_{n} & done_wo_{n};" for n in range(size)])}
  {"\n  ".join([f"early_{n} := ins_{n}_valid & seen_{n} & closing_wo_{n} & emitted;" for n in range(size)])}
  again_v := {" | ".join(carries_again)};
  cand_again := case
    {"\n    ".join([f"{carries_again[n]} : ins_{n};" for n in range(size)])}
    TRUE : {zero};
  esac;
  early := {" | ".join(carries_early)};
  cand_early := case
    {"\n    ".join([f"{carries_early[n]} : ins_{n};" for n in range(size)])}
    TRUE : {zero};
  esac;

  ASSIGN
  {"\n  ".join([f"init(seen_{n}) := FALSE;" for n in range(size)])}
  {"\n  ".join([f"next(seen_{n}) := done ? again_{n} : seen_next_{n};" for n in range(size)])}
  init(has_win) := FALSE;
  next(has_win) := done ? again_v : (has_win | cand_v);
  init(winner) := {zero};
  -- A token taken while the sink is stalled is still TAKEN, so it is latched
  -- here and held rather than lost.
  next(winner) := done ? cand_again : ((!has_win & cand_v) ? cand : winner);
  init(emitted) := FALSE;
  -- Having emitted early, stay quiet while absorbing the stragglers.
  next(emitted) := done ? (early & outs_ready) : (emitted | fire);

  -- output
  DEFINE
  {"\n  ".join([f"ins_{n}_ready := !seen_{n} | done_wo_{n};" for n in range(size)])}
  outs_valid := valid_i | early;
  outs := emitted ? cand_early : (has_win ? winner : cand);
"""
