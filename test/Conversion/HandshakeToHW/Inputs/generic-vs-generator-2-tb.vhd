-- The generic merges, join, blocker and queue of data/vhdl/handshake/generic
-- in lockstep with the units their generators write at the same parameters
-- (entities gen_merge, gen_merge_bare, gen_merge_ctl, gen_merge_ctl_bare,
-- gen_join, gen_blocker and gen_queue), used by
-- generic-vs-generator-2-ghdl.mlir: the same random valid, ready and data at
-- every cycle, a reset now and then, every output compared before and after
-- each clock edge. The generic entity is the generator's logic, and this is
-- what keeps the two from drifting apart.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.types.all;

entity tb is
  generic (
    SIZE   : positive := 3;      -- inputs of the merges, join and blocker
    W      : positive := 8;      -- data width
    SLOTS  : positive := 2;      -- the queue's slots
    CW     : positive := 2;      -- the width of the queue's counts
    TOKENS : string   := "none"; -- the tokens the queue holds at reset
    CYCLES : positive := 3000
  );
end entity;

architecture sim of tb is
  subtype word is std_logic_vector(W - 1 downto 0);
  subtype bits is std_logic_vector(SIZE - 1 downto 0);
  subtype count is std_logic_vector(CW - 1 downto 0);
  signal clk : std_logic := '0';
  signal rst : std_logic := '1';
  -- stimulus, shared by the units
  signal ins                : data_array(SIZE - 1 downto 0)(W - 1 downto 0) := (others => (others => '0'));
  signal ins_valid          : bits      := (others => '0');
  signal outs_ready         : std_logic := '0';
  signal q_in               : word      := (others => '0');
  signal q_valid, q_ready   : std_logic := '0';
  -- merge, with and without its slot, with and without data
  signal gm_o, hm_o, gb_o, hb_o                     : word;
  signal gm_r, hm_r, gb_r, hb_r, gc_r, hc_r, gd_r, hd_r : bits;
  signal gm_v, hm_v, gb_v, hb_v, gc_v, hc_v, gd_v, hd_v : std_logic;
  -- join, blocker
  signal gj_r, hj_r, gk_r, hk_r : bits;
  signal gj_v, hj_v, gk_v, hk_v : std_logic;
  signal gk_o, hk_o             : word;
  -- queue
  signal gq_o, hq_o                 : word;
  signal gq_r, hq_r, gq_v, hq_v     : std_logic;
  signal gq_sp, hq_sp, gq_sz, hq_sz : count;
begin
  g_merge : entity work.gen_merge
    port map(clk => clk, rst => rst, ins => ins, ins_valid => ins_valid, ins_ready => gm_r,
             outs => gm_o, outs_valid => gm_v, outs_ready => outs_ready);
  h_merge : entity work.handshake_merge(arch) generic map(SIZE, W)
    port map(clk => clk, rst => rst, ins => ins, ins_valid => ins_valid, ins_ready => hm_r,
             outs => hm_o, outs_valid => hm_v, outs_ready => outs_ready);
  g_bare : entity work.gen_merge_bare
    port map(clk => clk, rst => rst, ins => ins, ins_valid => ins_valid, ins_ready => gb_r,
             outs => gb_o, outs_valid => gb_v, outs_ready => outs_ready);
  h_bare : entity work.handshake_merge_notehb(arch) generic map(SIZE, W)
    port map(clk => clk, rst => rst, ins => ins, ins_valid => ins_valid, ins_ready => hb_r,
             outs => hb_o, outs_valid => hb_v, outs_ready => outs_ready);
  g_ctl : entity work.gen_merge_ctl
    port map(clk => clk, rst => rst, ins_valid => ins_valid, ins_ready => gc_r,
             outs_valid => gc_v, outs_ready => outs_ready);
  h_ctl : entity work.handshake_merge_dataless(arch) generic map(SIZE)
    port map(clk => clk, rst => rst, ins_valid => ins_valid, ins_ready => hc_r,
             outs_valid => hc_v, outs_ready => outs_ready);
  g_ctl_bare : entity work.gen_merge_ctl_bare
    port map(clk => clk, rst => rst, ins_valid => ins_valid, ins_ready => gd_r,
             outs_valid => gd_v, outs_ready => outs_ready);
  h_ctl_bare : entity work.handshake_merge_notehb_dataless(arch) generic map(SIZE)
    port map(clk => clk, rst => rst, ins_valid => ins_valid, ins_ready => hd_r,
             outs_valid => hd_v, outs_ready => outs_ready);

  g_join : entity work.gen_join
    port map(clk => clk, rst => rst, ins_valid => ins_valid, ins_ready => gj_r,
             outs_valid => gj_v, outs_ready => outs_ready);
  h_join : entity work.handshake_join(arch) generic map(SIZE)
    port map(clk => clk, rst => rst, ins_valid => ins_valid, ins_ready => hj_r,
             outs_valid => hj_v, outs_ready => outs_ready);
  g_blocker : entity work.gen_blocker
    port map(clk => clk, rst => rst, ins => ins, ins_valid => ins_valid, ins_ready => gk_r,
             outs => gk_o, outs_valid => gk_v, outs_ready => outs_ready);
  h_blocker : entity work.handshake_blocker(arch) generic map(SIZE, W)
    port map(clk => clk, rst => rst, ins => ins, ins_valid => ins_valid, ins_ready => hk_r,
             outs => hk_o, outs_valid => hk_v, outs_ready => outs_ready);

  g_queue : entity work.gen_queue
    port map(clk => clk, rst => rst, ins => q_in, ins_valid => q_valid, ins_ready => gq_r,
             ins_space => gq_sp, outs => gq_o, outs_valid => gq_v, outs_ready => q_ready,
             outs_size => gq_sz);
  h_queue : entity work.handshake_queue(arch) generic map(SLOTS, W, CW, CW, TOKENS)
    port map(clk => clk, rst => rst, ins => q_in, ins_valid => q_valid, ins_ready => hq_r,
             ins_space => hq_sp, outs => hq_o, outs_valid => hq_v, outs_ready => q_ready,
             outs_size => hq_sz);

  process
    variable lfsr : unsigned(62 downto 0) := to_unsigned(12345, 63);
    variable compared, read, full, taken : natural := 0;
    variable dense : boolean;

    procedure step is
    begin
      for i in 1 to 63 loop
        lfsr := lfsr(61 downto 0) & (lfsr(62) xor lfsr(61));
      end loop;
    end procedure;

    -- A W-bit word of fresh bits (W may be above 63).
    impure function fresh return word is
      variable r : word;
    begin
      for i in 0 to W - 1 loop
        if i mod 60 = 0 then
          step;
        end if;
        r(i) := lfsr(i mod 60);
      end loop;
      return r;
    end function;

    procedure compare is
    begin
      assert gm_o = hm_o and gm_r = hm_r and gm_v = hm_v
        report "the merge differs from its generator's at step " & integer'image(compared)
        severity failure;
      assert gb_o = hb_o and gb_r = hb_r and gb_v = hb_v
        report "the merge without a slot differs from its generator's at step " & integer'image(compared)
        severity failure;
      assert gc_r = hc_r and gc_v = hc_v
        report "the merge without data differs from its generator's at step " & integer'image(compared)
        severity failure;
      assert gd_r = hd_r and gd_v = hd_v
        report "the merge without data or a slot differs from its generator's at step " & integer'image(compared)
        severity failure;
      assert gj_r = hj_r and gj_v = hj_v
        report "the join differs from its generator's at step " & integer'image(compared)
        severity failure;
      assert gk_o = hk_o and gk_r = hk_r and gk_v = hk_v
        report "the blocker differs from its generator's at step " & integer'image(compared)
        severity failure;
      assert gq_r = hq_r and gq_v = hq_v and gq_sp = hq_sp and gq_sz = hq_sz
        report "the queue differs from its generator's at step " & integer'image(compared)
        severity failure;
      -- a queue's output is its memory, written only by what it has taken
      assert gq_v = '0' or gq_o = hq_o
        report "the queue's data differs from its generator's at step " & integer'image(compared)
        severity failure;
      compared := compared + 1;
    end procedure;
  begin
    for c in 0 to CYCLES loop
      -- Dense valids for a stretch, sparse for the next: a join fires on the
      -- first, a merge's arbiter sees one input alone on the second.
      dense := (c / 64) mod 2 = 0;
      for i in 0 to SIZE - 1 loop
        ins(i) <= fresh;
        step;
        if dense then
          ins_valid(i) <= lfsr(0) or lfsr(1) or lfsr(2);
        else
          ins_valid(i) <= lfsr(0) and lfsr(1);
        end if;
      end loop;
      step;
      outs_ready <= lfsr(0);
      q_in       <= fresh;
      step;
      -- the queue fills on a stretch of rare reads and drains on the next
      q_valid <= lfsr(0) or lfsr(1);
      if (c / 96) mod 2 = 0 then
        q_ready <= lfsr(2) and lfsr(3);
      else
        q_ready <= lfsr(2) or lfsr(3);
      end if;
      -- a reset at the start and now and then
      if c < 2 or c mod 509 = 508 then
        rst <= '1';
      else
        rst <= '0';
      end if;
      wait for 4 ns;
      if c >= 2 then
        compare;
        if rst = '0' and gq_v = '1' and q_ready = '1' then
          read := read + 1;
        end if;
        if rst = '0' and gq_r = '0' then
          full := full + 1;
        end if;
        if rst = '0' and gj_v = '1' and outs_ready = '1' then
          taken := taken + 1;
        end if;
      end if;
      clk <= '1';
      wait for 1 ns;
      if c >= 2 then
        compare;
      end if;
      wait for 4 ns;
      clk <= '0';
      wait for 1 ns;
    end loop;
    -- the run was not idle: the queue was read and was full, the join fired
    -- (a join of many inputs fires too rarely under this stimulus to ask it)
    assert read > CYCLES / 8 and full > 0 and (taken > 0 or SIZE > 16)
      report "the stimulus was idle: " & integer'image(read) & " reads, " & integer'image(full)
             & " cycles full, " & integer'image(taken) & " joins"
      severity failure;
    report "equal to the generator's over " & integer'image(compared) & " comparisons";
    wait;
  end process;
end architecture;
