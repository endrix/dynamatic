-- The generic sequential dividers of data/vhdl/handshake/generic in lockstep
-- with the units their generator writes at the same width (entities
-- gen_divui, gen_divsi, gen_remui and gen_remsi), used by
-- generic-vs-generator-4-ghdl.mlir: the same random valid, ready and
-- operands at every cycle, a reset now and then, every output compared
-- before and after each clock edge. The generic entity is the generator's
-- logic, and this is what keeps the two from drifting apart.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb is
  generic (
    W      : positive := 8;
    CYCLES : positive := 4000
  );
end entity;

architecture sim of tb is
  subtype word is std_logic_vector(W - 1 downto 0);
  signal clk : std_logic := '0';
  signal rst : std_logic := '1';
  signal a, b       : word      := (others => '0');
  signal av, bv, rr : std_logic := '0';
  signal g_du, h_du, g_ds, h_ds, g_ru, h_ru, g_rs, h_rs                         : word;
  signal g_du_a, h_du_a, g_ds_a, h_ds_a, g_ru_a, h_ru_a, g_rs_a, h_rs_a         : std_logic;
  signal g_du_b, h_du_b, g_ds_b, h_ds_b, g_ru_b, h_ru_b, g_rs_b, h_rs_b         : std_logic;
  signal g_du_v, h_du_v, g_ds_v, h_ds_v, g_ru_v, h_ru_v, g_rs_v, h_rs_v         : std_logic;
begin
  g_divui : entity work.gen_divui port map(clk, rst, a, av, g_du_a, b, bv, g_du_b, g_du, g_du_v, rr);
  h_divui : entity work.handshake_divider_sequential(divui) generic map(W)
    port map(clk, rst, a, av, h_du_a, b, bv, h_du_b, h_du, h_du_v, rr);
  g_divsi : entity work.gen_divsi port map(clk, rst, a, av, g_ds_a, b, bv, g_ds_b, g_ds, g_ds_v, rr);
  h_divsi : entity work.handshake_divider_sequential(divsi) generic map(W)
    port map(clk, rst, a, av, h_ds_a, b, bv, h_ds_b, h_ds, h_ds_v, rr);
  g_remui : entity work.gen_remui port map(clk, rst, a, av, g_ru_a, b, bv, g_ru_b, g_ru, g_ru_v, rr);
  h_remui : entity work.handshake_divider_sequential(remui) generic map(W)
    port map(clk, rst, a, av, h_ru_a, b, bv, h_ru_b, h_ru, h_ru_v, rr);
  g_remsi : entity work.gen_remsi port map(clk, rst, a, av, g_rs_a, b, bv, g_rs_b, g_rs, g_rs_v, rr);
  h_remsi : entity work.handshake_divider_sequential(remsi) generic map(W)
    port map(clk, rst, a, av, h_rs_a, b, bv, h_rs_b, h_rs, h_rs_v, rr);

  process
    variable lfsr : unsigned(62 downto 0) := to_unsigned(12345, 63);
    variable compared, results, by_zero, negative : natural := 0;
    -- the most negative dividend over minus one, a result held back by its
    -- consumer, a reset while a division runs
    variable extreme, stalled, cut : natural := 0;
    variable running : boolean := false;
    variable kind : natural;

    -- the most negative word: its sign bit alone
    function most_negative return word is
      variable r : word := (others => '0');
    begin
      r(W - 1) := '1';
      return r;
    end function;

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
      assert g_du = h_du and g_du_a = h_du_a and g_du_b = h_du_b and g_du_v = h_du_v
        report "the divui differs from its generator's at step " & integer'image(compared)
        severity failure;
      assert g_ds = h_ds and g_ds_a = h_ds_a and g_ds_b = h_ds_b and g_ds_v = h_ds_v
        report "the divsi differs from its generator's at step " & integer'image(compared)
        severity failure;
      assert g_ru = h_ru and g_ru_a = h_ru_a and g_ru_b = h_ru_b and g_ru_v = h_ru_v
        report "the remui differs from its generator's at step " & integer'image(compared)
        severity failure;
      assert g_rs = h_rs and g_rs_a = h_rs_a and g_rs_b = h_rs_b and g_rs_v = h_rs_v
        report "the remsi differs from its generator's at step " & integer'image(compared)
        severity failure;
      compared := compared + 1;
    end procedure;
  begin
    for c in 0 to CYCLES loop
      -- the operands: any two words; a small divisor, a zero one, the most
      -- negative dividend and a divisor of all ones (minus one) now and then
      a <= fresh;
      b <= fresh;
      step;
      kind := to_integer(lfsr(3 downto 0));
      if kind < 4 then
        b <= std_logic_vector(resize(lfsr(10 downto 8), W));
      elsif kind = 4 then
        b <= (others => '0');
      elsif kind = 5 then
        a        <= (others => '0');
        a(W - 1) <= '1';
        b <= (others => '1');
      end if;
      av <= lfsr(4) or lfsr(5);
      bv <= lfsr(6) or lfsr(7);
      rr <= lfsr(11) or lfsr(12);
      -- a reset at the start and now and then, mid-division
      if c < 2 or c mod 509 = 508 then
        rst <= '1';
      else
        rst <= '0';
      end if;
      wait for 4 ns;
      if c >= 2 then
        compare;
        if rst = '1' then
          if running and g_ds_v = '0' then
            cut := cut + 1;
          end if;
          running := false;
        else
          if g_ds_v = '1' then
            running := false;
            if rr = '1' then
              results := results + 1;
            else
              stalled := stalled + 1;
            end if;
          end if;
          if g_ds_a = '1' and av = '1' and bv = '1' then
            running := true;
            if unsigned(b) = 0 then
              by_zero := by_zero + 1;
            end if;
            if a(W - 1) = '1' then
              negative := negative + 1;
            end if;
            if a = most_negative and unsigned(not b) = 0 then
              extreme := extreme + 1;
            end if;
          end if;
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
    -- the run was not idle: divisions finished, some by zero, some of a
    -- negative dividend, some of the most negative one over minus one; a
    -- result waited for its consumer; a reset cut a division short
    assert results > CYCLES / (4 * (W + 2)) and by_zero > 0 and negative > 0
           and extreme > 0 and stalled > 0 and cut > 0
      report "the stimulus was idle: " & integer'image(results) & " results, "
             & integer'image(by_zero) & " by zero, " & integer'image(negative) & " negative, "
             & integer'image(extreme) & " of the most negative over minus one, "
             & integer'image(stalled) & " cycles a result waited, "
             & integer'image(cut) & " divisions cut by a reset"
      severity failure;
    report "equal to the generator's over " & integer'image(compared) & " comparisons";
    wait;
  end process;
end architecture;
