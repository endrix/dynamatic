-- A testbench for kill-domain-at-valid-ghdl.mlir: the exported @kdv, which is
-- kill-domain-ghdl.mlir's design with `kill_at_valid` on each of its three
-- commits -- the latch (a ONE_SLOT_BREAK_R in kill domain 0) feeding a
-- stand-in, a neighbour slot outside the domains, a commit on `d` (domain 0),
-- on `e` two commits in series (domain 1's then domain 0's, their kills ORed
-- into domain 0's), and latch1 in domain 1 feeding the stand-in flag1. One
-- step a cycle: the inputs set, the combinational outputs checked, the clock
-- ticks. The expected values are a model's of the units (their
-- specifications, not their RTL).
--
-- The rounds, with the decisions' readers STALLED, which is where the earlier
-- kill differs from the transfer's: `d` offered and not taken kills domain 0
-- in that first cycle, so flag offers its owed zero the cycle after while the
-- decision still waits; no further kill comes while it waits, nor in the
-- cycle it transfers; the token offered right after that transfer is killed
-- again in its first cycle. Then `e`, whose two commits in series see one
-- valid and one ready: both one-shots pulse in the same cycle, so flag and
-- flag1 owe their zeros in the same cycle, and neither is killed again at the
-- transfer. The neighbour slot, full, is never reset. An observer models the
-- two one-shots that domain 0's kill_or reads and asserts that they never
-- pulse in one cycle (the domain's promise); each stand-in asserts that no
-- two of its kills are high in one cycle, and that no kill comes while a
-- token waits at its output. Fails (severity failure) on the first thing
-- wrong.
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

  dut : entity work.kdv
    port map (clk => clk, rst => rst, a => a, a_valid => av, a_ready => ar,
              b => b, b_valid => bv, b_ready => br, d => d, d_valid => dv,
              d_ready => dr, e => e, e_valid => ev, e_ready => er,
              c => c, c_valid => cv, c_ready => cr,
              flag => flag, flag_valid => fv, flag_ready => fr,
              other => other, other_valid => ov, other_ready => orr,
              dec => dec, dec_valid => decv, dec_ready => decr,
              dec2 => dec2, dec2_valid => dec2v, dec2_ready => dec2r,
              flag1 => flag1, flag1_valid => gv, flag1_ready => gr);

  -- A model of each commit's one-shot: with `kill_at_valid` the kill is high
  -- in the first cycle its token is offered, `ins_valid and not killed`,
  -- where `killed` is "offered and not taken last cycle". Domain 0 is stopped
  -- by d's commit and by e's second one, whose kills the lowering ORs: the OR
  -- is one kill, so the two must never pulse in one cycle. Both commits on e
  -- see e's valid and dec2's ready, so one `killed` models both.
  process (clk) is
    variable killed_d, killed_e : std_logic := '0';
  begin
    if rising_edge(clk) and rst = '0' then
      assert not (dv = '1' and killed_d = '0' and ev = '1' and killed_e = '0')
        report "two commits of kill domain 0 killed in one cycle"
        severity failure;
      killed_d := dv and not dr;
      killed_e := ev and not er;
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
    -- d offered and its reader stalled: the kill is in THIS cycle, with
    -- nothing passed, so a zero is owed; the neighbour takes a token and
    -- holds it (its reader stalled), outside the domains
    d_rdy := '0';
    step('0', 0, '1', 3, '1', '0', '0', 0, '1', '0', '1', '0', 0, '1', 3, '1', '0', 0, '1');
    -- the stall holds: no second kill for that token, and the zero it owes is
    -- offered now, taken in this cycle, while the decision still waits
    step('0', 0, '0', 0, '1', '0', '0', 0, '1', '0', '1', '1', 0, '1', 3, '1', '0', 0, '1');
    -- the reader ready: the decision transfers, and its token, killed when it
    -- was first offered, is not killed again -- so nothing is owed, and a
    -- token offered now passes through the latch and the stand-in
    d_rdy := '1';
    step('1', 2, '0', 0, '1', '0', '0', 0, '1', '0', '1', '1', 2, '1', 3, '1', '0', 0, '1');
    -- the next decision, offered in the cycle right after that transfer, is
    -- killed in this its first cycle; the latch's token passed in the round,
    -- so nothing is owed
    step('0', 0, '0', 0, '1', '0', '0', 0, '1', '0', '1', '0', 0, '1', 3, '1', '0', 0, '1');
    -- e offered and its reader stalled: both commits in series see one valid
    -- and one ready, so both one-shots pulse in this cycle; neither round
    -- passed anything, so flag and flag1 both owe a zero
    e_rdy := '0';
    step('0', 0, '0', 0, '0', '1', '0', 0, '1', '0', '1', '0', 0, '1', 3, '1', '0', 0, '1');
    -- the stall holds: no second kill, and the two zeros are offered in the
    -- same cycle and taken, while the decision still waits
    step('0', 0, '0', 0, '0', '1', '0', 0, '1', '0', '1', '1', 0, '1', 3, '1', '1', 0, '1');
    -- the reader ready: the two commits transfer together and neither kills
    -- again; nothing is owed
    e_rdy := '1';
    step('0', 0, '0', 0, '0', '1', '0', 0, '1', '0', '1', '0', 0, '1', 3, '1', '0', 0, '1');
    -- e offered again right after its transfer: both pulse again, and both
    -- rounds, empty, owe a zero
    step('0', 0, '0', 0, '0', '1', '0', 0, '1', '0', '1', '0', 0, '1', 3, '1', '0', 0, '1');
    -- the two zeros, taken; the neighbour, full since the first cycle and in
    -- no domain, has kept its token through five kills and is taken now
    step('0', 0, '0', 0, '0', '0', '0', 0, '1', '1', '1', '1', 0, '1', 3, '1', '1', 0, '1');
    -- paid: nothing more is owed anywhere
    step('0', 0, '0', 0, '0', '0', '0', 0, '1', '1', '1', '0', 0, '0', 0, '1', '0', 0, '1');
    report "at-valid kill domain: " & integer'image(cycle) & " cycles as expected";
    std.env.finish;
  end process;
end architecture;
