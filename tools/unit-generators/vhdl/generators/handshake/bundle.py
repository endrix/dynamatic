from generators.support.utils import data


def _raw_port(name, direction, width):
    """See unbundle.py: a bare port of width 1 is a scalar, unlike a channel's
    data or extra signals, which are always vectors."""
    if width == 1:
        return f"{name} : {direction} std_logic"
    return f"{name} : {direction} std_logic_vector({width} - 1 downto 0)"


def _chan_extra_port(channel, signal, direction, width):
    """A channel's extra signal, which is always a vector."""
    return f"{channel}_{signal} : {direction} std_logic_vector({width} - 1 downto 0)"


def generate_bundle(name, params):
    """`handshake.bundle` joins individual signals back into a channel-like
    value. The exact inverse of `handshake.unbundle`; see that generator.

      control: valid -> (control, ready)             -- valid -> ctrl, ready
      channel: (control, data, extras) -> channel    -- ctrl, data, ... -> outs
    """
    form = params["form"]
    data_width = params["data_width"]
    extra_down = params.get("extra_down", {}) or {}
    extra_up = params.get("extra_up", {}) or {}

    if form == "channel":
        return _generate_bundle_channel(name, data_width, extra_down, extra_up)
    return _generate_bundle_control(name)


def _generate_bundle_channel(name, data_width, extra_down, extra_up):
    ports = ["ctrl_valid : in std_logic", "ctrl_ready : out std_logic"]
    if data_width > 0:
        ports.append(_raw_port("data", "in", data_width))
    # Mirror of unbundle: a downstream extra is consumed and sent on with the
    # data, an upstream one arrives from the consumer and is handed back.
    for sig, width in extra_down.items():
        ports.append(_raw_port(sig, "in", width))
    for sig, width in extra_up.items():
        ports.append(_raw_port(sig, "out", width))
    if data_width > 0:
        ports.append(f"outs : out std_logic_vector({data_width} - 1 downto 0)")
    ports.append("outs_valid : out std_logic")
    ports.append("outs_ready : in std_logic")
    for sig, width in extra_down.items():
        ports.append(_chan_extra_port("outs", sig, "out", width))
    for sig, width in extra_up.items():
        ports.append(_chan_extra_port("outs", sig, "in", width))

    body = ["outs_valid <= ctrl_valid;", "ctrl_ready <= outs_ready;"]
    if data_width > 0:
        body.append("outs(0) <= data;" if data_width == 1 else "outs <= data;")
    for sig, width in extra_down.items():
        body.append(f"outs_{sig}(0) <= {sig};" if width == 1
                    else f"outs_{sig} <= {sig};")
    for sig, width in extra_up.items():
        body.append(f"{sig} <= outs_{sig}(0);" if width == 1
                    else f"{sig} <= outs_{sig};")

    port_block = ";\n    ".join(ports)
    body_block = "\n  ".join(body)
    return f"""
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Entity of bundle (control + data + extras -> channel)
entity {name} is
  port (
    clk : in std_logic;
    rst : in std_logic;
    {port_block}
  );
end entity;

-- Architecture of bundle (control + data + extras -> channel)
architecture arch of {name} is
begin
  {body_block}
end architecture;
"""


def _generate_bundle_control(name):
    return f"""
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

-- Architecture of bundle (valid -> control, yielding ready)
architecture arch of {name} is
begin
  ctrl_valid <= valid;
  ready      <= ctrl_ready;
end architecture;
"""
