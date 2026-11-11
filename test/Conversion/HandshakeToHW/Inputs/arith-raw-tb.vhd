-- A testbench for the generic arith units on raw wires (data/vhdl/arith/raw),
-- used by arith-raw-ghdl.mlir: every unit at the width W, against results the
-- testbench computes itself. W = 1 is the case of a port that is a vector of
-- one element; W above 31 is the case of a shift amount `to_integer` cannot
-- take whole. Fails (severity failure) on a wrong result.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb is
  generic (W : positive := 8);
end entity;

architecture sim of tb is
  constant X : positive := W + 3; -- the wide side of the extensions
  subtype word is std_logic_vector(W - 1 downto 0);
  subtype wide is std_logic_vector(X - 1 downto 0);
  subtype bit1 is std_logic_vector(0 downto 0);

  signal clk, rst : std_logic := '0';
  signal a, b : word := (others => '0');
  signal c : bit1 := "0";
  signal ax : wide := (others => '0');
  signal add_r, sub_r, mul_r, and_r, or_r, xor_r : word;
  signal shl_r, shru_r, shrs_r, sel_r, trunc_r : word;
  signal extu_r, exts_r : wide;
  signal eq_r, ne_r, slt_r, sle_r, sgt_r, sge_r : bit1;
  signal ult_r, ule_r, ugt_r, uge_r : bit1;
  signal k5 : std_logic_vector(4 downto 0);
  signal k1 : bit1;

  function bit_of(cond : boolean) return bit1 is
  begin
    if cond then
      return "1";
    end if;
    return "0";
  end function;
begin
  u_add : entity work.arith_addi(arch) generic map(W) port map(clk, rst, a, b, add_r);
  u_sub : entity work.arith_subi(arch) generic map(W) port map(clk, rst, a, b, sub_r);
  u_mul : entity work.arith_muli(arch) generic map(W) port map(clk, rst, a, b, mul_r);
  u_and : entity work.arith_andi(arch) generic map(W) port map(clk, rst, a, b, and_r);
  u_or : entity work.arith_ori(arch) generic map(W) port map(clk, rst, a, b, or_r);
  u_xor : entity work.arith_xori(arch) generic map(W) port map(clk, rst, a, b, xor_r);
  u_shl : entity work.arith_shli(arch) generic map(W) port map(clk, rst, a, b, shl_r);
  u_shru : entity work.arith_shrui(arch) generic map(W) port map(clk, rst, a, b, shru_r);
  u_shrs : entity work.arith_shrsi(arch) generic map(W) port map(clk, rst, a, b, shrs_r);
  u_sel : entity work.arith_select(arch) generic map(W) port map(clk, rst, c, a, b, sel_r);
  u_trunc : entity work.arith_trunci(arch) generic map(X, W) port map(clk, rst, ax, trunc_r);
  u_extu : entity work.arith_extui(arch) generic map(W, X) port map(clk, rst, a, extu_r);
  u_exts : entity work.arith_extsi(arch) generic map(W, X) port map(clk, rst, a, exts_r);
  u_eq : entity work.arith_cmpi(arch) generic map("eq", W) port map(clk, rst, a, b, eq_r);
  u_ne : entity work.arith_cmpi(arch) generic map("ne", W) port map(clk, rst, a, b, ne_r);
  u_slt : entity work.arith_cmpi(arch) generic map("slt", W) port map(clk, rst, a, b, slt_r);
  u_sle : entity work.arith_cmpi(arch) generic map("sle", W) port map(clk, rst, a, b, sle_r);
  u_sgt : entity work.arith_cmpi(arch) generic map("sgt", W) port map(clk, rst, a, b, sgt_r);
  u_sge : entity work.arith_cmpi(arch) generic map("sge", W) port map(clk, rst, a, b, sge_r);
  u_ult : entity work.arith_cmpi(arch) generic map("ult", W) port map(clk, rst, a, b, ult_r);
  u_ule : entity work.arith_cmpi(arch) generic map("ule", W) port map(clk, rst, a, b, ule_r);
  u_ugt : entity work.arith_cmpi(arch) generic map("ugt", W) port map(clk, rst, a, b, ugt_r);
  u_uge : entity work.arith_cmpi(arch) generic map("uge", W) port map(clk, rst, a, b, uge_r);
  -- The value as the exporter writes it: a bit string, most significant first.
  u_k5 : entity work.arith_constant(arch) generic map("10110", 5) port map(clk, rst, k5);
  u_k1 : entity work.arith_constant(arch) generic map("1", 1) port map(clk, rst, k1);

  process
    variable lfsr : unsigned(62 downto 0) := to_unsigned(1, 63);
    variable checks : natural := 0;

    -- 63 fresh bits: x^63 + x^62 + 1
    procedure step is
    begin
      for i in 1 to 63 loop
        lfsr := lfsr(61 downto 0) & (lfsr(62) xor lfsr(61));
      end loop;
    end procedure;

    procedure check(cond : boolean; what : string) is
    begin
      assert cond
        report "arith raw, W=" & integer'image(W) & ": wrong " & what
        severity failure;
      checks := checks + 1;
    end procedure;

    -- One operand pair, every unit.
    procedure run(av, bv : word; cv : std_logic) is
      variable amount : natural;
      variable over : boolean;
      variable fill : word;
    begin
      a <= av;
      b <= bv;
      c(0) <= cv;
      ax <= std_logic_vector(lfsr(X - 1 downto 0));
      wait for 1 ns;
      check(add_r = std_logic_vector(unsigned(av) + unsigned(bv)), "addi");
      check(sub_r = std_logic_vector(unsigned(av) - unsigned(bv)), "subi");
      check(mul_r = std_logic_vector(resize(unsigned(av) * unsigned(bv), W)), "muli");
      check(and_r = (av and bv), "andi");
      check(or_r = (av or bv), "ori");
      check(xor_r = (av xor bv), "xori");
      -- A shift by the width or more leaves no bit of the operand.
      over := unsigned(bv) >= W;
      if over then
        amount := 0;
      else
        amount := to_integer(resize(unsigned(bv), 16));
      end if;
      fill := (others => av(W - 1));
      if over then
        check(unsigned(shl_r) = 0, "shli, amount over the width");
        check(unsigned(shru_r) = 0, "shrui, amount over the width");
        check(shrs_r = fill, "shrsi, amount over the width");
      else
        check(shl_r = std_logic_vector(shift_left(unsigned(av), amount)), "shli");
        check(shru_r = std_logic_vector(shift_right(unsigned(av), amount)), "shrui");
        check(shrs_r = std_logic_vector(shift_right(signed(av), amount)), "shrsi");
      end if;
      if cv = '1' then
        check(sel_r = av, "select, true");
      else
        check(sel_r = bv, "select, false");
      end if;
      check(trunc_r = ax(W - 1 downto 0), "trunci");
      check(extu_r = std_logic_vector(resize(unsigned(av), X)), "extui");
      check(exts_r = std_logic_vector(resize(signed(av), X)), "extsi");
      check(eq_r = bit_of(av = bv), "cmpi eq");
      check(ne_r = bit_of(av /= bv), "cmpi ne");
      check(slt_r = bit_of(signed(av) < signed(bv)), "cmpi slt");
      check(sle_r = bit_of(signed(av) <= signed(bv)), "cmpi sle");
      check(sgt_r = bit_of(signed(av) > signed(bv)), "cmpi sgt");
      check(sge_r = bit_of(signed(av) >= signed(bv)), "cmpi sge");
      check(ult_r = bit_of(unsigned(av) < unsigned(bv)), "cmpi ult");
      check(ule_r = bit_of(unsigned(av) <= unsigned(bv)), "cmpi ule");
      check(ugt_r = bit_of(unsigned(av) > unsigned(bv)), "cmpi ugt");
      check(uge_r = bit_of(unsigned(av) >= unsigned(bv)), "cmpi uge");
    end procedure;

    variable av, bv : word;
    constant ZERO : word := (others => '0');
    constant ONES : word := (others => '1');
    variable top : word;
  begin
    wait for 1 ns;
    check(k5 = "10110", "constant, five bits");
    check(k1 = "1", "constant, one bit");

    -- Random operands, and equal ones for the comparisons.
    for i in 1 to 200 loop
      step;
      av := std_logic_vector(lfsr(W - 1 downto 0));
      step;
      bv := std_logic_vector(lfsr(W - 1 downto 0));
      run(av, bv, lfsr(62));
      run(av, av, not lfsr(62));
    end loop;

    -- Every shift amount up to past the width, on an operand with its top
    -- bit set and on one with it clear.
    for s in 0 to W + 2 loop
      step;
      av := std_logic_vector(lfsr(W - 1 downto 0));
      bv := std_logic_vector(to_unsigned(s mod 2 ** minimum(W, 20), W));
      if s < 2 ** minimum(W, 20) then
        av(W - 1) := '1';
        run(av, bv, '1');
        av(W - 1) := '0';
        run(av, bv, '0');
      end if;
    end loop;

    -- An amount with only its top bit set: over the width at every width
    -- above one, and above bit 30 when the width is.
    top := (others => '0');
    top(W - 1) := '1';
    run(ONES, top, '1');
    run(top, top, '0');
    run(ONES, ONES, '1');
    run(ZERO, ZERO, '0');
    run(ZERO, ONES, '1');
    run(top, ZERO, '0');

    report "arith raw, W=" & integer'image(W) & ": " & integer'image(checks)
      & " checks as expected";
    wait;
  end process;
end architecture;
