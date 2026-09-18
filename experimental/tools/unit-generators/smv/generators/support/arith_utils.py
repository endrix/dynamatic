from generators.support.delay_buffer import generate_delay_buffer
from generators.handshake.join import generate_join
from generators.support.utils import *


def generate_binary_op_handshake_manager(name, params):
    latency = params[ATTR_LATENCY]
    impl = params.get(ATTR_IMPL, "pipelined")

    if impl == "sequential":
        return _generate_handshake_manager_sequential(name, latency)
    if impl != "pipelined":
        raise ValueError(f"unknown impl {impl!r} (pipelined or sequential)")
    if latency == 0:
        return _generate_handshake_manager_no_lat(name)
    else:
        return _generate_handshake_manager(name, latency)


def _generate_handshake_manager_no_lat(name):
    return f"""
MODULE {name}(lhs_valid, rhs_valid, outs_ready)
  VAR inner_join : {name}__join(lhs_valid, rhs_valid, outs_ready);

  -- output
  DEFINE lhs_ready := inner_join.ins_0_ready;
  DEFINE rhs_ready := inner_join.ins_1_ready;
  DEFINE outs_valid := inner_join.outs_valid;
  
  {generate_join(f"{name}__join", {"size": 2})}
"""


def _generate_handshake_manager(name, latency):
    return f"""
MODULE {name}(lhs_valid, rhs_valid, outs_ready)
  VAR inner_join : {name}__join(lhs_valid, rhs_valid, inner_delay_buffer.ins_ready);
  VAR inner_delay_buffer : {name}__delay_buffer(inner_join.outs_valid, outs_ready);

  -- output
  DEFINE lhs_ready := inner_join.ins_0_ready;
  DEFINE rhs_ready := inner_join.ins_1_ready;
  DEFINE outs_valid := inner_delay_buffer.outs_valid;
  
  {generate_join(f"{name}__join", {"size": 2})}
  {generate_delay_buffer(f"{name}__delay_buffer", {ATTR_LATENCY: latency})}
"""


def _generate_handshake_manager_sequential(name, latency):
    """A unit that runs one operation at a time: the operands are joined and
    taken when nothing is running and no result is waiting, the result comes
    LATENCY cycles later and is held until it is taken. The pipelined
    manager's delay buffer takes a pair every cycle; this one takes a pair
    every LATENCY cycles, which is what a sequential divider or multiplier
    does (`IMPL = "sequential"`)."""

    if latency < 2:
        raise ValueError(
            f"a sequential unit needs a latency of at least 2, got {latency}")

    # the operation runs for LATENCY - 1 cycles, then the result is there
    steps = latency - 1
    counter = "" if steps == 1 else f"""
  VAR step : 0..{steps - 1};
  ASSIGN init(step) := 0;
  ASSIGN next(step) := case
    accept : 0;
    busy : (step + 1) mod {steps};
    TRUE : step;
  esac;
"""
    last = "busy" if steps == 1 else f"busy & step = {steps - 1}"

    return f"""
MODULE {name}(lhs_valid, rhs_valid, outs_ready)
  VAR busy : boolean;
  VAR done : boolean;
{counter}
  -- the operands are taken together, when nothing is running and no result
  -- is waiting (or it goes this cycle)
  DEFINE idle := !busy & (!done | outs_ready);
  DEFINE accept := lhs_valid & rhs_valid & idle;
  DEFINE last := {last};

  ASSIGN init(busy) := FALSE;
  ASSIGN next(busy) := case
    accept : TRUE;
    last : FALSE;
    TRUE : busy;
  esac;

  ASSIGN init(done) := FALSE;
  ASSIGN next(done) := case
    last : TRUE;
    done & outs_ready : FALSE;
    TRUE : done;
  esac;

  -- output
  DEFINE lhs_ready := rhs_valid & idle;
  DEFINE rhs_ready := lhs_valid & idle;
  DEFINE outs_valid := done;
"""


def generate_binary_op_header(name):
    return f"""
MODULE {name}(lhs, lhs_valid, rhs, rhs_valid, outs_ready)
  VAR inner_handshake_manager : {name}__handshake_manager(lhs_valid, rhs_valid, outs_ready);

  -- output
  DEFINE lhs_ready := inner_handshake_manager.lhs_ready;
  DEFINE rhs_ready := inner_handshake_manager.rhs_ready;
  DEFINE result_valid := inner_handshake_manager.outs_valid;
"""


def generate_unanary_op_header(name):
    return f"""
MODULE {name}(ins, ins_valid, outs_ready)
  VAR inner_delay_buffer : {name}__delay_buffer(ins_valid, outs_ready);

  -- output
  DEFINE ins_ready := inner_delay_buffer.ins_ready;
  DEFINE outs_valid := inner_delay_buffer.outs_valid;
"""


def generate_abstract_binary_op(name, latency, data_type, impl="pipelined"):
    return f"""
{generate_binary_op_header(name)}
  DEFINE result := {data_type.format_constant(0)};
  
  {generate_binary_op_handshake_manager(f"{name}__handshake_manager", {ATTR_LATENCY: latency, ATTR_IMPL: impl})}
"""


def generate_abstract_unary_op(name, latency, data_type):
    return f"""
{generate_unanary_op_header(name)}
  DEFINE outs := {data_type.format_constant(0)};
  
  {generate_delay_buffer(f"{name}__delay_buffer", {ATTR_LATENCY: latency})}
"""
