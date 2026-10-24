

from generators.support.signal_manager.utils.entity import generate_entity
from generators.support.signal_manager.utils.concat import ConcatLayout
from generators.support.signal_manager.utils.generation import generate_concat, generate_slice
from generators.handshake.buffers.one_slot_break_r import generate_one_slot_break_r
from generators.handshake.buffers.fifo_break_dv import generate_fifo_break_dv


def generate_load(name, params):
    addr_bitwidth = params["addr_bitwidth"]
    data_bitwidth = params["data_bitwidth"]
    extra_signals = params.get("extra_signals", None)

    if params.get("kill_drop", 0):
        if extra_signals:
            raise ValueError(
                "a load that drops on a kill carries no extra signals: its "
                "words are counted, not tagged")
        return _generate_load_kill_drop(name, data_bitwidth, addr_bitwidth)
    if extra_signals:
        return _generate_load_signal_manager(name, data_bitwidth, addr_bitwidth, extra_signals)
    else:
        return _generate_load(name, data_bitwidth, addr_bitwidth)


def _generate_load_kill_drop(name, data_bitwidth, addr_bitwidth):
    """A load whose requester a commit can stop (`handshake.kill_domain`).

    The memory controller cannot forget a granted read -- it holds the word,
    valid, until the load takes it -- and an address in the load's own slot
    will be granted in its turn: neither can be withdrawn without breaking
    the protocol. So the load is not reset with the units it serves. It
    counts the words it owes them (addresses accepted, less words passed on)
    and, on `kill`, every word owed after that cycle is a dead evaluation's:
    `drop` of them are taken from the controller and thrown away, nothing
    offered to the (reset) requester meanwhile. Words come back in the order
    their addresses went, so the dropped ones are the first. At most three
    are owed: the address slot, the controller's word register for this
    port, the data slot -- two bits.
    """
    addr_one_slot_break_r_name = f"{name}_addr_one_slot_break_r"
    data_one_slot_break_r_name = f"{name}_data_one_slot_break_r"

    dependencies = \
        generate_one_slot_break_r(addr_one_slot_break_r_name, {"bitwidth": addr_bitwidth}) + \
        generate_one_slot_break_r(data_one_slot_break_r_name, {"bitwidth": data_bitwidth})

    entity = f"""
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Entity of load (dropping on a kill)
entity {name} is
  port (
    clk : in std_logic;
    rst : in std_logic;
    -- address from circuit channel
    addrIn       : in  std_logic_vector({addr_bitwidth} - 1 downto 0);
    addrIn_valid : in  std_logic;
    addrIn_ready : out std_logic;
    -- address to interface channel
    addrOut       : out std_logic_vector({addr_bitwidth} - 1 downto 0);
    addrOut_valid : out std_logic;
    addrOut_ready : in  std_logic;
    -- data from interface channel
    dataFromMem       : in  std_logic_vector({data_bitwidth} - 1 downto 0);
    dataFromMem_valid : in  std_logic;
    dataFromMem_ready : out std_logic;
    -- data from memory channel
    dataOut       : out std_logic_vector({data_bitwidth} - 1 downto 0);
    dataOut_valid : out std_logic;
    dataOut_ready : in  std_logic;
    -- the requester was stopped: what it is owed is dropped
    kill : in std_logic
  );
end entity;
"""

    architecture = f"""
-- Architecture of load (dropping on a kill)
architecture arch of {name} is
  signal addr_ready, word_valid, word_ready : std_logic;
  signal accepted, passed, dropping         : std_logic;
  signal owed, drop                         : unsigned(1 downto 0);
begin
  addr_one_slot_break_r : entity work.{addr_one_slot_break_r_name}(arch)
    port map(
      clk => clk,
      rst => rst,
      -- input channel
      ins       => addrIn,
      ins_valid => addrIn_valid,
      ins_ready => addr_ready,
      -- output channel
      outs       => addrOut,
      outs_valid => addrOut_valid,
      outs_ready => addrOut_ready
    );

  data_one_slot_break_r : entity work.{data_one_slot_break_r_name}(arch)
    port map(
      clk => clk,
      rst => rst,
      -- input channel
      ins       => dataFromMem,
      ins_valid => dataFromMem_valid,
      ins_ready => dataFromMem_ready,
      -- output channel
      outs       => dataOut,
      outs_valid => word_valid,
      outs_ready => word_ready
    );

  addrIn_ready  <= addr_ready;
  -- A word owed to a stopped evaluation is taken and offered to nobody.
  dropping      <= '1' when drop /= 0 else '0';
  dataOut_valid <= word_valid and not dropping;
  word_ready    <= dataOut_ready or dropping;

  accepted <= addrIn_valid and addr_ready;
  passed   <= word_valid and word_ready;

  process (clk) is
    variable owed_next : unsigned(1 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        owed <= (others => '0');
        drop <= (others => '0');
      else
        owed_next := owed;
        if accepted = '1' then
          owed_next := owed_next + 1;
        end if;
        if passed = '1' then
          owed_next := owed_next - 1;
        end if;
        owed <= owed_next;
        -- Everything still owed after the kill cycle is the dead
        -- evaluation's: an address accepted in it included, a word passed on
        -- in it not.
        if kill = '1' then
          drop <= owed_next;
        elsif dropping = '1' and passed = '1' then
          drop <= drop - 1;
        end if;
      end if;
    end if;
  end process;
end architecture;
"""

    return dependencies + entity + architecture


def _generate_load(name, data_bitwidth, addr_bitwidth):
    addr_one_slot_break_r_name = f"{name}_addr_one_slot_break_r"
    data_one_slot_break_r_name = f"{name}_data_one_slot_break_r"

    dependencies = \
        generate_one_slot_break_r(addr_one_slot_break_r_name, {"bitwidth": addr_bitwidth}) + \
        generate_one_slot_break_r(data_one_slot_break_r_name, {"bitwidth": data_bitwidth})

    entity = f"""
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Entity of load
entity {name} is
  port (
    clk : in std_logic;
    rst : in std_logic;
    -- address from circuit channel
    addrIn       : in  std_logic_vector({addr_bitwidth} - 1 downto 0);
    addrIn_valid : in  std_logic;
    addrIn_ready : out std_logic;
    -- address to interface channel
    addrOut       : out std_logic_vector({addr_bitwidth} - 1 downto 0);
    addrOut_valid : out std_logic;
    addrOut_ready : in  std_logic;
    -- data from interface channel
    dataFromMem       : in  std_logic_vector({data_bitwidth} - 1 downto 0);
    dataFromMem_valid : in  std_logic;
    dataFromMem_ready : out std_logic;
    -- data from memory channel
    dataOut       : out std_logic_vector({data_bitwidth} - 1 downto 0);
    dataOut_valid : out std_logic;
    dataOut_ready : in  std_logic
  );
end entity;
"""

    architecture = f"""
-- Architecture of load
architecture arch of {name} is
begin
  addr_one_slot_break_r : entity work.{addr_one_slot_break_r_name}(arch)
    port map(
      clk => clk,
      rst => rst,
      -- input channel
      ins       => addrIn,
      ins_valid => addrIn_valid,
      ins_ready => addrIn_ready,
      -- output channel
      outs       => addrOut,
      outs_valid => addrOut_valid,
      outs_ready => addrOut_ready
    );

  data_one_slot_break_r : entity work.{data_one_slot_break_r_name}(arch)
    port map(
      clk => clk,
      rst => rst,
      -- input channel
      ins       => dataFromMem,
      ins_valid => dataFromMem_valid,
      ins_ready => dataFromMem_ready,
      -- output channel
      outs       => dataOut,
      outs_valid => dataOut_valid,
      outs_ready => dataOut_ready
    );
end architecture;
"""

    return dependencies + entity + architecture


def _generate_load_signal_manager(name, data_bitwidth, addr_bitwidth, extra_signals):
    # Concatenate extra signals and store them in a dedicated FIFO

    # Get concatenation details for extra signals
    concat_layout = ConcatLayout(extra_signals)
    extra_signals_total_bitwidth = concat_layout.total_bitwidth

    inner_name = f"{name}_inner"
    inner = _generate_load(inner_name, data_bitwidth, addr_bitwidth)

    # Generate fifo_break_dv to store extra signals for in-flight memory requests
    fifo_break_dv_name = f"{name}_fifo_break_dv"
    fifo_break_dv = generate_fifo_break_dv(fifo_break_dv_name, {
        "bitwidth": extra_signals_total_bitwidth,
        "num_slots": 1  # Assume LoadOp is connected to a memory controller
    })

    entity = generate_entity(name, [{
        "name": "addrIn",
        "bitwidth": addr_bitwidth,
        "extra_signals": extra_signals
    }, {
        "name": "dataFromMem",
        "bitwidth": data_bitwidth,
        "extra_signals": {}
    }], [{
        "name": "addrOut",
        "bitwidth": addr_bitwidth,
        "extra_signals": {}
    }, {
        "name": "dataOut",
        "bitwidth": data_bitwidth,
        "extra_signals": extra_signals
    }])

    assignments = []

    # Concatenate addrIn extra signals to create signals_pre_buffer
    assignments.extend(generate_concat(
        "addrIn", 0, "signals_pre_buffer", concat_layout))

    # Slice signals_post_buffer to create dataOut data and extra signals
    assignments.extend(generate_slice(
        "signals_post_buffer", "dataOut", 0, concat_layout))

    architecture = f"""
-- Architecture of load signal manager
architecture arch of {name} is
  signal signals_pre_buffer, signals_post_buffer : std_logic_vector({concat_layout.total_bitwidth} - 1 downto 0);
  signal transfer_in, transfer_out : std_logic;
begin
  -- Transfer signal assignments
  transfer_in <= addrIn_valid and addrIn_ready;
  transfer_out <= dataOut_valid and dataOut_ready;

  -- Concat/slice extra signals
  {"\n  ".join(assignments)}

  -- Buffer to store extra signals for in-flight memory requests
  -- LoadOp is assumed to be connected to a memory controller
  -- Use fifo_break_dv with latency 1 (MC latency)
  fifo_break_dv : entity work.{fifo_break_dv_name}(arch)
    port map(
      clk => clk,
      rst => rst,
      ins => signals_pre_buffer,
      ins_valid => transfer_in,
      ins_ready => open,
      outs => signals_post_buffer,
      outs_valid => open,
      outs_ready => transfer_out
    );

  inner : entity work.{inner_name}(arch)
    port map(
      clk => clk,
      rst => rst,
      addrIn => addrIn,
      addrIn_valid => addrIn_valid,
      addrIn_ready => addrIn_ready,
      addrOut => addrOut,
      addrOut_valid => addrOut_valid,
      addrOut_ready => addrOut_ready,
      dataFromMem => dataFromMem,
      dataFromMem_valid => dataFromMem_valid,
      dataFromMem_ready => dataFromMem_ready,
      dataOut => dataOut,
      dataOut_valid => dataOut_valid,
      dataOut_ready => dataOut_ready
    );
end architecture;
"""

    return inner + fifo_break_dv + entity + architecture
