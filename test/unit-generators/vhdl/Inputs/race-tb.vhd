-- A testbench for handshake.race, used by race-ghdl.mlir: the unit under test
-- is named dut, generated with CANDIDATES "t0/p1:f0:u1:a0/p2:f2:a0/p4:f3,1:a0,2"
-- (P(t, F(g1(a, not b), P(g2(c), g3(d, b)))), one 4-bit token and four
-- flags), driven by the rounds of race-vectors.txt one a cycle -- the inputs
-- set, the combinational outputs checked against the requirement's, the clock
-- ticks. Random rounds, each input's token held until taken, the sink
-- stalling at random: a candidate wins once its flags arrived as it needs
-- them and every candidate before it refused, the lowest-index winner of a
-- cycle wins, zero once every candidate is refused, an answer is held while
-- stalled, an input that gave its token is ready again in the cycle the
-- round completes and gives the next round's then, which is answered then
-- when it decides and the output is free. Fails (severity failure) on the
-- first thing wrong.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use work.types.all;

entity tb is
end entity;

architecture sim of tb is
  signal clk, rst : std_logic := '1';
  signal tokens : data_array(0 downto 0)(3 downto 0) := (others => (others => '0'));
  signal tokens_valid, tokens_ready : std_logic_vector(0 downto 0) := (others => '0');
  signal flags : data_array(3 downto 0)(0 downto 0) := (others => (others => '0'));
  signal flags_valid, flags_ready : std_logic_vector(3 downto 0) := (others => '0');
  signal outs : std_logic_vector(3 downto 0);
  signal outs_valid, outs_ready : std_logic := '0';
begin
  clk <= not clk after 5 ns;

  dut : entity work.dut
    port map (clk => clk, rst => rst,
              tokens => tokens, tokens_valid => tokens_valid, tokens_ready => tokens_ready,
              flags => flags, flags_valid => flags_valid, flags_ready => flags_ready,
              outs => outs, outs_valid => outs_valid, outs_ready => outs_ready);

  process
    file f : text open read_mode is "race-vectors.txt";
    variable l : line;
    variable cycle : integer := 0;
    variable e : integer_vector(0 to 17);
    variable rdy : std_logic;
  begin
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    rst <= '0';
    wait for 1 ns;
    while not endfile(f) loop
      readline(f, l);
      if l'length > 0 and l(l'left) /= '#' then
        for i in 0 to 17 loop
          read(l, e(i));
        end loop;
        -- input 0 the token, 1 to 4 the flags
        tokens_valid(0) <= '1' when e(0) = 1 else '0';
        tokens(0) <= std_logic_vector(to_unsigned(e(5), 4));
        for k in 0 to 3 loop
          flags_valid(k) <= '1' when e(1 + k) = 1 else '0';
          flags(k)(0) <= '1' when e(6 + k) = 1 else '0';
        end loop;
        outs_ready <= '1' when e(10) = 1 else '0';
        wait for 1 ns;
        assert (outs_valid = '1') = (e(11) = 1)
          report "cycle " & integer'image(cycle) & ": outs_valid " & std_logic'image(outs_valid)
          severity failure;
        if e(11) = 1 then
          assert to_integer(unsigned(outs)) = e(12)
            report "cycle " & integer'image(cycle) & ": outs " &
                   integer'image(to_integer(unsigned(outs))) & ", expected " & integer'image(e(12))
            severity failure;
        end if;
        assert (tokens_ready(0) = '1') = (e(13) = 1)
          report "cycle " & integer'image(cycle) & ": tokens_ready(0) " & std_logic'image(tokens_ready(0))
          severity failure;
        for k in 0 to 3 loop
          rdy := flags_ready(k);
          assert (rdy = '1') = (e(14 + k) = 1)
            report "cycle " & integer'image(cycle) & ": flags_ready(" & integer'image(k) & ") " &
                   std_logic'image(rdy)
            severity failure;
        end loop;
        wait until rising_edge(clk);
        wait for 1 ns;
        cycle := cycle + 1;
      end if;
    end loop;
    report "race: " & integer'image(cycle) & " cycles as expected";
    std.env.finish;
  end process;
end architecture;
