-- The generic init, init without data and sequential multiplier of
-- data/vhdl/handshake/generic in lockstep with the units their generator
-- writes at the same parameters (entities gen_init, gen_init_control and
-- gen_muli), used by generic-vs-generator-ghdl.mlir: the same random valid,
-- ready and data at every cycle, a reset now and then, every output compared
-- before and after each clock edge. The generic entity is the generator's
-- logic, and this is what keeps the two from drifting apart.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb is
  generic (
    W : positive := 8;
    S : positive := 3;
    V : string := "5";
    N : positive := 3000
  );
end entity;

architecture sim of tb is
  subtype word is std_logic_vector(W - 1 downto 0);
  signal clk : std_logic := '0';
  signal rst : std_logic := '1';
  signal i_in, a, b : word := (others => '0');
  signal i_iv, i_or, d_iv, d_or, av, bv, pr : std_logic := '0';
  signal g_out, h_out, g_p, h_p : word;
  signal g_ir, h_ir, g_ov, h_ov : std_logic;
  signal gd_ir, hd_ir, gd_ov, hd_ov : std_logic;
  signal g_ar, h_ar, g_br, h_br, g_pv, h_pv : std_logic;
begin
  g_init : entity work.gen_init port map(clk, rst, i_in, i_iv, g_ir, g_out, g_ov, i_or);
  h_init : entity work.handshake_init(arch) generic map(V, W)
    port map(clk, rst, i_in, i_iv, h_ir, h_out, h_ov, i_or);
  g_initd : entity work.gen_init_control port map(clk, rst, d_iv, gd_ir, gd_ov, d_or);
  h_initd : entity work.handshake_init_dataless(arch)
    port map(clk, rst, d_iv, hd_ir, hd_ov, d_or);
  g_mul : entity work.gen_muli port map(clk, rst, a, av, g_ar, b, bv, g_br, g_p, g_pv, pr);
  h_mul : entity work.handshake_muli_sequential(arch) generic map(S, W)
    port map(clk, rst, a, av, h_ar, b, bv, h_br, h_p, h_pv, pr);

  process
    variable lfsr : unsigned(62 downto 0) := to_unsigned(12345, 63);
    variable compared, products : natural := 0;

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
      assert g_out = h_out and g_ir = h_ir and g_ov = h_ov
        report "the init differs from its generator's at step " & integer'image(compared)
        severity failure;
      assert gd_ir = hd_ir and gd_ov = hd_ov
        report "the init without data differs from its generator's at step " & integer'image(compared)
        severity failure;
      assert g_p = h_p and g_ar = h_ar and g_br = h_br and g_pv = h_pv
        report "the multiplier differs from its generator's at step " & integer'image(compared)
        severity failure;
      if h_pv = '1' and pr = '1' then
        products := products + 1;
      end if;
      compared := compared + 1;
    end procedure;
  begin
    clk <= '1'; wait for 1 ns; clk <= '0'; wait for 1 ns;
    compare;
    rst <= '0';
    wait for 1 ns;
    compare;
    for c in 1 to N loop
      step;
      i_in <= fresh; a <= fresh; b <= fresh;
      i_iv <= lfsr(0); i_or <= lfsr(1); d_iv <= lfsr(2); d_or <= lfsr(3);
      av <= lfsr(4) or lfsr(10); bv <= lfsr(5) or lfsr(11); pr <= lfsr(6) or lfsr(12);
      if lfsr(20 downto 14) = 0 then
        rst <= '1';
      else
        rst <= '0';
      end if;
      wait for 1 ns;
      compare;
      clk <= '1'; wait for 1 ns;
      compare;
      clk <= '0'; wait for 1 ns;
    end loop;
    -- A run that multiplied nothing compared nothing of the multiplier.
    assert products > 10
      report "only " & integer'image(products) & " products" severity failure;
    report "equal to the generator's over " & integer'image(compared) & " steps, "
      & integer'image(products) & " products";
    wait;
  end process;
end architecture;
