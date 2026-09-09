# A unit on raw wires: no valid, no ready, nothing clocked. This is what an
# `arith` operation on plain integers becomes -- the logic a handshake function
# holds between an `unbundle` and the `bundle` that times its result on a
# control. The ports carry the wires and nothing else. `clk` and `rst` are
# declared because every instance is handed them; nothing here reads them.
#
# A raw signal of one bit is a `std_logic`, the way the exporter and the
# bundle declare it, while the arithmetic wants vectors. Every port is mirrored
# by a vector signal of its width, and the width-one case is the (0 => x)
# aggregate in one direction and a bit select in the other.


def raw_port(name, width, direction):
    if width == 1:
        return f"{name} : {direction} std_logic"
    return f"{name} : {direction} std_logic_vector({width} - 1 downto 0)"


def raw_to_vector(name, width):
    """`name_v <= name`, widened to a vector when the port is one bit."""
    if width == 1:
        return f"  {name}_v <= (0 => {name});"
    return f"  {name}_v <= {name};"


def vector_to_raw(name, width):
    """`name <= name_v`, narrowed to a bit when the port is one bit."""
    if width == 1:
        return f"  {name} <= {name}_v(0);"
    return f"  {name} <= {name}_v;"


def generate_raw_unit(name, op, inputs, outputs, body, signals=""):
    """
    Args:
        name: Unique entity name (e.g. arith_addi_0).
        op: The arith operation, for the comment.
        inputs: (port, width) pairs, in port order.
        outputs: (port, width) pairs, in port order.
        body: VHDL over the `_v` vector signals of the ports.
        signals: Further signal declarations the body needs.
    """
    ports = ["clk : in std_logic", "rst : in std_logic"]
    ports += [raw_port(p, w, "in") for p, w in inputs]
    ports += [raw_port(p, w, "out") for p, w in outputs]
    port_list = ";\n    ".join(ports)

    vectors = "\n".join(
        f"  signal {p}_v : std_logic_vector({w} - 1 downto 0);"
        for p, w in inputs + outputs)
    wrap = "\n".join(raw_to_vector(p, w) for p, w in inputs)
    unwrap = "\n".join(vector_to_raw(p, w) for p, w in outputs)

    return f"""
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Entity of {op} on raw wires
entity {name} is
  port (
    {port_list}
  );
end entity;

-- Architecture of {op} on raw wires
architecture arch of {name} is
{vectors}
{signals}
begin
{wrap}
{body}
{unwrap}
end architecture;
"""
