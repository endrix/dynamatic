-- The generic muxes, control merges, bundles and unbundles of
-- data/vhdl/handshake/generic in lockstep with the units their generators
-- write at the same parameters (entities gen_mux, gen_mux_bare, gen_mux_ctl,
-- gen_mux_ctl_bare, gen_cmerge, gen_cmerge_ctl, gen_bundle, gen_bundle_space,
-- gen_bundle_control, gen_unbundle, gen_unbundle_size and
-- gen_unbundle_control), used by generic-vs-generator-3-ghdl.mlir: the same
-- random valid, ready and data at every cycle, a reset now and then, every
-- output compared before and after each clock edge. The generic entity is
-- the generator's logic, and this is what keeps the two from drifting apart.
-- W and CW are two bits at least: a bare wire of one bit is a scalar in what
-- the generator writes (generic-units-5-export.mlir exports that case).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.types.all;

entity tb is
  generic (
    SIZE   : positive := 3;  -- inputs of the muxes and control merges
    W      : positive := 8;  -- data width
    IW     : positive := 2;  -- width of the mux's select and the control merge's index
    CW     : positive := 2;  -- width of a channel's `size` or `space`
    CYCLES : positive := 3000
  );
end entity;

architecture sim of tb is
  subtype word is std_logic_vector(W - 1 downto 0);
  subtype bits is std_logic_vector(SIZE - 1 downto 0);
  subtype idx is std_logic_vector(IW - 1 downto 0);
  subtype count is std_logic_vector(CW - 1 downto 0);
  signal clk : std_logic := '0';
  signal rst : std_logic := '1';
  -- stimulus, shared by the units
  signal ins                   : data_array(SIZE - 1 downto 0)(W - 1 downto 0) := (others => (others => '0'));
  signal ins_valid             : bits      := (others => '0');
  signal sel                   : idx       := (others => '0');
  signal sel_valid, outs_ready : std_logic := '0';
  signal index_ready           : std_logic := '0';
  signal d                     : word      := (others => '0');
  signal k                     : count     := (others => '0');
  signal v, r                  : std_logic := '0';
  -- mux, with and without its slot, with and without data
  signal gm_o, hm_o, gb_o, hb_o                         : word;
  signal gm_r, hm_r, gb_r, hb_r, gc_r, hc_r, gd_r, hd_r : bits;
  signal gm_v, hm_v, gb_v, hb_v, gc_v, hc_v, gd_v, hd_v : std_logic;
  signal gm_s, hm_s, gb_s, hb_s, gc_s, hc_s, gd_s, hd_s : std_logic;
  -- control merge, with and without data
  signal gx_o, hx_o                     : word;
  signal gx_i, hx_i, gy_i, hy_i         : idx;
  signal gx_r, hx_r, gy_r, hy_r         : bits;
  signal gx_v, hx_v, gy_v, hy_v         : std_logic;
  signal gx_iv, hx_iv, gy_iv, hy_iv     : std_logic;
  -- bundle and unbundle
  signal g1_o, h1_o, g2_o, h2_o, g3_d, h3_d, g4_d, h4_d : word;
  signal g2_k, h2_k, g4_k, h4_k                         : count;
  signal g1_v, h1_v, g1_r, h1_r, g2_v, h2_v, g2_r, h2_r : std_logic;
  signal g3_v, h3_v, g3_r, h3_r, g4_v, h4_v, g4_r, h4_r : std_logic;
  signal g5_v, h5_v, g5_r, h5_r, g6_v, h6_v, g6_r, h6_r : std_logic;
begin
  g_mux : entity work.gen_mux
    port map(clk => clk, rst => rst, ins => ins, ins_valid => ins_valid, ins_ready => gm_r,
             index => sel, index_valid => sel_valid, index_ready => gm_s,
             outs => gm_o, outs_valid => gm_v, outs_ready => outs_ready);
  h_mux : entity work.handshake_mux(arch) generic map(SIZE, W, IW, 1)
    port map(clk => clk, rst => rst, ins => ins, ins_valid => ins_valid, ins_ready => hm_r,
             index => sel, index_valid => sel_valid, index_ready => hm_s,
             outs => hm_o, outs_valid => hm_v, outs_ready => outs_ready);
  g_bare : entity work.gen_mux_bare
    port map(clk => clk, rst => rst, ins => ins, ins_valid => ins_valid, ins_ready => gb_r,
             index => sel, index_valid => sel_valid, index_ready => gb_s,
             outs => gb_o, outs_valid => gb_v, outs_ready => outs_ready);
  h_bare : entity work.handshake_mux(arch) generic map(SIZE, W, IW, 0)
    port map(clk => clk, rst => rst, ins => ins, ins_valid => ins_valid, ins_ready => hb_r,
             index => sel, index_valid => sel_valid, index_ready => hb_s,
             outs => hb_o, outs_valid => hb_v, outs_ready => outs_ready);
  g_ctl : entity work.gen_mux_ctl
    port map(clk => clk, rst => rst, ins_valid => ins_valid, ins_ready => gc_r,
             index => sel, index_valid => sel_valid, index_ready => gc_s,
             outs_valid => gc_v, outs_ready => outs_ready);
  h_ctl : entity work.handshake_mux_dataless(arch) generic map(SIZE, IW, 1)
    port map(clk => clk, rst => rst, ins_valid => ins_valid, ins_ready => hc_r,
             index => sel, index_valid => sel_valid, index_ready => hc_s,
             outs_valid => hc_v, outs_ready => outs_ready);
  g_ctl_bare : entity work.gen_mux_ctl_bare
    port map(clk => clk, rst => rst, ins_valid => ins_valid, ins_ready => gd_r,
             index => sel, index_valid => sel_valid, index_ready => gd_s,
             outs_valid => gd_v, outs_ready => outs_ready);
  h_ctl_bare : entity work.handshake_mux_dataless(arch) generic map(SIZE, IW, 0)
    port map(clk => clk, rst => rst, ins_valid => ins_valid, ins_ready => hd_r,
             index => sel, index_valid => sel_valid, index_ready => hd_s,
             outs_valid => hd_v, outs_ready => outs_ready);

  g_cmerge : entity work.gen_cmerge
    port map(clk => clk, rst => rst, ins => ins, ins_valid => ins_valid, ins_ready => gx_r,
             outs => gx_o, outs_valid => gx_v, outs_ready => outs_ready,
             index => gx_i, index_valid => gx_iv, index_ready => index_ready);
  h_cmerge : entity work.handshake_control_merge(arch) generic map(SIZE, W, IW)
    port map(clk => clk, rst => rst, ins => ins, ins_valid => ins_valid, ins_ready => hx_r,
             outs => hx_o, outs_valid => hx_v, outs_ready => outs_ready,
             index => hx_i, index_valid => hx_iv, index_ready => index_ready);
  g_cmerge_ctl : entity work.gen_cmerge_ctl
    port map(clk => clk, rst => rst, ins_valid => ins_valid, ins_ready => gy_r,
             outs_valid => gy_v, outs_ready => outs_ready,
             index => gy_i, index_valid => gy_iv, index_ready => index_ready);
  h_cmerge_ctl : entity work.handshake_control_merge_dataless(arch) generic map(SIZE, IW)
    port map(clk => clk, rst => rst, ins_valid => ins_valid, ins_ready => hy_r,
             outs_valid => hy_v, outs_ready => outs_ready,
             index => hy_i, index_valid => hy_iv, index_ready => index_ready);

  g_bundle : entity work.gen_bundle
    port map(clk => clk, rst => rst, ctrl_valid => v, ctrl_ready => g1_r, data => d,
             outs => g1_o, outs_valid => g1_v, outs_ready => r);
  h_bundle : entity work.handshake_bundle(arch) generic map(W)
    port map(clk => clk, rst => rst, ctrl_valid => v, ctrl_ready => h1_r, data => d,
             outs => h1_o, outs_valid => h1_v, outs_ready => r);
  g_bundle_space : entity work.gen_bundle_space
    port map(clk => clk, rst => rst, ctrl_valid => v, ctrl_ready => g2_r, data => d, space => g2_k,
             outs => g2_o, outs_valid => g2_v, outs_ready => r, outs_space => k);
  h_bundle_space : entity work.handshake_bundle_space(arch) generic map(W, CW)
    port map(clk => clk, rst => rst, ctrl_valid => v, ctrl_ready => h2_r, data => d, space => h2_k,
             outs => h2_o, outs_valid => h2_v, outs_ready => r, outs_space => k);
  g_unbundle : entity work.gen_unbundle
    port map(clk => clk, rst => rst, ins => d, ins_valid => v, ins_ready => g3_r,
             ctrl_valid => g3_v, ctrl_ready => r, data => g3_d);
  h_unbundle : entity work.handshake_unbundle(arch) generic map(W)
    port map(clk => clk, rst => rst, ins => d, ins_valid => v, ins_ready => h3_r,
             ctrl_valid => h3_v, ctrl_ready => r, data => h3_d);
  g_unbundle_size : entity work.gen_unbundle_size
    port map(clk => clk, rst => rst, ins => d, ins_valid => v, ins_ready => g4_r, ins_size => k,
             ctrl_valid => g4_v, ctrl_ready => r, data => g4_d, size => g4_k);
  h_unbundle_size : entity work.handshake_unbundle_size(arch) generic map(W, CW)
    port map(clk => clk, rst => rst, ins => d, ins_valid => v, ins_ready => h4_r, ins_size => k,
             ctrl_valid => h4_v, ctrl_ready => r, data => h4_d, size => h4_k);
  g_bundle_control : entity work.gen_bundle_control
    port map(clk => clk, rst => rst, valid => v, ctrl_valid => g5_v, ctrl_ready => r, ready => g5_r);
  h_bundle_control : entity work.handshake_bundle_control(arch)
    port map(clk => clk, rst => rst, valid => v, ctrl_valid => h5_v, ctrl_ready => r, ready => h5_r);
  g_unbundle_control : entity work.gen_unbundle_control
    port map(clk => clk, rst => rst, ins_valid => v, ins_ready => g6_r, ready => r, valid => g6_v);
  h_unbundle_control : entity work.handshake_unbundle_control(arch)
    port map(clk => clk, rst => rst, ins_valid => v, ins_ready => h6_r, ready => r, valid => h6_v);

  process
    variable lfsr : unsigned(62 downto 0) := to_unsigned(12345, 63);
    variable compared, muxed, merged : natural := 0;
    variable dense : boolean;

    procedure step is
    begin
      for i in 1 to 63 loop
        lfsr := lfsr(61 downto 0) & (lfsr(62) xor lfsr(61));
      end loop;
    end procedure;

    -- A W-bit word of fresh bits (W may be above 63).
    impure function fresh return word is
      variable res : word;
    begin
      for i in 0 to W - 1 loop
        if i mod 60 = 0 then
          step;
        end if;
        res(i) := lfsr(i mod 60);
      end loop;
      return res;
    end function;

    procedure compare is
    begin
      assert gm_o = hm_o and gm_r = hm_r and gm_v = hm_v and gm_s = hm_s
        report "the mux differs from its generator's at step " & integer'image(compared)
        severity failure;
      assert gb_o = hb_o and gb_r = hb_r and gb_v = hb_v and gb_s = hb_s
        report "the mux without a slot differs from its generator's at step " & integer'image(compared)
        severity failure;
      assert gc_r = hc_r and gc_v = hc_v and gc_s = hc_s
        report "the mux without data differs from its generator's at step " & integer'image(compared)
        severity failure;
      assert gd_r = hd_r and gd_v = hd_v and gd_s = hd_s
        report "the mux without data or a slot differs from its generator's at step " & integer'image(compared)
        severity failure;
      assert gx_o = hx_o and gx_i = hx_i and gx_r = hx_r and gx_v = hx_v and gx_iv = hx_iv
        report "the control merge differs from its generator's at step " & integer'image(compared)
        severity failure;
      assert gy_i = hy_i and gy_r = hy_r and gy_v = hy_v and gy_iv = hy_iv
        report "the control merge without data differs from its generator's at step " & integer'image(compared)
        severity failure;
      assert g1_o = h1_o and g1_v = h1_v and g1_r = h1_r
        report "the bundle differs from its generator's at step " & integer'image(compared)
        severity failure;
      assert g2_o = h2_o and g2_v = h2_v and g2_r = h2_r and g2_k = h2_k
        report "the bundle with a space differs from its generator's at step " & integer'image(compared)
        severity failure;
      assert g3_d = h3_d and g3_v = h3_v and g3_r = h3_r
        report "the unbundle differs from its generator's at step " & integer'image(compared)
        severity failure;
      assert g4_d = h4_d and g4_v = h4_v and g4_r = h4_r and g4_k = h4_k
        report "the unbundle with a size differs from its generator's at step " & integer'image(compared)
        severity failure;
      assert g5_v = h5_v and g5_r = h5_r and g6_v = h6_v and g6_r = h6_r
        report "a bundle or unbundle of a control differs from its generator's at step " & integer'image(compared)
        severity failure;
      compared := compared + 1;
    end procedure;
  begin
    for c in 0 to CYCLES loop
      -- Dense valids for a stretch, sparse for the next: a control merge's
      -- arbiter sees several inputs on the first, one alone on the second.
      dense := (c / 64) mod 2 = 0;
      for i in 0 to SIZE - 1 loop
        ins(i) <= fresh;
        step;
        if dense then
          ins_valid(i) <= lfsr(0) or lfsr(1);
        else
          ins_valid(i) <= lfsr(0) and lfsr(1);
        end if;
      end loop;
      -- the select: any value of its width, one of the inputs most of the time
      step;
      if lfsr(3 downto 0) = "0000" then
        sel <= std_logic_vector(resize(lfsr(40 downto 10), IW));
      else
        sel <= std_logic_vector(to_unsigned(to_integer(lfsr(30 downto 10)) mod SIZE, IW));
      end if;
      sel_valid   <= lfsr(4) or lfsr(5);
      outs_ready  <= lfsr(6) or lfsr(7);
      index_ready <= lfsr(8) or lfsr(9);
      d <= fresh;
      step;
      k <= std_logic_vector(resize(lfsr(40 downto 10), CW));
      v <= lfsr(0);
      r <= lfsr(1);
      -- a reset at the start and now and then
      if c < 2 or c mod 509 = 508 then
        rst <= '1';
      else
        rst <= '0';
      end if;
      wait for 4 ns;
      if c >= 2 then
        compare;
        if rst = '0' and gm_v = '1' and outs_ready = '1' then
          muxed := muxed + 1;
        end if;
        if rst = '0' and gx_v = '1' and outs_ready = '1' then
          merged := merged + 1;
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
    -- the run was not idle: the mux and the control merge passed tokens
    assert muxed > CYCLES / 16 and merged > CYCLES / 16
      report "the stimulus was idle: " & integer'image(muxed) & " tokens through the mux, "
             & integer'image(merged) & " through the control merge"
      severity failure;
    report "equal to the generator's over " & integer'image(compared) & " comparisons";
    wait;
  end process;
end architecture;
