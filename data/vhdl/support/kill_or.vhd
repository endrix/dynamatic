library ieee;
use ieee.std_logic_1164.all;

-- The kill of a domain with several commits (`handshake.commit`): the OR of
-- their kills, which HandshakeToHW gives the domain's units as their reset.
-- SIZE one-bit inputs, one output; combinational, no clock and no reset (each
-- commit's kill has the reset in it already). Not a Handshake unit: the
-- lowering's own, as mem_to_bram is. The same circuit as the generator's
-- (tools/unit-generators/vhdl/generators/support/kill_or.py), with the size
-- lifted into a generic.
entity kill_or is
  generic (
    SIZE : integer
  );
  port (
    -- the kills of the domain's commits
    ins  : in  std_logic_vector(SIZE - 1 downto 0);
    -- the domain's kill
    outs : out std_logic
  );
end entity;

architecture arch of kill_or is
  constant NO_KILL : std_logic_vector(SIZE - 1 downto 0) := (others => '0');
begin
  outs <= '0' when ins = NO_KILL else '1';
end architecture;
