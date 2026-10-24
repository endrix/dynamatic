-- A testbench for kill-or-ghdl.mlir: `dut`, a kill_or of three kills (the
-- generator's, or the static entity under that name), driven with every
-- combination of its inputs; its output must be their OR. Fails (severity
-- failure) on the first wrong one.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb is
end entity;

architecture sim of tb is
  signal ins  : std_logic_vector(2 downto 0) := (others => '0');
  signal outs : std_logic;
begin
  dut : entity work.dut port map (ins => ins, outs => outs);
  process
    variable expected : std_logic;
  begin
    for i in 0 to 7 loop
      ins <= std_logic_vector(to_unsigned(i, 3));
      wait for 1 ns;
      if i = 0 then expected := '0'; else expected := '1'; end if;
      assert outs = expected
        report "kill_or: inputs " & integer'image(i) & ", outs " & std_logic'image(outs)
        severity failure;
    end loop;
    report "kill_or: 8 combinations as expected";
    std.env.finish;
  end process;
end architecture;
