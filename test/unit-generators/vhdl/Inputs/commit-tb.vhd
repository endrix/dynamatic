-- A testbench for handshake.commit, used by commit-ghdl.mlir: the unit under
-- test is named dut, a 3-bit payload, driven by commit-vectors.txt one line a
-- cycle (written by ../../verilog/Inputs/commit_spec.py, the requirement of
-- the form under test): the inputs set, the combinational outputs checked,
-- the clock ticks. Fails (severity failure) on the first thing wrong.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity tb is
end entity;

architecture sim of tb is
  signal clk : std_logic := '0';
  signal rst, ins_valid, outs_ready : std_logic := '0';
  signal outs_valid, ins_ready, kill : std_logic;
  signal ins, outs : std_logic_vector(2 downto 0) := (others => '0');
begin
  clk <= not clk after 5 ns;

  dut : entity work.dut
    port map (clk => clk, rst => rst, ins => ins, ins_valid => ins_valid,
              ins_ready => ins_ready, outs => outs, outs_valid => outs_valid,
              outs_ready => outs_ready, kill => kill);

  process
    file f : text open read_mode is "commit-vectors.txt";
    variable l : line;
    variable cycle : integer := 0;
    variable e : integer_vector(0 to 7);
  begin
    wait for 1 ns;
    while not endfile(f) loop
      readline(f, l);
      if l'length > 0 and l(l'left) /= '#' then
        for i in 0 to 7 loop
          read(l, e(i));
        end loop;
        rst <= '1' when e(0) = 1 else '0';
        ins_valid <= '1' when e(1) = 1 else '0';
        ins <= std_logic_vector(to_unsigned(e(2), 3));
        outs_ready <= '1' when e(3) = 1 else '0';
        wait for 1 ns;
        assert (outs_valid = '1') = (e(4) = 1)
          report "cycle " & integer'image(cycle) & ": outs_valid " & std_logic'image(outs_valid)
          severity failure;
        assert to_integer(unsigned(outs)) = e(5)
          report "cycle " & integer'image(cycle) & ": outs " & integer'image(to_integer(unsigned(outs)))
          severity failure;
        assert (ins_ready = '1') = (e(6) = 1)
          report "cycle " & integer'image(cycle) & ": ins_ready " & std_logic'image(ins_ready)
          severity failure;
        assert (kill = '1') = (e(7) = 1)
          report "cycle " & integer'image(cycle) & ": kill " & std_logic'image(kill)
          severity failure;
        wait until rising_edge(clk);
        wait for 1 ns;
        cycle := cycle + 1;
      end if;
    end loop;
    report "commit: " & integer'image(cycle) & " cycles as expected";
    std.env.finish;
  end process;
end architecture;
