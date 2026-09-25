-- A testbench for the int/float converters' rounding, used by
-- converter-rounding-ghdl.mlir: operands whose conversion is not exact, in
-- and out as bit patterns, so the expected results do not come from the
-- package the units use. fptosi truncates toward zero (C, MLIR's
-- arith.fptosi, RISC-V's fcvt.w.s) and saturates out of range; sitofp and
-- uitofp round to nearest, ties to even. The unit under test is dut; fails
-- (severity failure) on a wrong result or a missing one.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb is
  generic (KIND : string := "fptosi");
end entity;

architecture sim of tb is
  type words is array (natural range <>) of std_logic_vector(31 downto 0);
  -- fptosi: 11.75, -11.75, 0.5, -0.5, 2.5, -2.5, 0.99999994, -0.99999994,
  -- 1e9, 2147483520, -2147483648, 2^31 (saturates), -2^31 - 256
  -- (saturates), +inf, -inf
  constant FPTOSI_IN : words := (
    x"413C0000", x"C13C0000", x"3F000000", x"BF000000", x"40200000",
    x"C0200000", x"3F7FFFFF", x"BF7FFFFF", x"4E6E6B28", x"4EFFFFFF",
    x"CF000000", x"4F000000", x"CF000001", x"7F800000", x"FF800000");
  constant FPTOSI_OUT : words := (
    x"0000000B", x"FFFFFFF5", x"00000000", x"00000000", x"00000002",
    x"FFFFFFFE", x"00000000", x"00000000", x"3B9ACA00", x"7FFFFF80",
    x"80000000", x"7FFFFFFF", x"80000000", x"7FFFFFFF", x"80000000");
  -- sitofp: 2^24 + 1 (tie, to even: 2^24), 2^24 + 3 (tie, to 2^24 + 4),
  -- 2^24 + 5 (tie, to 2^24 + 4), 2^31 - 1 (to 2^31), -(2^24 + 1),
  -- -(2^24 + 3), 2^25 + 3 (to 2^25 + 4), 7
  constant SITOFP_IN : words := (
    x"01000001", x"01000003", x"01000005", x"7FFFFFFF", x"FEFFFFFF",
    x"FEFFFFFD", x"02000003", x"00000007");
  constant SITOFP_OUT : words := (
    x"4B800000", x"4B800002", x"4B800002", x"4F000000", x"CB800000",
    x"CB800002", x"4C000001", x"40E00000");
  -- uitofp: 2^32 - 1 (to 2^32), 2^31 + 1 (to 2^31), 2^24 + 1, 2^24 + 3,
  -- 2^31 + 2^7 (tie, to even: 2^31), 2^31 + 3 * 2^7 (tie, to 2^31 + 2^9), 7
  constant UITOFP_IN : words := (
    x"FFFFFFFF", x"80000001", x"01000001", x"01000003", x"80000080",
    x"80000180", x"00000007");
  constant UITOFP_OUT : words := (
    x"4F800000", x"4F000000", x"4B800000", x"4B800002", x"4F000000",
    x"4F000002", x"40E00000");

  function pick(f, s, u : words) return words is
  begin
    if KIND = "fptosi" then
      return f;
    elsif KIND = "sitofp" then
      return s;
    end if;
    return u;
  end function;

  constant OPS : words := pick(FPTOSI_IN, SITOFP_IN, UITOFP_IN);
  constant WANT : words := pick(FPTOSI_OUT, SITOFP_OUT, UITOFP_OUT);
  constant N : natural := OPS'length;

  signal clk, rst : std_logic := '1';
  signal ins, outs : std_logic_vector(31 downto 0) := (others => '0');
  signal iv, ir, ov, orr : std_logic := '0';
  signal sent, got, bad : integer := 0;
begin
  clk <= not clk after 5 ns;

  dut : entity work.dut
    port map(clk => clk, rst => rst, ins => ins, ins_valid => iv, ins_ready => ir,
             outs => outs, outs_valid => ov, outs_ready => orr);

  process
  begin
    wait for 20 ns;
    rst <= '0';
    for c in 0 to 80 loop
      wait until falling_edge(clk);
      orr <= '1' when (c mod 4) /= 2 else '0';
      if sent < N then
        iv <= '1';
        ins <= OPS(sent);
      else
        iv <= '0';
      end if;
      wait until rising_edge(clk);
      if iv = '1' and ir = '1' then
        sent <= sent + 1;
      end if;
      if ov = '1' and orr = '1' then
        if outs /= WANT(got) then
          report KIND & ": " & to_hstring(OPS(got)) & " gave " & to_hstring(outs)
            & ", want " & to_hstring(WANT(got));
          bad <= bad + 1;
        end if;
        got <= got + 1;
      end if;
    end loop;
    wait for 1 ns;
    report KIND & ": " & integer'image(got) & " of " & integer'image(N)
      & " results, " & integer'image(bad) & " wrong";
    assert got = N and bad = 0 report KIND & ": FAILED" severity failure;
    std.env.stop;
  end process;
end architecture;
