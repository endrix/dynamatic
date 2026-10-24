from generators.support.utils import *
from generators.handshake.buffers.one_slot_break_r import generate_one_slot_break_r


def generate_load(name, params):
    data_type = SmvScalarType(params[ATTR_DATA_BITWIDTH])
    addr_type = SmvScalarType(params[ATTR_ADDR_BITWIDTH])

    if params.get("kill_drop", 0):
        return _generate_load_kill_drop(name, data_type, addr_type)
    return _generate_load(name, data_type, addr_type)


def _generate_load_kill_drop(name, data_type, addr_type):
    """A load whose requester a commit can stop (`handshake.kill_domain`),
    register for register the RTL generator's: the two slots, the words owed
    (addresses accepted less words passed on, two bits, wrapping as the RTL
    does) and, from a `kill` on, the words to drop -- taken from the
    controller and offered to nobody.
    """
    return f"""
MODULE {name}(addrIn, addrIn_valid, dataFromMem, dataFromMem_valid, kill, addrOut_ready, dataOut_ready)
  VAR
  inner_addr_one_slot_break_r : {name}__addr_one_slot_break_r(addrIn, addrIn_valid, addrOut_ready);
  inner_data_one_slot_break_r : {name}__data_one_slot_break_r(dataFromMem, dataFromMem_valid, word_ready);
  owed : unsigned word [2];
  drop : unsigned word [2];

  DEFINE
  -- a word owed to a stopped evaluation is taken and offered to nobody
  dropping := drop != 0ud2_0;
  word_valid := inner_data_one_slot_break_r.outs_valid;
  word_ready := dataOut_ready | dropping;
  accepted := addrIn_valid & inner_addr_one_slot_break_r.ins_ready;
  passed := word_valid & word_ready;
  owed_next := owed + (accepted ? 0ud2_1 : 0ud2_0) - (passed ? 0ud2_1 : 0ud2_0);

  ASSIGN
  init(owed) := 0ud2_0;
  next(owed) := owed_next;
  init(drop) := 0ud2_0;
  -- everything still owed after the kill cycle is the dead evaluation's
  next(drop) := kill ? owed_next : ((dropping & passed) ? drop - 0ud2_1 : drop);

  -- outputs
  DEFINE
  addrIn_ready := inner_addr_one_slot_break_r.ins_ready;
  addrOut := inner_addr_one_slot_break_r.outs;
  addrOut_valid := inner_addr_one_slot_break_r.outs_valid;
  dataFromMem_ready := inner_data_one_slot_break_r.ins_ready;
  dataOut := inner_data_one_slot_break_r.outs;
  dataOut_valid := word_valid & !dropping;

  addr_full := inner_addr_one_slot_break_r.full;
  data_full := inner_data_one_slot_break_r.full;

{generate_one_slot_break_r(f"{name}__addr_one_slot_break_r", {ATTR_BITWIDTH: addr_type.bitwidth})}
{generate_one_slot_break_r(f"{name}__data_one_slot_break_r", {ATTR_BITWIDTH: data_type.bitwidth})}
"""


def _generate_load(name, data_type, addr_type):
    return f"""
MODULE {name}(addrIn, addrIn_valid, dataFromMem, dataFromMem_valid, addrOut_ready, dataOut_ready)
  VAR
  inner_addr_one_slot_break_r : {name}__addr_one_slot_break_r(addrIn, addrIn_valid, addrOut_ready);
  inner_data_one_slot_break_r : {name}__data_one_slot_break_r(dataFromMem, dataFromMem_valid, dataOut_ready);

  -- outputs
  DEFINE
  addrIn_ready := inner_addr_one_slot_break_r.ins_ready;
  addrOut := inner_addr_one_slot_break_r.outs;
  addrOut_valid := inner_addr_one_slot_break_r.outs_valid;
  dataFromMem_ready := inner_data_one_slot_break_r.ins_ready;
  dataOut := inner_data_one_slot_break_r.outs;
  dataOut_valid := inner_data_one_slot_break_r.outs_valid;

  addr_full := inner_addr_one_slot_break_r.full;
  data_full := inner_data_one_slot_break_r.full;

{generate_one_slot_break_r(f"{name}__addr_one_slot_break_r", {ATTR_BITWIDTH: addr_type.bitwidth})}
{generate_one_slot_break_r(f"{name}__data_one_slot_break_r", {ATTR_BITWIDTH: data_type.bitwidth})}
"""
