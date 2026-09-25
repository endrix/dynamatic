from generators.support.signal_manager import generate_concat_signal_manager
from generators.support.signal_manager.utils.concat import get_concat_extra_signals_bitwidth


def generate_init(name, params):
    bitwidth = params["bitwidth"]
    extra_signals = params.get("extra_signals", None)
    # The initial value to use for the buffer
    initial_value = params.get("initial_value", 0)

    if extra_signals:
        return _generate_init_signal_manager(name, bitwidth, extra_signals, initial_value)
    elif bitwidth == 0:
        return _generate_init_dataless(name)
    else:
        return _generate_init(name, bitwidth, initial_value)


def _generate_init_dataless(name):

    entity = f"""
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Entity of init_dataless
entity {name} is
  port (
    clk, rst : in std_logic;
    -- input channel
    ins_valid : in  std_logic;
    ins_ready : out std_logic;
    -- output channel
    outs_valid : out std_logic;
    outs_ready : in  std_logic
  );
end entity;
"""

    architecture = f"""
-- Architecture of init_dataless
architecture arch of {name} is
  signal fullReg, outputValid : std_logic;
begin
  outputValid <= ins_valid or fullReg;

  process (clk) is
  begin
    if (rising_edge(clk)) then
      if (rst = '1') then
        fullReg <= '1';
      else
        fullReg <= outputValid and not outs_ready;
      end if;
    end if;
  end process;

  ins_ready  <= not fullReg;
  outs_valid <= outputValid;
end architecture;
"""

    return entity + architecture


def _reset_bits(name, bitwidth, initial_value, value_bitwidth):
    """The register's reset value as a VHDL bit string of `bitwidth` bits: the
    integer `initial_value` at the channel's data width `value_bitwidth`, a
    negative one in two's complement, and the bits above it (the extra
    signals the signal manager concatenates over the data) zero.

    The value is the integer, whatever it is: 1 on an 8-bit channel is
    "00000001". (Until 2026-09 a 0 or a 1 was replicated over the width,
    `(others => '1')`, so a state variable wider than one bit that starts at
    1 came out of reset as -1.)"""
    initial_value = int(initial_value)
    if value_bitwidth == 0:
        # dataless, its extra signals alone in the register: no value to hold
        return f'"{0:0{bitwidth}b}"'
    if not -(1 << (value_bitwidth - 1)) <= initial_value < (1 << value_bitwidth):
        raise ValueError(
            f"init {name}: initial value {initial_value} does not fit {value_bitwidth} bits")
    bits = initial_value & ((1 << value_bitwidth) - 1)
    return f'"{bits:0{bitwidth}b}"'


def _generate_init(name, bitwidth, initial_value, value_bitwidth=None):
    init_dataless_name = f"{name}_dataless"

    dependencies = _generate_init_dataless(
        init_dataless_name)

    # The register's reset value: the integer at the data's width (an actor's
    # state variable that starts at 4, a one-bit token that starts at 1).
    dataReg_reset = _reset_bits(
        name, bitwidth, initial_value,
        bitwidth if value_bitwidth is None else value_bitwidth)

    entity = f"""
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Entity of init
entity {name} is
  port (
    clk, rst : in std_logic;
    -- input channel
    ins       : in  std_logic_vector({bitwidth} - 1 downto 0);
    ins_valid : in  std_logic;
    ins_ready : out std_logic;
    -- output channel
    outs       : out std_logic_vector({bitwidth} - 1 downto 0);
    outs_valid : out std_logic;
    outs_ready : in  std_logic
  );
end entity;
"""

    architecture = f"""
-- Architecture of init
architecture arch of {name} is
  signal regEnable, regNotFull : std_logic;
  signal dataReg               : std_logic_vector({bitwidth} - 1 downto 0);
begin
  regEnable <= regNotFull and ins_valid and not outs_ready;

  control : entity work.{init_dataless_name}
    port map(
      clk        => clk,
      rst        => rst,
      ins_valid  => ins_valid,
      ins_ready  => regNotFull,
      outs_valid => outs_valid,
      outs_ready => outs_ready
    );

  process (clk) is
  begin
    if (rising_edge(clk)) then
      if (rst = '1') then
        dataReg <= {dataReg_reset};
      elsif (regEnable) then
        dataReg <= ins;
      end if;
    end if;
  end process;

  process (regNotFull, dataReg, ins) is
  begin
    if (regNotFull) then
      outs <= ins;
    else
      outs <= dataReg;
    end if;
  end process;

  ins_ready <= regNotFull;

end architecture;
"""

    return dependencies + entity + architecture


def _generate_init_signal_manager(name, bitwidth, extra_signals, initial_value):
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
            "extra_signals": extra_signals
        }],
        extra_signals,
        lambda name: _generate_init(name, bitwidth + extra_signals_bitwidth, initial_value,
                                    bitwidth))
