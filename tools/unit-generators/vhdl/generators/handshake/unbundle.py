from generators.support.utils import data

def _raw_port(name, direction, width):
    """Declaration for a BARE data port, one not part of a channel.

    The exporter declares a raw signal of width 1 as a scalar `std_logic`,
    reserving `std_logic_vector` for wider ones -- unlike a channel's data,
    which is always a vector, `std_logic_vector(0 downto 0)` included. Getting
    this wrong fails in GHDL with "can't associate ... with port", so the two
    conventions have to be kept apart.
    """
    if width == 1:
        return f"{name} : {direction} std_logic"
    return f"{name} : {direction} std_logic_vector({width} - 1 downto 0)"



def generate_unbundle(name, params):
    """`handshake.unbundle` splits a channel-like value into its signals.

    Two forms, told apart by FORM because they share an op name and would
    otherwise collide on one external module with incompatible ports:

      channel: channel -> (control, data)   -- ins -> ctrl, data
      control: (control, ready) -> valid    -- ins, ready -> valid

    Both are pure rewiring. They exist so that a circuit can OBSERVE a
    channel's protocol signals -- which is the one thing the channel
    abstraction cannot express, since reading a channel consumes it.
    """
    form = params["form"]
    data_width = params["data_width"]

    if form == "channel":
        return _generate_unbundle_channel(name, data_width)
    return _generate_unbundle_control(name)


def _generate_unbundle_channel(name, data_width):
    entity = f"""
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Entity of unbundle (channel -> control + data)
entity {name} is
  port (
    clk : in std_logic;
    rst : in std_logic;
    -- input channel
    {data(f"ins : in std_logic_vector({data_width} - 1 downto 0);", data_width)}
    ins_valid : in std_logic;
    ins_ready : out std_logic;
    -- output control
    ctrl_valid : out std_logic;
    ctrl_ready : in std_logic;
    -- output data, a bare signal with no handshake of its own
    {data(_raw_port("data", "out", data_width), data_width)}
  );
end entity;
"""

    architecture = f"""
-- Architecture of unbundle (channel -> control + data)
architecture arch of {name} is
begin
  ctrl_valid <= ins_valid;
  ins_ready  <= ctrl_ready;
  {data("data <= ins(0);" if data_width == 1 else "data <= ins;", data_width)}
end architecture;
"""

    return entity + architecture


def _generate_unbundle_control(name):
    entity = f"""
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Entity of unbundle (control -> valid, taking ready)
entity {name} is
  port (
    clk : in std_logic;
    rst : in std_logic;
    -- input control
    ins_valid : in std_logic;
    ins_ready : out std_logic;
    -- ready is supplied by the consumer as a bare signal
    ready : in std_logic;
    -- valid is produced as a bare signal
    valid : out std_logic
  );
end entity;
"""

    architecture = f"""
-- Architecture of unbundle (control -> valid, taking ready)
architecture arch of {name} is
begin
  valid     <= ins_valid;
  ins_ready <= ready;
end architecture;
"""

    return entity + architecture
