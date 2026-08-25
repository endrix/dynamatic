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



def generate_bundle(name, params):
    """`handshake.bundle` joins individual signals back into a channel-like
    value. The exact inverse of `handshake.unbundle`; see that generator.

      control: valid -> (control, ready)    -- valid -> ctrl, ready
      channel: (control, data) -> channel   -- ctrl, data -> outs
    """
    form = params["form"]
    data_width = params["data_width"]

    if form == "channel":
        return _generate_bundle_channel(name, data_width)
    return _generate_bundle_control(name)


def _generate_bundle_channel(name, data_width):
    entity = f"""
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Entity of bundle (control + data -> channel)
entity {name} is
  port (
    clk : in std_logic;
    rst : in std_logic;
    -- input control
    ctrl_valid : in std_logic;
    ctrl_ready : out std_logic;
    -- input data, a bare signal with no handshake of its own
    {data(_raw_port("data", "in", data_width) + ";", data_width)}
    -- output channel
    {data(f"outs : out std_logic_vector({data_width} - 1 downto 0);", data_width)}
    outs_valid : out std_logic;
    outs_ready : in std_logic
  );
end entity;
"""

    architecture = f"""
-- Architecture of bundle (control + data -> channel)
architecture arch of {name} is
begin
  outs_valid <= ctrl_valid;
  ctrl_ready <= outs_ready;
  {data("outs(0) <= data;" if data_width == 1 else "outs <= data;", data_width)}
end architecture;
"""

    return entity + architecture


def _generate_bundle_control(name):
    entity = f"""
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Entity of bundle (valid -> control, yielding ready)
entity {name} is
  port (
    clk : in std_logic;
    rst : in std_logic;
    -- valid is supplied as a bare signal
    valid : in std_logic;
    -- output control
    ctrl_valid : out std_logic;
    ctrl_ready : in std_logic;
    -- ready is handed back as a bare signal
    ready : out std_logic
  );
end entity;
"""

    architecture = f"""
-- Architecture of bundle (valid -> control, yielding ready)
architecture arch of {name} is
begin
  ctrl_valid <= valid;
  ready      <= ctrl_ready;
end architecture;
"""

    return entity + architecture
