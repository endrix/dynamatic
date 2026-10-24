-- The static kill_or (data/vhdl/support/kill_or.vhd, the entity the vivado
-- configuration emits) with three kills, under the generator's name, so that
-- kill-or-tb.vhd drives both.
library ieee;
use ieee.std_logic_1164.all;

entity dut is
  port (
    ins  : in  std_logic_vector(2 downto 0);
    outs : out std_logic
  );
end entity;

architecture arch of dut is
begin
  k : entity work.kill_or generic map (SIZE => 3) port map (ins => ins, outs => outs);
end architecture;
