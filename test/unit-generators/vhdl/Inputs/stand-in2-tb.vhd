-- A testbench for stand-in-ghdl.mlir: `dut`, a stand-in with two kills and a
-- 2-bit payload (the generator's, or the static entity under that name),
-- driven by ../../verilog/Inputs/stand-in2-vectors.txt, one line a cycle: the
-- inputs set, the combinational outputs checked, the clock ticks. Lines that
-- begin with '#' are comments. Fails (severity failure) on the first wrong
-- cycle; the unit's own assertion (its precondition) fails it too.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity tb is
end entity;

architecture sim of tb is
  signal clk : std_logic := '0';
  signal rst : std_logic := '1';
  signal iv, ordy, ov, ir : std_logic := '0';
  signal k : std_logic_vector(1 downto 0) := "00";
  signal ins, outs : std_logic_vector(1 downto 0) := "00";
  function b(i : integer) return std_logic is
  begin
    if i = 1 then return '1'; else return '0'; end if;
  end function;
begin
  clk <= not clk after 5 ns;
  dut : entity work.dut
    port map (clk => clk, rst => rst, ins => ins, ins_valid => iv, ins_ready => ir,
              kill => k, outs => outs, outs_valid => ov, outs_ready => ordy);
  process
    file f : text open read_mode is "stand-in2-vectors.txt";
    variable l : line;
    variable c : character;
    variable x : integer;
    variable e : integer_vector(0 to 8);
    variable cycle : integer := 0;
  begin
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    wait for 1 ns;
    while not endfile(f) loop
      readline(f, l);
      if l'length > 0 and l(l'left) /= '#' then
        for i in 0 to 8 loop
          read(l, x);
          e(i) := x;
        end loop;
        rst <= b(e(0)); iv <= b(e(1)); ins <= std_logic_vector(to_unsigned(e(2), 2));
        k(0) <= b(e(3)); k(1) <= b(e(4)); ordy <= b(e(5));
        wait for 1 ns;
        assert ov = b(e(6)) and ir = b(e(8)) and (e(6) = 0 or to_integer(unsigned(outs)) = e(7))
          report "cycle " & integer'image(cycle) & ": outs_valid " & std_logic'image(ov) &
                 " outs " & integer'image(to_integer(unsigned(outs))) & " ins_ready " & std_logic'image(ir)
          severity failure;
        wait until rising_edge(clk);
        wait for 1 ns;
        cycle := cycle + 1;
      end if;
    end loop;
    report "stand_in, two kills: " & integer'image(cycle) & " cycles as expected";
    std.env.finish;
  end process;
end architecture;
