-- The eager fork of the VHDL library (data/vhdl/handshake/dataless/fork.vhd,
-- entity fork_dataless) in lockstep with the fork the unit generator writes
-- (entity fork_ref, of SIZE outputs), used by fork-phase-ghdl.mlir. The
-- generator's fork has one register per output; from three outputs on, the
-- library's stores the same state against a phase. Both get the same
-- ins_valid, outs_ready and rst, drawn at random with no regard for the
-- protocol (a valid may be withdrawn, a reset may fall anywhere), and must
-- agree on ins_ready and outs_valid in every cycle.
--
-- The stimulus has to reach the cases the two forms store differently: a
-- token some outputs take before the others (a torn cycle), a token that
-- completes after one, a valid withdrawn from a torn token, and a reset that
-- falls on one. Fails (severity failure) on a disagreement, or when one of
-- these cases was never reached.
library ieee;
use ieee.std_logic_1164.all;
use ieee.math_real.all;

entity tb is
  generic (SIZE : integer := 4; CYCLES : integer := 20000);
end entity;

architecture sim of tb is
  signal clk, rst : std_logic := '1';
  signal iv : std_logic := '0';
  signal ordy : std_logic_vector(SIZE - 1 downto 0) := (others => '0');
  signal lib_ir, ref_ir : std_logic;
  signal lib_ov, ref_ov : std_logic_vector(SIZE - 1 downto 0);
begin
  clk <= not clk after 5 ns;

  lib : entity work.fork_dataless generic map (SIZE => SIZE)
    port map (clk => clk, rst => rst, ins_valid => iv, ins_ready => lib_ir,
              outs_valid => lib_ov, outs_ready => ordy);

  ref : entity work.fork_ref
    port map (clk => clk, rst => rst, ins_valid => iv, ins_ready => ref_ir,
              outs_valid => ref_ov, outs_ready => ordy);

  process
    variable s1 : positive := 2026 + SIZE;
    variable s2 : positive := 7919;
    variable x, pv, pr : real;
    -- some outputs have taken the token on `ins`, the others have not
    variable torn : boolean := false;
    variable taken : boolean;
    variable disagreements, tokens, torn_cycles : natural := 0;
    variable after_torn, withdrawn, resets : natural := 0;
  begin
    -- two cycles of reset
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    for c in 1 to CYCLES loop
      wait for 1 ns;
      -- how often the input is valid and an output ready changes every 512
      -- cycles: a wide fork completes a token only under a valid that lasts
      case (c / 512) mod 4 is
        when 0      => pv := 0.90; pr := 0.50;
        when 1      => pv := 0.50; pr := 0.90;
        when 2      => pv := 0.97; pr := 0.15;
        when others => pv := 0.75; pr := 0.50;
      end case;
      uniform(s1, s2, x);
      if x < pv then iv <= '1'; else iv <= '0'; end if;
      for i in ordy'range loop
        uniform(s1, s2, x);
        if x < pr then ordy(i) <= '1'; else ordy(i) <= '0'; end if;
      end loop;
      uniform(s1, s2, x);
      if x < 0.004 then rst <= '1'; else rst <= '0'; end if;
      wait for 1 ns;

      if lib_ir /= ref_ir or lib_ov /= ref_ov then
        if disagreements = 0 then
          report "first disagreement in cycle " & integer'image(c);
        end if;
        disagreements := disagreements + 1;
      end if;

      -- what this cycle is, read on the generator's fork
      taken := false;
      for i in ordy'range loop
        if ref_ov(i) = '1' and ordy(i) = '1' then taken := true; end if;
      end loop;
      if rst = '1' then
        if torn then resets := resets + 1; end if;
        torn := false;
      elsif iv = '0' then
        if torn then withdrawn := withdrawn + 1; end if;
        torn := false;
      elsif ref_ir = '1' then
        tokens := tokens + 1;
        if torn then after_torn := after_torn + 1; end if;
        torn := false;
      elsif taken then
        torn_cycles := torn_cycles + 1;
        torn := true;
      end if;
      wait until rising_edge(clk);
    end loop;

    assert tokens > 0 report "no token completed" severity failure;
    if SIZE > 1 then
      assert torn_cycles > 0 report "no torn cycle" severity failure;
      assert after_torn > 0
        report "no token completed after a torn cycle" severity failure;
      assert withdrawn > 0
        report "no valid withdrawn from a torn token" severity failure;
      assert resets > 0 report "no reset on a torn token" severity failure;
    end if;
    assert disagreements = 0
      report "SIZE=" & integer'image(SIZE) & ": "
             & integer'image(disagreements) & " cycles disagree"
      severity failure;
    report "SIZE=" & integer'image(SIZE) & ": " & integer'image(CYCLES)
           & " cycles agree, " & integer'image(tokens) & " tokens, "
           & integer'image(after_torn) & " after a torn cycle, "
           & integer'image(withdrawn) & " withdrawn, "
           & integer'image(resets) & " reset";
    std.env.stop;
    wait;
  end process;
end architecture;
