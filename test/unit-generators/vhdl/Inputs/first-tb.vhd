-- A testbench for handshake.first, used by first-ghdl.mlir: the unit under
-- test is named dut, three inputs of two bits, driven by the rounds of
-- first-vectors.txt one a cycle -- the inputs set, the combinational outputs
-- checked against the requirement's, the clock ticks. Random rounds, each
-- input's token held until taken, the sink stalling at random: the first
-- carrying payload to arrive wins, an all-zero round answers zero, an input
-- that gave its token is not ready again until the round completes, and is
-- ready in the cycle it does, the next round's token taken then and its winner
-- answered then when the round's answer went out before. Fails (severity
-- failure) on the first thing wrong.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use work.types.all;

entity tb is
end entity;

architecture sim of tb is
  signal clk, rst : std_logic := '1';
  signal ins : data_array(2 downto 0)(1 downto 0) := (others => (others => '0'));
  signal ins_valid, ins_ready : std_logic_vector(2 downto 0) := (others => '0');
  signal outs : std_logic_vector(1 downto 0);
  signal outs_valid, outs_ready : std_logic := '0';
begin
  clk <= not clk after 5 ns;

  dut : entity work.dut
    port map (clk => clk, rst => rst, ins => ins, ins_valid => ins_valid,
              ins_ready => ins_ready, outs => outs, outs_valid => outs_valid,
              outs_ready => outs_ready);

  process
    file f : text open read_mode is "first-vectors.txt";
    variable l : line;
    variable c : character;
    variable v, d : integer;
    variable cycle : integer := 0;
    variable e : integer_vector(0 to 11);
  begin
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    rst <= '0';
    wait for 1 ns;
    while not endfile(f) loop
      readline(f, l);
      if l'length > 0 and l(l'left) /= '#' then
        for i in 0 to 11 loop
          read(l, e(i));
        end loop;
        for k in 0 to 2 loop
          ins_valid(k) <= '1' when e(k) = 1 else '0';
          ins(k) <= std_logic_vector(to_unsigned(e(3 + k), 2));
        end loop;
        outs_ready <= '1' when e(6) = 1 else '0';
        wait for 1 ns;
        assert (outs_valid = '1') = (e(7) = 1)
          report "cycle " & integer'image(cycle) & ": outs_valid " & std_logic'image(outs_valid)
          severity failure;
        if e(7) = 1 then
          assert to_integer(unsigned(outs)) = e(8)
            report "cycle " & integer'image(cycle) & ": outs " &
                   integer'image(to_integer(unsigned(outs))) & ", expected " & integer'image(e(8))
            severity failure;
        end if;
        for k in 0 to 2 loop
          assert (ins_ready(k) = '1') = (e(9 + k) = 1)
            report "cycle " & integer'image(cycle) & ": ins_ready(" & integer'image(k) & ") " &
                   std_logic'image(ins_ready(k))
            severity failure;
        end loop;
        wait until rising_edge(clk);
        wait for 1 ns;
        cycle := cycle + 1;
      end if;
    end loop;
    report "first: " & integer'image(cycle) & " cycles as expected";
    std.env.finish;
  end process;
end architecture;
