from generators.support.utils import data


def _raw_port(name, direction, width):
    """Declaration for a BARE port, one not part of a channel.

    The exporter declares a raw signal of width 1 as a scalar `std_logic`,
    reserving `std_logic_vector` for wider ones -- unlike a channel's data or
    its extra signals, which are always vectors, `(0 downto 0)` included.
    Getting this wrong fails in GHDL with "can't associate ... with port".
    """
    if width == 1:
        return f"{name} : {direction} std_logic"
    return f"{name} : {direction} std_logic_vector({width} - 1 downto 0)"


def _chan_extra_port(channel, signal, direction, width):
    """A channel's extra signal, which is always a vector."""
    return f"{channel}_{signal} : {direction} std_logic_vector({width} - 1 downto 0)"


def generate_unbundle(name, params):
    """`handshake.unbundle` splits a channel-like value into its signals.

    Two forms, told apart by FORM because they share an op name and would
    otherwise collide on one external module with incompatible ports:

      channel: channel -> (control, data, extras)  -- ins -> ctrl, data, ...
      control: (control, ready) -> valid           -- ins, ready -> valid

    All of it is pure rewiring. It exists so a circuit can OBSERVE a channel's
    protocol signals and its extra signals, which is the one thing the channel
    abstraction cannot express: reading a channel consumes it.

    Extra signals are split out INDIVIDUALLY, each keeping its own name, rather
    than concatenated the way the signal-manager units tunnel them -- the point
    here is to read one by name. Direction decides which side a signal sits on:
    a downstream extra travels with the data and is read out, an upstream one
    travels against it and is driven in.
    """
    form = params["form"]
    data_width = params["data_width"]
    extra_down = params.get("extra_down", {}) or {}
    extra_up = params.get("extra_up", {}) or {}

    if form == "channel":
        return _generate_unbundle_channel(name, data_width, extra_down, extra_up)
    return _generate_unbundle_control(name)


def _generate_unbundle_channel(name, data_width, extra_down, extra_up):
    ports = []
    if data_width > 0:
        ports.append(f"ins : in std_logic_vector({data_width} - 1 downto 0)")
    ports.append("ins_valid : in std_logic")
    ports.append("ins_ready : out std_logic")
    # On an INPUT channel a downstream extra arrives with the data; an upstream
    # one is driven back out, like ready.
    for sig, width in extra_down.items():
        ports.append(_chan_extra_port("ins", sig, "in", width))
    for sig, width in extra_up.items():
        ports.append(_chan_extra_port("ins", sig, "out", width))
    ports.append("ctrl_valid : out std_logic")
    ports.append("ctrl_ready : in std_logic")
    if data_width > 0:
        ports.append(_raw_port("data", "out", data_width))
    for sig, width in extra_down.items():
        ports.append(_raw_port(sig, "out", width))
    for sig, width in extra_up.items():
        ports.append(_raw_port(sig, "in", width))

    body = ["ctrl_valid <= ins_valid;", "ins_ready  <= ctrl_ready;"]
    if data_width > 0:
        body.append("data <= ins(0);" if data_width == 1 else "data <= ins;")
    for sig, width in extra_down.items():
        body.append(f"{sig} <= ins_{sig}(0);" if width == 1
                    else f"{sig} <= ins_{sig};")
    for sig, width in extra_up.items():
        body.append(f"ins_{sig}(0) <= {sig};" if width == 1
                    else f"ins_{sig} <= {sig};")

    port_block = ";\n    ".join(ports)
    body_block = "\n  ".join(body)
    return f"""
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Entity of unbundle (channel -> control + data + extras)
entity {name} is
  port (
    clk : in std_logic;
    rst : in std_logic;
    {port_block}
  );
end entity;

-- Architecture of unbundle (channel -> control + data + extras)
architecture arch of {name} is
begin
  {body_block}
end architecture;
"""


def _generate_unbundle_control(name):
    return f"""
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

-- Architecture of unbundle (control -> valid, taking ready)
architecture arch of {name} is
begin
  valid     <= ins_valid;
  ins_ready <= ready;
end architecture;
"""
