-- The function of state-loop-ghdl.mlir exported twice, in lockstep: with the
-- state registers' units (library state_units: handshake_init_state and
-- handshake_buffer_state in its four loops) and without (library
-- generic_units: handshake_init and oehb). Both get the same inputs, drawn at
-- random: a new `d` in every cycle it is not held valid, the readies of the
-- five outputs, and resets that fall anywhere. Every output must be the same
-- in every cycle; the four state values are outputs.
--
-- Fails (severity failure) on a difference, or when the run did not move the
-- states, transfer on every output and reset in mid-run.
library ieee;
use ieee.std_logic_1164.all;
use ieee.math_real.all;

library state_units;
library generic_units;

entity tb is
  generic (CYCLES : integer := 20000);
end entity;

architecture sim of tb is
  signal clk, rst : std_logic := '1';
  signal d : std_logic_vector(7 downto 0) := (others => '0');
  signal d_valid, go_valid : std_logic := '0';
  signal f_ready, a_ready, w_ready, x_ready, p_ready : std_logic := '0';

  -- every output of the function, side by side
  type outputs is record
    d_ready, go_ready : std_logic;
    f : std_logic_vector(0 downto 0);
    a : std_logic_vector(7 downto 0);
    w : std_logic_vector(32 downto 0);
    x : std_logic_vector(63 downto 0);
    p : std_logic_vector(7 downto 0);
    f_valid, a_valid, w_valid, x_valid, p_valid : std_logic;
  end record;
  signal s, g : outputs;
begin
  clk <= not clk after 5 ns;

  with_units : entity state_units.state
    port map (clk => clk, rst => rst, d => d, d_valid => d_valid, d_ready => s.d_ready,
              go_valid => go_valid, go_ready => s.go_ready,
              f => s.f, f_valid => s.f_valid, f_ready => f_ready,
              a => s.a, a_valid => s.a_valid, a_ready => a_ready,
              w => s.w, w_valid => s.w_valid, w_ready => w_ready,
              x => s.x, x_valid => s.x_valid, x_ready => x_ready,
              p => s.p, p_valid => s.p_valid, p_ready => p_ready);

  without_units : entity generic_units.state
    port map (clk => clk, rst => rst, d => d, d_valid => d_valid, d_ready => g.d_ready,
              go_valid => go_valid, go_ready => g.go_ready,
              f => g.f, f_valid => g.f_valid, f_ready => f_ready,
              a => g.a, a_valid => g.a_valid, a_ready => a_ready,
              w => g.w, w_valid => g.w_valid, w_ready => w_ready,
              x => g.x, x_valid => g.x_valid, x_ready => x_ready,
              p => g.p, p_valid => g.p_valid, p_ready => p_ready);

  process
    variable s1 : positive := 2026;
    variable s2 : positive := 7919;
    variable r : real;
    variable differs, resets, moves : natural := 0;
    variable f_taken, a_taken, w_taken, x_taken, p_taken : natural := 0;
    variable before : std_logic_vector(105 downto 0) := (others => '0');
    variable now : std_logic_vector(105 downto 0);

    impure function chance(p : real) return std_logic is
    begin
      uniform(s1, s2, r);
      if r < p then return '1'; end if;
      return '0';
    end function;
  begin
    -- two cycles of reset
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    for c in 1 to CYCLES loop
      wait for 1 ns;
      -- a valid is held until it is taken, and `d` under it; without one,
      -- `d` is another value in every cycle (the states read it bare)
      if d_valid = '0' or g.d_ready = '1' then
        d_valid <= chance(0.6);
        for i in d'range loop d(i) <= chance(0.5); end loop;
      end if;
      if go_valid = '0' or g.go_ready = '1' then
        go_valid <= chance(0.7);
      end if;
      f_ready <= chance(0.6);
      a_ready <= chance(0.6);
      w_ready <= chance(0.6);
      x_ready <= chance(0.6);
      p_ready <= chance(0.6);
      rst <= chance(0.003);
      wait for 1 ns;

      if s /= g then
        if differs = 0 then
          report "the two exports first differ in cycle " & integer'image(c);
        end if;
        differs := differs + 1;
      end if;

      now := g.f & g.a & g.w & g.x;
      if now /= before then moves := moves + 1; end if;
      before := now;
      if rst = '1' then
        resets := resets + 1;
      else
        if g.f_valid = '1' and f_ready = '1' then f_taken := f_taken + 1; end if;
        if g.a_valid = '1' and a_ready = '1' then a_taken := a_taken + 1; end if;
        if g.w_valid = '1' and w_ready = '1' then w_taken := w_taken + 1; end if;
        if g.x_valid = '1' and x_ready = '1' then x_taken := x_taken + 1; end if;
        if g.p_valid = '1' and p_ready = '1' then p_taken := p_taken + 1; end if;
      end if;
      wait until rising_edge(clk);
    end loop;

    assert moves > CYCLES / 2 report "the states did not move" severity failure;
    assert resets > 0 report "no reset in mid-run" severity failure;
    assert f_taken > 0 and a_taken > 0 and w_taken > 0 and x_taken > 0 and p_taken > 0
      report "an output never transferred" severity failure;
    assert differs = 0
      report "the two exports differ in " & integer'image(differs) & " cycles"
      severity failure;
    report integer'image(CYCLES) & " cycles agree, the states moved in "
           & integer'image(moves) & ", " & integer'image(a_taken)
           & " transfers of a state, " & integer'image(resets) & " resets";
    std.env.stop;
    wait;
  end process;
end architecture;
