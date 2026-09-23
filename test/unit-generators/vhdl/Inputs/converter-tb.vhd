-- A testbench for the int/float converters (sitofp, uitofp, fptosi), used by
-- converter-latency-ghdl.mlir: twelve operands in, the unit under test named
-- dut, its ready stalled one cycle in four, and every result compared with
-- the conversion computed here. Fails (severity failure) on a wrong result
-- or a missing one.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.float_pkg.all;

entity tb is
  generic (KIND : string := "sitofp");
end entity;

architecture sim of tb is
  signal clk, rst : std_logic := '1';
  signal ins, outs : std_logic_vector(31 downto 0) := (others => '0');
  signal iv, ir, ov, orr : std_logic := '0';
  signal sent, got, bad : integer := 0;

  function operand(i : integer) return std_logic_vector is
  begin
    if KIND = "fptosi" then
      return to_slv(to_float(real(i * 7 - 20), float32'high, -float32'low));
    end if;
    return std_logic_vector(to_signed(i * 7 - 20, 32));
  end function;

  function expected(i : integer) return std_logic_vector is
  begin
    if KIND = "fptosi" then
      return std_logic_vector(to_signed(i * 7 - 20, 32));
    elsif KIND = "uitofp" then
      return to_slv(to_float(unsigned(std_logic_vector(to_signed(i * 7 - 20, 32)))));
    end if;
    return to_slv(to_float(to_signed(i * 7 - 20, 32)));
  end function;
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
      if sent < 12 then
        iv <= '1';
        ins <= operand(sent);
      else
        iv <= '0';
      end if;
      wait until rising_edge(clk);
      if iv = '1' and ir = '1' then
        sent <= sent + 1;
      end if;
      if ov = '1' and orr = '1' then
        if outs /= expected(got) then
          bad <= bad + 1;
        end if;
        got <= got + 1;
      end if;
    end loop;
    wait for 1 ns;
    report KIND & ": " & integer'image(got) & " results, " & integer'image(bad) & " wrong";
    assert got = 12 and bad = 0 report KIND & ": FAILED" severity failure;
    std.env.stop;
  end process;
end architecture;
