-- A testbench for a queue holding tokens at reset, used by
-- queue-initial-tokens-ghdl.mlir. The unit under test is named dut, 16 bits
-- wide with `size` and `space` of 3 bits; NINIT is how many tokens it holds at
-- reset (-3, 7, 42 in that order) and SLOTS its depth. Right after reset it
-- must offer the first of them (or nothing, for none) with `size` = NINIT
-- and `space` = SLOTS - NINIT; then ten tokens 100..109 go in under a ready stalled one cycle in
-- three, and what comes out must be the tokens held at reset then the ten, in
-- order, with a held output never changing. Fails (severity failure) on the
-- first thing wrong.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb is
  generic (NINIT : integer := 2; SLOTS : integer := 4);
end entity;

architecture sim of tb is
  signal clk, rst : std_logic := '1';
  signal ins, outs : std_logic_vector(15 downto 0) := (others => '0');
  signal iv, ir, ov, orr : std_logic := '0';
  signal size, space : std_logic_vector(2 downto 0);
  signal sent, got : integer := 0;
  constant TOTAL : integer := NINIT + 10;
  type ints is array (0 to 2) of integer;
  constant HELD : ints := (-3, 7, 42);

  function expected(i : integer) return integer is
  begin
    if i < NINIT then
      return HELD(i);
    end if;
    return 100 + i - NINIT;
  end function;
begin
  clk <= not clk after 5 ns;

  dut : entity work.dut
    port map (clk => clk, rst => rst, ins => ins, ins_valid => iv,
              ins_ready => ir, ins_space => space, outs => outs,
              outs_valid => ov, outs_ready => orr, outs_size => size);

  iv <= '1' when sent < 10 else '0';
  ins <= std_logic_vector(to_signed(100 + sent, 16));

  process
    variable cycle : integer := 0;
    variable held_valid : boolean := false;
    variable held_data : std_logic_vector(15 downto 0);
    variable take_in, take_out : boolean;
  begin
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    rst <= '0';
    wait for 1 ns;
    if NINIT > 0 then
      assert ov = '1' report "not valid out of reset" severity failure;
      assert to_integer(signed(outs)) = HELD(0)
        report "first token " & integer'image(to_integer(signed(outs)))
        severity failure;
    else
      assert ov = '0' report "valid out of reset, holding nothing" severity failure;
    end if;
    assert to_integer(unsigned(size)) = NINIT
      report "size " & integer'image(to_integer(unsigned(size))) severity failure;
    assert to_integer(unsigned(space)) = SLOTS - NINIT
      report "space " & integer'image(to_integer(unsigned(space))) severity failure;
    while got < TOTAL and cycle < 200 loop
      if cycle mod 3 = 2 then orr <= '0'; else orr <= '1'; end if;
      wait for 1 ns;
      if held_valid then
        assert ov = '1' and outs = held_data
          report "held output changed" severity failure;
      end if;
      held_valid := ov = '1' and orr = '0';
      held_data := outs;
      take_out := ov = '1' and orr = '1';
      take_in := iv = '1' and ir = '1';
      if take_out then
        assert to_integer(signed(outs)) = expected(got)
          report "token " & integer'image(got) & " is "
                 & integer'image(to_integer(signed(outs))) & ", want "
                 & integer'image(expected(got)) severity failure;
      end if;
      -- the transfers happen at this edge; the counters move after it
      wait until rising_edge(clk);
      if take_out then got <= got + 1; end if;
      if take_in then sent <= sent + 1; end if;
      cycle := cycle + 1;
    end loop;
    assert got = TOTAL report "only " & integer'image(got) & " tokens" severity failure;
    report integer'image(got) & " tokens in order";
    std.env.stop;
    wait;
  end process;
end architecture;
