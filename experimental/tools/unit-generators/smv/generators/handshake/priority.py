from generators.support.utils import *


def generate_priority(name, params):
    """A priority merge that waits for its high input only, as a NuSMV model.

    `hi` when it carries something, `lo` otherwise; payload 0 is the reserved
    "nothing selected". The unit consumes one token on each input per round,
    each the cycle it arrives (`seen_hi`, `seen_lo`: not ready again until the
    round closes), and emits one: `hi` the cycle a non-zero `hi` arrives,
    whether `lo` has arrived or not; when `hi` arrives zero, `lo` the cycle it
    is there. The round closes once both inputs are in and the answer has
    been taken.

    The state is the RTL generator's, register for register
    (tools/unit-generators/vhdl/generators/handshake/priority.py): `emitted`,
    `hi_nz_r` (a non-zero hi is in) and `held`, the answer as far as it is
    known -- a non-zero hi, else lo. There is no reset input in SMV, so
    `init()` carries what `rst` carries in the RTL. `verify-priority.py`
    checks the model against a specification written apart from it.

    The round closes in the cycle it completes: the input that gave its token
    is ready again the cycle the other arrives with the answer taken or being
    taken, and gives the next round's (`again_hi`, `again_lo`); with the
    answer out earlier, a non-zero hi of the next round is answered in that
    same cycle.
    """
    data_type = SmvScalarType(params[ATTR_BITWIDTH])

    if data_type.bitwidth == 0:
        raise ValueError(
            "handshake.priority has no dataless form: the payload is the "
            "answer, and zero is 'nothing selected'. A dataless priority is "
            "a join.")

    zero = data_type.format_constant(0)
    # a one-bit payload is a boolean in these models
    nonzero = "hi" if data_type.bitwidth == 1 else f"hi != {zero}"

    return f"""
MODULE {name}(hi, hi_valid, lo, lo_valid, outs_ready)
  VAR
  seen_hi : boolean;
  seen_lo : boolean;
  emitted : boolean;
  hi_nz_r : boolean;
  held : {data_type};

  DEFINE
  -- Each input gives exactly one token per round: once seen, not ready again
  -- until the round completes -- and then at once, in the cycle it does.
  take_hi := hi_valid & !seen_hi;
  take_lo := lo_valid & !seen_lo;
  hi_here := seen_hi | take_hi;
  lo_here := seen_lo | take_lo;
  hi_now_nz := take_hi & ({nonzero});
  hi_nz := hi_nz_r | hi_now_nz;

  -- hi decides alone when it is non-zero; otherwise lo, once it is here.
  -- Never before hi is here, and once a round.
  valid_i := !emitted & hi_here & (hi_nz | lo_here);
  fire := valid_i & outs_ready;
  -- The round is over once both inputs have given their token AND the answer
  -- has been taken, in either order.
  done := hi_here & lo_here & (emitted | fire);

  -- An input that has given its token is ready again the cycle the round
  -- completes, which it reads from the OTHER input alone (its own token is
  -- in): its ready never reads its own valid, and the output's valid never
  -- reads the output's ready.
  done_hi := lo_here & (emitted | ((hi_nz_r | lo_here) & outs_ready));
  done_lo := hi_here & (emitted | outs_ready);
  -- The next round's tokens, on the inputs that gave this round's already;
  -- with the answer out earlier the output is free, and a non-zero hi among
  -- them goes now.
  again_hi := hi_valid & seen_hi & done_hi;
  again_lo := lo_valid & seen_lo & done_lo;
  again_nz := again_hi & ({nonzero});
  early := hi_valid & seen_hi & lo_here & emitted & ({nonzero});

  ASSIGN
  init(seen_hi) := FALSE;
  next(seen_hi) := done ? again_hi : hi_here;
  init(seen_lo) := FALSE;
  next(seen_lo) := done ? again_lo : lo_here;
  init(emitted) := FALSE;
  -- Having answered early, stay quiet while absorbing the late input.
  next(emitted) := done ? (early & outs_ready) : (emitted | fire);
  init(hi_nz_r) := FALSE;
  next(hi_nz_r) := done ? again_nz : hi_nz;
  init(held) := {zero};
  -- An input taken while the sink is stalled is still TAKEN: what the answer
  -- needs of it is held rather than lost.
  next(held) := case
    done & again_nz : hi;
    done & again_lo : lo;
    done : {zero};
    hi_now_nz : hi;
    take_lo & !hi_nz_r : lo;
    TRUE : held;
  esac;

  -- output
  DEFINE
  hi_ready := !seen_hi | done_hi;
  lo_ready := !seen_lo | done_lo;
  outs_valid := valid_i | early;
  outs := (hi_now_nz | early) ? hi : ((hi_nz_r | !take_lo) ? held : lo);
"""
