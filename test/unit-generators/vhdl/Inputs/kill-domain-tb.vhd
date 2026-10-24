-- A testbench for kill-domain-ghdl.mlir: the exported @kd, whose latch (a
-- ONE_SLOT_BREAK_R in kill domain 0) feeds a stand-in, beside a neighbour
-- slot outside the domain, and a commit on `d`. One step a cycle: the inputs
-- set, the combinational outputs checked, the clock ticks. Every commit comes
-- when nothing waits at the stand-in's output: the stand-in's precondition,
-- which it asserts. The rounds: a commit with nothing passed owes a zero,
-- offered the next cycle and held until taken, and leaves the neighbour full;
-- the latch takes a token, which waits behind the zero; a commit in the cycle
-- the zero is taken resets the latch (its token never shows) and owes the
-- next round's zero, the neighbour still full; a token that passes in the
-- commit's own cycle owes nothing; a token that passed earlier in the round
-- owes nothing; a commit with nothing passed and the zero taken at once; a
-- token offered while the zero is owed waits behind it. Fails (severity
-- failure) on the first thing wrong.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb is
end entity;

architecture sim of tb is
  signal clk, rst : std_logic := '1';
  signal a, b, flag, other : std_logic_vector(1 downto 0) := (others => '0');
  signal d, dec : std_logic_vector(0 downto 0) := (others => '0');
  signal av, bv, dv, ar, br, dr : std_logic := '0';
  signal fv, ov, decv, fr, orr, decr : std_logic := '0';
begin
  clk <= not clk after 5 ns;

  dut : entity work.kd
    port map (clk => clk, rst => rst, a => a, a_valid => av, a_ready => ar,
              b => b, b_valid => bv, b_ready => br, d => d, d_valid => dv,
              d_ready => dr, flag => flag, flag_valid => fv, flag_ready => fr,
              other => other, other_valid => ov, other_ready => orr,
              dec => dec, dec_valid => decv, dec_ready => decr);

  process
    variable cycle : integer := 0;
    -- set the inputs (a, b offered with their values, the commit's token
    -- offered, the three readies), check the outputs (values only when
    -- valid is expected), tick
    procedure step(a_v : std_logic; a_d : integer; b_v : std_logic; b_d : integer;
                   d_v : std_logic; f_r : std_logic; o_r : std_logic;
                   e_fv : std_logic; e_f : integer; e_ov : std_logic; e_o : integer;
                   e_ar : std_logic) is
    begin
      av <= a_v; a <= std_logic_vector(to_unsigned(a_d, 2));
      bv <= b_v; b <= std_logic_vector(to_unsigned(b_d, 2));
      dv <= d_v; decr <= '1';
      fr <= f_r; orr <= o_r;
      wait for 1 ns;
      assert fv = e_fv
        report "cycle " & integer'image(cycle) & ": flag_valid " & std_logic'image(fv)
        severity failure;
      if e_fv = '1' then
        assert to_integer(unsigned(flag)) = e_f
          report "cycle " & integer'image(cycle) & ": flag " &
                 integer'image(to_integer(unsigned(flag))) & ", expected " & integer'image(e_f)
          severity failure;
      end if;
      assert ov = e_ov
        report "cycle " & integer'image(cycle) & ": other_valid " & std_logic'image(ov)
        severity failure;
      if e_ov = '1' then
        assert to_integer(unsigned(other)) = e_o
          report "cycle " & integer'image(cycle) & ": other " &
                 integer'image(to_integer(unsigned(other))) & ", expected " & integer'image(e_o)
          severity failure;
      end if;
      assert ar = e_ar
        report "cycle " & integer'image(cycle) & ": a_ready " & std_logic'image(ar)
        severity failure;
      wait until rising_edge(clk);
      wait for 1 ns;
      cycle := cycle + 1;
    end procedure;
  begin
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    rst <= '0';
    wait for 1 ns;
    -- a commit with nothing passed: a zero owed; the neighbour takes a
    -- token, its reader stalled
    step('0', 0, '1', 3, '1', '1', '0', '0', 0, '1', 3, '1');
    -- the zero, held; the latch takes a token, which waits behind it
    step('1', 2, '0', 0, '0', '0', '0', '1', 0, '1', 3, '1');
    -- the zero taken and a commit in that cycle: the latch, full, is reset,
    -- the next round owes a zero, the neighbour is not reset
    step('0', 0, '0', 0, '1', '1', '0', '1', 0, '1', 3, '0');
    -- that zero, held until taken; the latch is empty and ready, its token
    -- gone; the neighbour still full
    step('0', 0, '0', 0, '0', '0', '0', '1', 0, '1', 3, '1');
    step('0', 0, '0', 0, '0', '1', '1', '1', 0, '1', 3, '1');
    -- paid: nothing more, the neighbour taken
    step('0', 0, '0', 0, '0', '1', '1', '0', 0, '0', 0, '1');
    -- a token that passes in the commit's own cycle owes nothing
    step('1', 1, '0', 0, '1', '1', '1', '1', 1, '0', 0, '1');
    step('0', 0, '0', 0, '0', '1', '1', '0', 0, '0', 0, '1');
    -- a token that passed earlier in the round owes nothing
    step('1', 3, '0', 0, '0', '1', '1', '1', 3, '0', 0, '1');
    step('0', 0, '0', 0, '1', '1', '1', '0', 0, '0', 0, '1');
    step('0', 0, '0', 0, '0', '1', '1', '0', 0, '0', 0, '1');
    -- nothing passed: the zero, taken at once
    step('0', 0, '0', 0, '1', '1', '1', '0', 0, '0', 0, '1');
    step('0', 0, '0', 0, '0', '1', '1', '1', 0, '0', 0, '1');
    step('0', 0, '0', 0, '0', '1', '1', '0', 0, '0', 0, '1');
    -- a token offered while the zero is owed waits behind it
    step('0', 0, '0', 0, '1', '1', '1', '0', 0, '0', 0, '1');
    step('1', 2, '0', 0, '0', '0', '1', '1', 0, '0', 0, '1');
    step('0', 0, '0', 0, '0', '1', '1', '1', 0, '0', 0, '0');
    step('0', 0, '0', 0, '0', '1', '1', '1', 2, '0', 0, '0');
    step('0', 0, '0', 0, '0', '1', '1', '0', 0, '0', 0, '1');
    report "kill domain: " & integer'image(cycle) & " cycles as expected";
    std.env.finish;
  end process;
end architecture;
