def generate_kill_or(name, params):
    """The kill of a domain with several commits (`handshake.commit`): the OR
    of their kills, which HandshakeToHW gives the domain's units as their
    reset. `size` one-bit inputs, `ins`, one output, `outs`; combinational,
    no clock and no reset (each commit's kill has the reset in it already).
    Not a Handshake unit: the lowering's own, as mem_to_bram is.
    """
    size = params["size"]
    if size < 2:
        raise ValueError(
            "kill_or ORs the kills of a domain's commits, and the lowering "
            "builds one only for a domain with two or more")

    entity = f"""
library ieee;
use ieee.std_logic_1164.all;

-- Entity of kill_or
entity {name} is
  port (
    -- the kills of the domain's commits
    ins  : in  std_logic_vector({size} - 1 downto 0);
    -- the domain's kill
    outs : out std_logic
  );
end entity;
"""

    architecture = f"""
-- Architecture of kill_or
architecture arch of {name} is
  constant NO_KILL : std_logic_vector({size} - 1 downto 0) := (others => '0');
begin
  outs <= '0' when ins = NO_KILL else '1';
end architecture;
"""

    return entity + architecture
