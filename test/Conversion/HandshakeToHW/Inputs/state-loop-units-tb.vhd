-- One state register's loop, bundle -> init -> slot -> unbundle with the
-- unbundle's control back on the bundle, built from the units themselves:
-- with handshake_init and oehb (STATE = 0), or with handshake_init_state and
-- handshake_buffer_state (STATE = 1). Every wire between the four units is
-- brought out. Used by state-loop-units-ghdl.mlir.
library ieee;
use ieee.std_logic_1164.all;

entity state_loop is
  generic (W : integer; INIT : string; STATE : integer);
  port (
    clk, rst : in  std_logic;
    nxt      : in  std_logic_vector(W - 1 downto 0);
    -- the value read, the init's output, and the valids and readies
    q        : out std_logic_vector(W - 1 downto 0);
    mid      : out std_logic_vector(W - 1 downto 0);
    hs       : out std_logic_vector(7 downto 0)
  );
end entity;

architecture arch of state_loop is
  signal b_outs, i_outs, r_outs : std_logic_vector(W - 1 downto 0);
  signal b_v, b_r, i_v, i_r, r_v, r_r, u_cv, u_cr : std_logic;
begin
  b : entity work.handshake_bundle generic map (W)
    port map (clk => clk, rst => rst, ctrl_valid => u_cv, ctrl_ready => u_cr, data => nxt,
              outs => b_outs, outs_valid => b_v, outs_ready => b_r);
  generic_units : if STATE = 0 generate
    i : entity work.handshake_init generic map (INIT, W)
      port map (clk => clk, rst => rst, ins => b_outs, ins_valid => b_v, ins_ready => b_r,
                outs => i_outs, outs_valid => i_v, outs_ready => i_r);
    r : entity work.oehb generic map (W)
      port map (clk => clk, rst => rst, ins => i_outs, ins_valid => i_v, ins_ready => i_r,
                outs => r_outs, outs_valid => r_v, outs_ready => r_r);
  end generate;
  state_units : if STATE = 1 generate
    i : entity work.handshake_init_state generic map (INIT, W)
      port map (clk => clk, rst => rst, ins => b_outs, ins_valid => b_v, ins_ready => b_r,
                outs => i_outs, outs_valid => i_v, outs_ready => i_r);
    r : entity work.handshake_buffer_state generic map (W)
      port map (clk => clk, rst => rst, ins => i_outs, ins_valid => i_v, ins_ready => i_r,
                outs => r_outs, outs_valid => r_v, outs_ready => r_r);
  end generate;
  u : entity work.handshake_unbundle generic map (W)
    port map (clk => clk, rst => rst, ins => r_outs, ins_valid => r_v, ins_ready => r_r,
              ctrl_valid => u_cv, ctrl_ready => u_cr, data => q);
  mid <= i_outs;
  hs  <= (b_v, b_r, i_v, i_r, r_v, r_r, u_cv, u_cr);
end architecture;

-- The two loops in lockstep: the same next value, another at every cycle,
-- and the same reset, in bursts of one to six cycles that fall anywhere.
-- The value read, the init's output and all eight valids and readies must be
-- the same in every cycle: the two units are held against the generic ones
-- at every port, the ports nothing outside a loop reads among them.
--
-- Fails (severity failure) on a difference, or when the run had no reset in
-- mid-run or did not move the state.
library ieee;
use ieee.std_logic_1164.all;
use ieee.math_real.all;

entity tb is
  generic (W : integer := 8; INIT : string := "5"; CYCLES : integer := 20000);
end entity;

architecture sim of tb is
  signal clk, rst : std_logic := '1';
  signal nxt : std_logic_vector(W - 1 downto 0) := (others => '0');
  signal gq, sq, gmid, smid : std_logic_vector(W - 1 downto 0);
  signal ghs, shs : std_logic_vector(7 downto 0);
begin
  clk <= not clk after 5 ns;

  generic_loop : entity work.state_loop generic map (W, INIT, 0)
    port map (clk, rst, nxt, gq, gmid, ghs);
  state_loop : entity work.state_loop generic map (W, INIT, 1)
    port map (clk, rst, nxt, sq, smid, shs);

  process
    variable s1 : positive := 2026 + W;
    variable s2 : positive := 7919;
    variable r : real;
    variable differs, bursts, moves : natural := 0;
    variable left : natural := 0;
    variable before : std_logic_vector(W - 1 downto 0) := (others => '0');
  begin
    -- two cycles of reset
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    for c in 1 to CYCLES loop
      wait for 1 ns;
      for i in nxt'range loop
        uniform(s1, s2, r);
        if r < 0.5 then nxt(i) <= '1'; else nxt(i) <= '0'; end if;
      end loop;
      if left > 0 then
        left := left - 1;
      else
        uniform(s1, s2, r);
        if r < 0.01 then
          uniform(s1, s2, r);
          left := 1 + integer(floor(r * 6.0));
          bursts := bursts + 1;
        end if;
      end if;
      if left > 0 then rst <= '1'; else rst <= '0'; end if;
      wait for 1 ns;

      if gq /= sq or gmid /= smid or ghs /= shs then
        if differs = 0 then
          report "the two loops first differ in cycle " & integer'image(c);
        end if;
        differs := differs + 1;
      end if;
      if gq /= before then moves := moves + 1; end if;
      before := gq;
      wait until rising_edge(clk);
    end loop;

    assert bursts > 0 report "no reset in mid-run" severity failure;
    assert moves > CYCLES / 8 report "the state did not move" severity failure;
    assert differs = 0
      report "the two loops differ in " & integer'image(differs) & " cycles"
      severity failure;
    report "W=" & integer'image(W) & " INIT=" & INIT & ": "
           & integer'image(CYCLES) & " cycles agree, "
           & integer'image(bursts) & " resets";
    std.env.stop;
    wait;
  end process;
end architecture;
