-- A testbench for kill-domain-ghdl.mlir: the exported @kd, whose latch (a
-- ONE_SLOT_BREAK_R in kill domain 0) feeds a stand-in, beside a neighbour
-- slot outside the domain, a commit on `d` (domain 0), and on `e` two commits
-- in series, domain 1's then domain 0's; domain 1's slot, latch1, feeds a
-- stand-in of its own (flag1). Domain 0's stand-in takes both its commits'
-- kills. One step a cycle: the inputs set, the combinational outputs checked,
-- the clock ticks. Every commit comes when nothing waits at the stand-ins'
-- outputs it ends a round of: their precondition, which they assert. The
-- rounds, first with `e` idle: a commit with nothing passed owes a zero,
-- offered the next cycle and held until taken, and leaves the neighbour full;
-- the latch takes a token, which waits behind the zero; a commit in the cycle
-- the zero is taken resets the latch (its token never shows) and owes the
-- next round's zero, the neighbour still full; a token that passes in the
-- commit's own cycle owes nothing; a token that passed earlier in the round
-- owes nothing; a commit with nothing passed and the zero taken at once; a
-- token offered while the zero is owed waits behind it. Then `e`: its commit
-- ends a round of both domains (each stand-in owes what its own round did not
-- pass), `d`'s of domain 0 only; latch1, full behind flag1's owed zero, is not
-- reset by `d`'s commit and is by `e`'s in the cycle that zero is taken; a
-- token that passes in `e`'s commit's cycle owes nothing; and the latch, full
-- behind flag's owed zero, is reset by `e`'s commit (domain 0's second, through
-- the OR) in the cycle that zero is taken. Then the decisions' readers
-- stalled: while `dec2` is not ready for three cycles, neither of `e`'s two
-- commits in series transfers (no round of either domain ends, latch1 keeps
-- its token behind flag1's owed zero, `d` stalled with it for a cycle), and
-- in the cycle it is ready again both transfer, ending a round of each domain
-- and resetting latch1 full. Every step checks that each commit passes its
-- decision's valid and ready straight through. The expected values are a
-- model's of the units (their specifications, not their RTL), which
-- reproduces the 19 cycles written by hand before `e` was added. An observer
-- checks the domain's promise: `d`'s and `e`'s decisions never transfer in
-- one cycle; the stand-ins assert it too (no two kills in one cycle). Fails
-- (severity failure) on the first thing wrong.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb is
end entity;

architecture sim of tb is
  signal clk, rst : std_logic := '1';
  signal a, b, c, flag, other, flag1 : std_logic_vector(1 downto 0) := (others => '0');
  signal d, dec, e, dec2 : std_logic_vector(0 downto 0) := (others => '0');
  signal av, bv, cv, dv, ev, ar, br, cr, dr, er : std_logic := '0';
  signal fv, ov, gv, decv, dec2v, fr, orr, gr, decr, dec2r : std_logic := '0';
begin
  clk <= not clk after 5 ns;

  dut : entity work.kd
    port map (clk => clk, rst => rst, a => a, a_valid => av, a_ready => ar,
              b => b, b_valid => bv, b_ready => br, d => d, d_valid => dv,
              d_ready => dr, e => e, e_valid => ev, e_ready => er,
              c => c, c_valid => cv, c_ready => cr,
              flag => flag, flag_valid => fv, flag_ready => fr,
              other => other, other_valid => ov, other_ready => orr,
              dec => dec, dec_valid => decv, dec_ready => decr,
              dec2 => dec2, dec2_valid => dec2v, dec2_ready => dec2r,
              flag1 => flag1, flag1_valid => gv, flag1_ready => gr);

  -- The domain's promise: its two commits (the decisions on d and on e)
  -- never transfer in one cycle.
  process (clk) is
  begin
    if rising_edge(clk) and rst = '0' then
      assert not (dv = '1' and dr = '1' and ev = '1' and er = '1')
        report "two commits of kill domain 0 transferred in one cycle"
        severity failure;
    end if;
  end process;

  process
    variable cycle : integer := 0;
    -- the decisions' readers (dec_ready, dec2_ready), ready unless a step
    -- stalls them
    variable d_rdy, e_rdy : std_logic := '1';
    -- set the inputs (a, b, c offered with their values, the decisions on
    -- d and e offered, the three flag/other readies, the decisions' readies
    -- from d_rdy and e_rdy), check the outputs (values only when valid is
    -- expected; each decision's valid and ready passed through its commits),
    -- tick
    procedure step(a_v : std_logic; a_d : integer; b_v : std_logic; b_d : integer;
                   d_v : std_logic; e_v : std_logic; c_v : std_logic; c_d : integer;
                   f_r : std_logic; o_r : std_logic; g_r : std_logic;
                   e_fv : std_logic; e_f : integer; e_ov : std_logic; e_o : integer;
                   e_ar : std_logic; e_gv : std_logic; e_g : integer; e_cr : std_logic) is
    begin
      av <= a_v; a <= std_logic_vector(to_unsigned(a_d, 2));
      bv <= b_v; b <= std_logic_vector(to_unsigned(b_d, 2));
      cv <= c_v; c <= std_logic_vector(to_unsigned(c_d, 2));
      dv <= d_v; ev <= e_v; decr <= d_rdy; dec2r <= e_rdy;
      fr <= f_r; orr <= o_r; gr <= g_r;
      wait for 1 ns;
      assert decv = d_v and dr = d_rdy and dec2v = e_v and er = e_rdy
        report "cycle " & integer'image(cycle) & ": a decision's valid or ready not passed through its commits"
        severity failure;
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
      assert gv = e_gv
        report "cycle " & integer'image(cycle) & ": flag1_valid " & std_logic'image(gv)
        severity failure;
      if e_gv = '1' then
        assert to_integer(unsigned(flag1)) = e_g
          report "cycle " & integer'image(cycle) & ": flag1 " &
                 integer'image(to_integer(unsigned(flag1))) & ", expected " & integer'image(e_g)
          severity failure;
      end if;
      assert cr = e_cr
        report "cycle " & integer'image(cycle) & ": c_ready " & std_logic'image(cr)
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
    -- step(a_v, a, b_v, b, d_v, e_v, c_v, c, flag_ready, other_ready, flag1_ready,
    --      expected: flag_valid, flag, other_valid, other, a_ready, flag1_valid, flag1, c_ready)
    -- a commit with nothing passed: a zero owed; the neighbour takes a token, its reader stalled
    step('0', 0, '1', 3, '1', '0', '0', 0, '1', '0', '1', '0', 0, '1', 3, '1', '0', 0, '1');
    -- the zero, held; the latch takes a token, which waits behind it
    step('1', 2, '0', 0, '0', '0', '0', 0, '0', '0', '1', '1', 0, '1', 3, '1', '0', 0, '1');
    -- the zero taken and a commit in that cycle: the latch, full, is reset, the next round owes a zero, the neighbour is not reset
    step('0', 0, '0', 0, '1', '0', '0', 0, '1', '0', '1', '1', 0, '1', 3, '0', '0', 0, '1');
    -- that zero, held until taken; the latch is empty and ready, its token gone; the neighbour still full
    step('0', 0, '0', 0, '0', '0', '0', 0, '0', '0', '1', '1', 0, '1', 3, '1', '0', 0, '1');
    step('0', 0, '0', 0, '0', '0', '0', 0, '1', '1', '1', '1', 0, '1', 3, '1', '0', 0, '1');
    -- paid: nothing more, the neighbour taken
    step('0', 0, '0', 0, '0', '0', '0', 0, '1', '1', '1', '0', 0, '0', 0, '1', '0', 0, '1');
    -- a token that passes in the commit's own cycle owes nothing
    step('1', 1, '0', 0, '1', '0', '0', 0, '1', '1', '1', '1', 1, '0', 0, '1', '0', 0, '1');
    step('0', 0, '0', 0, '0', '0', '0', 0, '1', '1', '1', '0', 0, '0', 0, '1', '0', 0, '1');
    -- a token that passed earlier in the round owes nothing
    step('1', 3, '0', 0, '0', '0', '0', 0, '1', '1', '1', '1', 3, '0', 0, '1', '0', 0, '1');
    step('0', 0, '0', 0, '1', '0', '0', 0, '1', '1', '1', '0', 0, '0', 0, '1', '0', 0, '1');
    step('0', 0, '0', 0, '0', '0', '0', 0, '1', '1', '1', '0', 0, '0', 0, '1', '0', 0, '1');
    -- nothing passed: the zero, taken at once
    step('0', 0, '0', 0, '1', '0', '0', 0, '1', '1', '1', '0', 0, '0', 0, '1', '0', 0, '1');
    step('0', 0, '0', 0, '0', '0', '0', 0, '1', '1', '1', '1', 0, '0', 0, '1', '0', 0, '1');
    step('0', 0, '0', 0, '0', '0', '0', 0, '1', '1', '1', '0', 0, '0', 0, '1', '0', 0, '1');
    -- a token offered while the zero is owed waits behind it
    step('0', 0, '0', 0, '1', '0', '0', 0, '1', '1', '1', '0', 0, '0', 0, '1', '0', 0, '1');
    step('1', 2, '0', 0, '0', '0', '0', 0, '0', '1', '1', '1', 0, '0', 0, '1', '0', 0, '1');
    step('0', 0, '0', 0, '0', '0', '0', 0, '1', '1', '1', '1', 0, '0', 0, '0', '0', 0, '1');
    step('0', 0, '0', 0, '0', '0', '0', 0, '1', '1', '1', '1', 2, '0', 0, '0', '0', 0, '1');
    step('0', 0, '0', 0, '0', '0', '0', 0, '1', '1', '1', '0', 0, '0', 0, '1', '0', 0, '1');
    -- e's commit ends a round of both domains: flag's token passed this round, so it owes nothing; flag1 passed nothing and owes a zero
    step('0', 0, '0', 0, '0', '1', '0', 0, '1', '1', '1', '0', 0, '0', 0, '1', '0', 0, '1');
    -- flag1's zero, taken
    step('0', 0, '0', 0, '0', '0', '0', 0, '1', '1', '1', '0', 0, '0', 0, '1', '1', 0, '1');
    -- e's commit with nothing passed in either round: both owe a zero
    step('0', 0, '0', 0, '0', '1', '0', 0, '1', '1', '1', '0', 0, '0', 0, '1', '0', 0, '1');
    -- both zeros, taken
    step('0', 0, '0', 0, '0', '0', '0', 0, '1', '1', '1', '1', 0, '0', 0, '1', '1', 0, '1');
    -- d's commit ends a round of domain 0 only: flag owes a zero, flag1 nothing
    step('0', 0, '0', 0, '1', '0', '0', 0, '1', '1', '1', '0', 0, '0', 0, '1', '0', 0, '1');
    -- flag's zero, taken; flag1 offers nothing
    step('0', 0, '0', 0, '0', '0', '0', 0, '1', '1', '1', '1', 0, '0', 0, '1', '0', 0, '1');
    -- e's commit, nothing passed: both owe a zero
    step('0', 0, '0', 0, '0', '1', '0', 0, '1', '1', '1', '0', 0, '0', 0, '1', '0', 0, '1');
    -- flag's zero taken, flag1's held; latch1 takes a token, which waits behind it
    step('0', 0, '0', 0, '0', '0', '1', 3, '1', '1', '0', '1', 0, '0', 0, '1', '1', 0, '1');
    -- d's commit, flag's round empty: flag owes a zero; latch1 (domain 1) is not reset, flag1's zero still held
    step('0', 0, '0', 0, '1', '0', '0', 0, '1', '1', '0', '0', 0, '0', 0, '1', '1', 0, '0');
    -- both zeros taken and e's commit in that cycle: latch1, full, is reset (its token never shows), both owe the next round's zero
    step('0', 0, '0', 0, '0', '1', '0', 0, '1', '1', '1', '1', 0, '0', 0, '1', '1', 0, '0');
    -- the two zeros, taken; latch1 empty and ready
    step('0', 0, '0', 0, '0', '0', '0', 0, '1', '1', '1', '1', 0, '0', 0, '1', '1', 0, '1');
    step('0', 0, '0', 0, '0', '0', '0', 0, '1', '1', '1', '0', 0, '0', 0, '1', '0', 0, '1');
    -- a token that passes in e's commit's own cycle owes nothing on flag; flag1 passed nothing and owes
    step('1', 1, '0', 0, '0', '1', '0', 0, '1', '1', '1', '1', 1, '0', 0, '1', '0', 0, '1');
    -- flag1's zero, taken
    step('0', 0, '0', 0, '0', '0', '0', 0, '1', '1', '1', '0', 0, '0', 0, '1', '1', 0, '1');
    step('0', 0, '0', 0, '0', '0', '0', 0, '1', '1', '1', '0', 0, '0', 0, '1', '0', 0, '1');
    -- d's commit, flag's round empty: flag owes a zero
    step('0', 0, '0', 0, '1', '0', '0', 0, '1', '1', '1', '0', 0, '0', 0, '1', '0', 0, '1');
    -- the zero, held; the latch takes a token, which waits behind it
    step('1', 2, '0', 0, '0', '0', '0', 0, '0', '1', '1', '1', 0, '0', 0, '1', '0', 0, '1');
    -- the zero taken and e's commit in that cycle: the latch, full, is reset by domain 0's second commit (its token never shows); both owe a zero
    step('0', 0, '0', 0, '0', '1', '0', 0, '1', '1', '1', '1', 0, '0', 0, '0', '0', 0, '1');
    -- the two zeros, taken; the latch empty and ready
    step('0', 0, '0', 0, '0', '0', '0', 0, '1', '1', '1', '1', 0, '0', 0, '1', '1', 0, '1');
    step('0', 0, '0', 0, '0', '0', '0', 0, '1', '1', '1', '0', 0, '0', 0, '1', '0', 0, '1');
    -- e's commit, nothing passed in either round: both owe a zero
    step('0', 0, '0', 0, '0', '1', '0', 0, '1', '1', '1', '0', 0, '0', 0, '1', '0', 0, '1');
    -- e's decision offered again, its reader stalled (dec2 not ready): neither commit in series transfers; flag's zero taken, flag1's held; latch1 takes a token, which waits behind it
    e_rdy := '0';
    step('0', 0, '0', 0, '0', '1', '1', 3, '1', '1', '0', '1', 0, '0', 0, '1', '1', 0, '1');
    -- the stall holds: no round of either domain ends; flag owes nothing, latch1 keeps its token behind flag1's zero
    step('0', 0, '0', 0, '0', '1', '0', 0, '1', '1', '0', '0', 0, '0', 0, '1', '1', 0, '0');
    -- d's decision offered too, its reader stalled as well: no commit transfers
    d_rdy := '0';
    step('0', 0, '0', 0, '1', '1', '0', 0, '1', '1', '0', '0', 0, '0', 0, '1', '1', 0, '0');
    -- e's reader ready again: both commits in series transfer in this cycle, a round of each domain ends; flag1's zero taken, latch1, full, is reset (its token never shows); both owe the next round's zero
    d_rdy := '1';
    e_rdy := '1';
    step('0', 0, '0', 0, '0', '1', '0', 0, '1', '1', '1', '0', 0, '0', 0, '1', '1', 0, '0');
    -- the two zeros, taken; latch1 empty and ready
    step('0', 0, '0', 0, '0', '0', '0', 0, '1', '1', '1', '1', 0, '0', 0, '1', '1', 0, '1');
    step('0', 0, '0', 0, '0', '0', '0', 0, '1', '1', '1', '0', 0, '0', 0, '1', '0', 0, '1');
    report "kill domain: " & integer'image(cycle) & " cycles as expected";
    std.env.finish;
  end process;
end architecture;
