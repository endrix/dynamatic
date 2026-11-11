-- A testbench for the generic handshake units of data/vhdl/handshake/generic,
-- used by handshake-generic-ghdl.mlir: every unit at the width W, its data
-- against results the testbench computes itself and its handshake against
-- the join (or the forwarding) the unit is. Shift amounts stay below 2**8:
-- the units read the amount as their generator does, with `to_integer`.
-- Fails (severity failure) on a wrong result.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb is
  generic (W : positive := 8);
end entity;

architecture sim of tb is
  constant X : positive := W + 3;
  subtype word is std_logic_vector(W - 1 downto 0);
  subtype wide is std_logic_vector(X - 1 downto 0);
  subtype bit1 is std_logic_vector(0 downto 0);
  type preds is array (0 to 9) of string(1 to 3);
  constant P : preds := ("eq ", "ne ", "slt", "sle", "sgt", "sge", "ult", "ule", "ugt", "uge");

  signal clk : std_logic := '0';
  signal rst : std_logic := '1';
  signal a, b : word := (others => '0');
  signal ax : wide := (others => '0');
  signal c : bit1 := "0";
  signal av, bv, cv, rdy : std_logic := '0';
  signal shl_r, shru_r, shrs_r, trunc_r, sel_r, k_r : word;
  signal shl_v, shru_v, shrs_v, trunc_v, sel_v, k_v : std_logic;
  signal shl_ar, shl_br, shru_ar, shru_br, shrs_ar, shrs_br, trunc_ar, k_cr : std_logic;
  signal sel_cr, sel_tr, sel_fr : std_logic;
  type bits is array (0 to 9) of bit1;
  signal cmp_r : bits;
  signal cmp_v, cmp_ar, cmp_br : std_logic_vector(0 to 9);
  constant KV : word := std_logic_vector(to_unsigned(5 mod 2 ** minimum(W, 20), W));

  function trim(s : string) return string is
  begin
    if s(3) = ' ' then
      return s(1 to 2);
    end if;
    return s;
  end function;

  function bit_of(cond : boolean) return bit1 is
  begin
    if cond then
      return "1";
    end if;
    return "0";
  end function;
begin
  u_shl : entity work.handshake_shli(arch) generic map(W)
    port map(clk, rst, a, av, shl_ar, b, bv, shl_br, shl_r, shl_v, rdy);
  u_shru : entity work.handshake_shrui(arch) generic map(W)
    port map(clk, rst, a, av, shru_ar, b, bv, shru_br, shru_r, shru_v, rdy);
  u_shrs : entity work.handshake_shrsi(arch) generic map(W)
    port map(clk, rst, a, av, shrs_ar, b, bv, shrs_br, shrs_r, shrs_v, rdy);
  u_trunc : entity work.handshake_trunci(arch) generic map(X, W)
    port map(clk, rst, ax, av, trunc_ar, trunc_r, trunc_v, rdy);
  u_k : entity work.handshake_constant(arch) generic map(KV, W)
    port map(clk, rst, av, k_cr, k_r, k_v, rdy);
  u_sel : entity work.handshake_select(arch) generic map(W)
    port map(clk, rst, c, cv, sel_cr, a, av, sel_tr, b, bv, sel_fr, sel_r, sel_v, rdy);
  cmps : for i in 0 to 9 generate
    u_cmp : entity work.handshake_cmpi(arch) generic map(trim(P(i)), W)
      port map(clk, rst, a, av, cmp_ar(i), b, bv, cmp_br(i), cmp_r(i), cmp_v(i), rdy);
  end generate;

  process
    variable lfsr : unsigned(62 downto 0) := to_unsigned(1, 63);
    variable checks : natural := 0;
    variable xa, xb : word;
    variable amount : natural;
    variable both : std_logic;
    variable want : bit1;

    procedure step is
    begin
      for i in 1 to 63 loop
        lfsr := lfsr(61 downto 0) & (lfsr(62) xor lfsr(61));
      end loop;
    end procedure;

    procedure check(cond : boolean; what : string) is
    begin
      assert cond
        report "handshake generic, W=" & integer'image(W) & ": wrong " & what
        severity failure;
      checks := checks + 1;
    end procedure;
  begin
    wait for 2 ns;
    clk <= '1'; wait for 1 ns; clk <= '0'; wait for 1 ns;
    rst <= '0';
    for i in 1 to 400 loop
      step;
      xa := std_logic_vector(lfsr(W - 1 downto 0));
      step;
      xb := (others => '0');
      xb(minimum(W, 8) - 1 downto 0) := std_logic_vector(lfsr(minimum(W, 8) - 1 downto 0));
      if i mod 5 = 0 then
        xb := xa; -- equal operands, for the comparisons
        xb(W - 1 downto minimum(W, 8)) := (others => '0');
        xa := xb;
      end if;
      step;
      a <= xa; b <= xb; ax <= std_logic_vector(lfsr(X - 1 downto 0));
      av <= lfsr(40); bv <= lfsr(41); rdy <= lfsr(42);
      -- The select is checked on its data and with all three operands there:
      -- its antitokens are the generator's own, checked against it elsewhere.
      c(0) <= lfsr(43); cv <= '1';
      wait for 1 ns;
      both := av and bv;
      -- The amount is the low W - 1 bits of rhs.
      if W = 1 then
        amount := 0;
      else
        amount := to_integer(unsigned(xb(minimum(W - 1, 8) - 1 downto 0)));
      end if;
      check(shl_r = std_logic_vector(shift_left(unsigned(xa), amount)), "shli");
      check(shru_r = std_logic_vector(shift_right(unsigned(xa), amount)), "shrui");
      check(shrs_r = std_logic_vector(shift_right(signed(xa), amount)), "shrsi");
      -- A join of the two operands.
      check(shl_v = both and shru_v = both and shrs_v = both, "shift valid");
      check(shl_ar = (bv and rdy) and shl_br = (av and rdy), "shli ready");
      check(shru_ar = (bv and rdy) and shrs_br = (av and rdy), "shift ready");
      check(trunc_r = ax(W - 1 downto 0), "trunci");
      check(trunc_v = av and trunc_ar = rdy, "trunci handshake");
      check(k_r = KV, "constant");
      check(k_v = av and k_cr = rdy, "constant handshake");
      for q in 0 to 9 loop
        case q is
          when 0 => want := bit_of(xa = xb);
          when 1 => want := bit_of(xa /= xb);
          when 2 => want := bit_of(signed(xa) < signed(xb));
          when 3 => want := bit_of(signed(xa) <= signed(xb));
          when 4 => want := bit_of(signed(xa) > signed(xb));
          when 5 => want := bit_of(signed(xa) >= signed(xb));
          when 6 => want := bit_of(unsigned(xa) < unsigned(xb));
          when 7 => want := bit_of(unsigned(xa) <= unsigned(xb));
          when 8 => want := bit_of(unsigned(xa) > unsigned(xb));
          when others => want := bit_of(unsigned(xa) >= unsigned(xb));
        end case;
        check(cmp_r(q) = want, "cmpi " & trim(P(q)));
        check(cmp_v(q) = both and cmp_ar(q) = (bv and rdy) and cmp_br(q) = (av and rdy), "cmpi handshake");
      end loop;
      if c(0) = '1' then
        check(sel_r = xa, "select, true");
      else
        check(sel_r = xb, "select, false");
      end if;
      if both = '1' then
        check(sel_v = '1', "select valid, every operand there");
      end if;
      clk <= '1'; wait for 1 ns; clk <= '0'; wait for 1 ns;
      -- Leave no antitoken behind: offer both operands until it is gone.
      av <= '1'; bv <= '1'; rdy <= '1';
      for d in 1 to 3 loop
        clk <= '1'; wait for 1 ns; clk <= '0'; wait for 1 ns;
      end loop;
    end loop;
    report "handshake generic, W=" & integer'image(W) & ": " & integer'image(checks)
      & " checks as expected";
    wait;
  end process;
end architecture;
