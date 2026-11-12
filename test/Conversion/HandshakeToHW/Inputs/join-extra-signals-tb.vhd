-- The joins of join-extra-signals-export.mlir (a two-input join from a and
-- b to ab, a three-input one from c, d and e to cde, every control carrying
-- a spec bit), at every one of the 4096 combinations of their inputs' valid
-- and spec bits and their outputs' ready bits: an output is valid when all
-- its inputs are, an input is ready when the output is and every other input
-- is valid, and a valid output is speculative when any of its inputs is.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity join_extra_signals_tb is
end entity;

architecture sim of join_extra_signals_tb is
  signal clk, rst : std_logic := '0';
  signal av, bv, cv, dv, ev, abr, cder : std_logic := '0';
  signal asp, bsp, csp, dsp, esp : std_logic_vector(0 downto 0) := "0";
  signal ar, br, cr, dr, er, abv, cdev : std_logic;
  signal absp, cdesp : std_logic_vector(0 downto 0);
begin
  dut : entity work.specjoin
    port map(
      a_valid => av, a_spec => asp, b_valid => bv, b_spec => bsp,
      c_valid => cv, c_spec => csp, d_valid => dv, d_spec => dsp,
      e_valid => ev, e_spec => esp,
      clk => clk, rst => rst,
      ab_ready => abr, cde_ready => cder,
      a_ready => ar, b_ready => br, c_ready => cr, d_ready => dr, e_ready => er,
      ab_valid => abv, ab_spec => absp, cde_valid => cdev, cde_spec => cdesp);

  process
    variable v : unsigned(11 downto 0);
    -- Transfers on each output, speculative and not: an exhaustive run sees
    -- both, or it checked nothing of the spec bit.
    variable ab_spec, ab_plain, cde_spec, cde_plain : natural := 0;
  begin
    for n in 0 to 4095 loop
      v := to_unsigned(n, 12);
      av <= v(0); bv <= v(1); cv <= v(2); dv <= v(3); ev <= v(4);
      asp(0) <= v(5); bsp(0) <= v(6); csp(0) <= v(7); dsp(0) <= v(8); esp(0) <= v(9);
      abr <= v(10); cder <= v(11);
      wait for 1 ns;

      assert abv = (av and bv)
        report "ab valid wrong at " & integer'image(n) severity failure;
      assert ar = (bv and abr) and br = (av and abr)
        report "a or b ready wrong at " & integer'image(n) severity failure;
      assert cdev = (cv and dv and ev)
        report "cde valid wrong at " & integer'image(n) severity failure;
      assert cr = (dv and ev and cder) and dr = (cv and ev and cder)
        and er = (cv and dv and cder)
        report "c, d or e ready wrong at " & integer'image(n) severity failure;
      if abv = '1' then
        assert absp(0) = (asp(0) or bsp(0))
          report "ab spec wrong at " & integer'image(n) severity failure;
        if abr = '1' then
          if absp(0) = '1' then ab_spec := ab_spec + 1; else ab_plain := ab_plain + 1; end if;
        end if;
      end if;
      if cdev = '1' then
        assert cdesp(0) = (csp(0) or dsp(0) or esp(0))
          report "cde spec wrong at " & integer'image(n) severity failure;
        if cder = '1' then
          if cdesp(0) = '1' then cde_spec := cde_spec + 1; else cde_plain := cde_plain + 1; end if;
        end if;
      end if;
    end loop;
    report "ab: " & integer'image(ab_spec) & " speculative, " & integer'image(ab_plain)
      & " not; cde: " & integer'image(cde_spec) & " speculative, "
      & integer'image(cde_plain) & " not";
    wait;
  end process;
end architecture;
