from generators.support.signal_manager import generate_concat_signal_manager
from generators.support.signal_manager.utils.concat import get_concat_extra_signals_bitwidth
from generators.support.logic import generate_or_n
from generators.support.eager_fork_register_block import (
    generate_eager_fork_register_block,
)


def generate_fork(name, params):
    # Number of output ports
    size = params["size"]

    bitwidth = params["bitwidth"]
    extra_signals = params.get("extra_signals", None)

    if extra_signals:
        return _generate_fork_signal_manager(name, size, bitwidth, extra_signals)
    elif bitwidth == 0:
        return _generate_fork_dataless(name, size)
    else:
        return _generate_fork(name, size, bitwidth)


# From this many outputs on, the fork keeps its state against a phase
# (data/vhdl/handshake/dataless/fork.vhd says why, and is the same logic).
PHASE_MIN = 3


def _generate_fork_dataless(name, size):
    if size >= PHASE_MIN:
        return _generate_fork_dataless_phase(name, size)

    or_n_name = f"{name}_or_n"
    regblock_name = f"{name}_regblock"

    dependencies = generate_or_n(
        or_n_name, {"size": size}
    ) + generate_eager_fork_register_block(regblock_name)

    entity = f"""
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Entity of fork_dataless
entity {name} is
  port (
    clk : in std_logic;
    rst : in std_logic;
    -- input channel
    ins_valid : in  std_logic;
    ins_ready : out std_logic;
    -- output channels
    outs_valid : out std_logic_vector({size} - 1 downto 0);
    outs_ready : in  std_logic_vector({size} - 1 downto 0)
  );
end entity;
"""

    architecture = f"""
-- Architecture of fork_dataless
architecture arch of {name} is
  signal blockStopArray : std_logic_vector({size} - 1 downto 0);
  signal anyBlockStop   : std_logic;
  signal backpressure   : std_logic;
begin
  anyBlockFull : entity work.{or_n_name}
    port map(
      blockStopArray,
      anyBlockStop
    );

  ins_ready    <= not anyBlockStop;
  backpressure <= ins_valid and anyBlockStop;

  generateBlocks : for i in {size} - 1 downto 0 generate
    regblock : entity work.{regblock_name}(arch)
      port map(
        -- inputs
        clk          => clk,
        rst          => rst,
        ins_valid    => ins_valid,
        outs_ready   => outs_ready(i),
        backpressure => backpressure,
        -- outputs
        outs_valid => outs_valid(i),
        blockStop  => blockStopArray(i)
      );
  end generate;

end architecture;
"""

    return dependencies + entity + architecture


def _generate_fork_dataless_phase(name, size):
    entity = f"""
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Entity of fork_dataless
entity {name} is
  port (
    clk : in std_logic;
    rst : in std_logic;
    -- input channel
    ins_valid : in  std_logic;
    ins_ready : out std_logic;
    -- output channels
    outs_valid : out std_logic_vector({size} - 1 downto 0);
    outs_ready : in  std_logic_vector({size} - 1 downto 0)
  );
end entity;
"""

    # transmit(i), "output i still owes the token", is emitted(i) xor phase:
    # an output's transfer writes its own emitted(i), the token's completion
    # flips the phase alone, and a cycle without a valid input makes every
    # output owe again.
    architecture = f"""
-- Architecture of fork_dataless
architecture arch of {name} is
  signal phase        : std_logic;
  signal emitted      : std_logic_vector({size} - 1 downto 0);
  signal transmit     : std_logic_vector({size} - 1 downto 0);
  signal blockStop    : std_logic_vector({size} - 1 downto 0);
  signal anyBlockStop : std_logic;
  signal complete     : std_logic;
begin
  transmit  <= emitted xor ({size} - 1 downto 0 => phase);
  blockStop <= transmit and not outs_ready;
  anyBlockStop <= '0' when blockStop = ({size} - 1 downto 0 => '0') else '1';
  ins_ready  <= not anyBlockStop;
  outs_valid <= transmit and ({size} - 1 downto 0 => ins_valid);
  complete   <= ins_valid and not anyBlockStop;

  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        phase   <= '0';
        emitted <= (others => '1');
      else
        phase <= phase xor complete;
        for i in 0 to {size} - 1 loop
          if ins_valid = '0' then
            emitted(i) <= not phase;
          elsif transmit(i) = '1' and outs_ready(i) = '1' then
            emitted(i) <= phase;
          end if;
        end loop;
      end if;
    end if;
  end process;
end architecture;
"""

    return entity + architecture


def _generate_fork(name, size, bitwidth):
    inner_name = f"{name}_inner"

    dependencies = _generate_fork_dataless(inner_name, size)

    entity = f"""
library ieee;
use ieee.std_logic_1164.all;
use work.types.all;

-- Entity of fork
entity {name} is
  port (
    clk : in std_logic;
    rst : in std_logic;
    -- input channel
    ins       : in  std_logic_vector({bitwidth} - 1 downto 0);
    ins_valid : in  std_logic;
    ins_ready : out std_logic;
    -- output channels
    outs       : out data_array({size} - 1 downto 0)({bitwidth} - 1 downto 0);
    outs_valid : out std_logic_vector({size} - 1 downto 0);
    outs_ready : in  std_logic_vector({size} - 1 downto 0)
  );
end entity;
"""

    architecture = f"""
-- Architecture of fork
architecture arch of {name} is
begin
  control : entity work.{inner_name}
    port map(
      clk        => clk,
      rst        => rst,
      ins_valid  => ins_valid,
      ins_ready  => ins_ready,
      outs_valid => outs_valid,
      outs_ready => outs_ready
    );

  process (ins)
  begin
    for i in 0 to {size} - 1 loop
      outs(i) <= ins;
    end loop;
  end process;
end architecture;
"""

    return dependencies + entity + architecture


def _generate_fork_signal_manager(name, size, bitwidth, extra_signals):
    extra_signals_bitwidth = get_concat_extra_signals_bitwidth(extra_signals)
    return generate_concat_signal_manager(
        name,
        [{
            "name": "ins",
            "bitwidth": bitwidth,
            "extra_signals": extra_signals
        }],
        [{
            "name": "outs",
            "bitwidth": bitwidth,
            "extra_signals": extra_signals,
            "size": size
        }],
        extra_signals,
        lambda name: _generate_fork(name, size, bitwidth + extra_signals_bitwidth))
