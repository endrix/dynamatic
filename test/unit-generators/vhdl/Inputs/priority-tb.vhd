-- A testbench for handshake.priority, used by priority-ghdl.mlir. The unit
-- under test is named dut, 4 bits wide. One step a cycle: the inputs are set,
-- the combinational outputs checked, the clock ticks. The rounds: hi decides
-- alone the cycle it arrives and a late lo is absorbed; lo arriving first is
-- held and answered the cycle a zero hi arrives; a non-zero hi beats a lo that
-- came first; a zero hi waits for lo; a stalled sink keeps the answer while
-- the late input is absorbed; two zeros answer zero; rounds back to back, one
-- a cycle; a stalled answer from lo; a zero hi and lo in one cycle with the
-- sink stalled; the next round's hi offered while the round is open. Each
-- input is ready exactly while it has not given its round's token. Fails (severity failure) on the first thing
-- wrong.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb is
end entity;

architecture sim of tb is
  signal clk, rst : std_logic := '1';
  signal hi, lo, outs : std_logic_vector(3 downto 0) := (others => '0');
  signal hv, lv, hr, lr, ov, ordy : std_logic := '0';
begin
  clk <= not clk after 5 ns;

  dut : entity work.dut
    port map (clk => clk, rst => rst, hi => hi, hi_valid => hv, hi_ready => hr,
              lo => lo, lo_valid => lv, lo_ready => lr, outs => outs,
              outs_valid => ov, outs_ready => ordy);

  process
    variable cycle : integer := 0;
    -- set the inputs, check the outputs (e_o only when e_ov), tick
    procedure step(h_v : std_logic; h : integer; l_v : std_logic; l : integer;
                   r : std_logic; e_ov : std_logic; e_o : integer;
                   e_hr : std_logic; e_lr : std_logic) is
    begin
      hv <= h_v; hi <= std_logic_vector(to_unsigned(h, 4));
      lv <= l_v; lo <= std_logic_vector(to_unsigned(l, 4));
      ordy <= r;
      wait for 1 ns;
      assert ov = e_ov
        report "cycle " & integer'image(cycle) & ": outs_valid " & std_logic'image(ov)
        severity failure;
      if e_ov = '1' then
        assert to_integer(unsigned(outs)) = e_o
          report "cycle " & integer'image(cycle) & ": outs " &
                 integer'image(to_integer(unsigned(outs))) & ", expected " & integer'image(e_o)
          severity failure;
      end if;
      assert hr = e_hr
        report "cycle " & integer'image(cycle) & ": hi_ready " & std_logic'image(hr)
        severity failure;
      assert lr = e_lr
        report "cycle " & integer'image(cycle) & ": lo_ready " & std_logic'image(lr)
        severity failure;
      wait until rising_edge(clk);
      wait for 1 ns;
      cycle := cycle + 1;
    end procedure;
  begin
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    rst <= '0';
    wait for 1 ns;
    -- hi decides alone, lo absorbed later
    step('1', 4, '0', 0, '1', '1', 4, '1', '1');
    step('0', 0, '0', 0, '1', '0', 0, '0', '1');
    step('0', 0, '1', 2, '1', '0', 0, '0', '1');
    step('0', 0, '0', 0, '1', '0', 0, '1', '1');
    -- lo first, held; a zero hi answers it
    step('0', 0, '1', 2, '1', '0', 0, '1', '1');
    step('0', 0, '0', 0, '1', '0', 0, '1', '0');
    step('1', 0, '0', 0, '1', '1', 2, '1', '0');
    step('0', 0, '0', 0, '1', '0', 0, '1', '1');
    -- lo first; a non-zero hi beats it
    step('0', 0, '1', 2, '1', '0', 0, '1', '1');
    step('1', 8, '0', 0, '1', '1', 8, '1', '0');
    step('0', 0, '0', 0, '1', '0', 0, '1', '1');
    -- a zero hi waits for lo
    step('1', 0, '0', 0, '1', '0', 0, '1', '1');
    step('0', 0, '0', 0, '1', '0', 0, '0', '1');
    step('0', 0, '1', 1, '1', '1', 1, '0', '1');
    step('0', 0, '0', 0, '1', '0', 0, '1', '1');
    -- a stalled sink: the answer is kept while lo is absorbed
    step('1', 4, '0', 0, '0', '1', 4, '1', '1');
    step('0', 0, '1', 2, '0', '1', 4, '0', '1');
    step('0', 0, '0', 0, '0', '1', 4, '0', '0');
    step('0', 0, '0', 0, '1', '1', 4, '0', '0');
    step('0', 0, '0', 0, '1', '0', 0, '1', '1');
    -- two zeros answer zero
    step('1', 0, '1', 0, '1', '1', 0, '1', '1');
    -- back to back, one round a cycle
    step('1', 1, '1', 2, '1', '1', 1, '1', '1');
    step('1', 0, '1', 4, '1', '1', 4, '1', '1');
    step('0', 0, '0', 0, '1', '0', 0, '1', '1');
    -- a stalled answer that is lo's
    step('1', 0, '0', 0, '0', '0', 0, '1', '1');
    step('0', 0, '1', 8, '0', '1', 8, '0', '1');
    step('0', 0, '0', 0, '0', '1', 8, '0', '0');
    step('0', 0, '0', 0, '1', '1', 8, '0', '0');
    step('0', 0, '0', 0, '1', '0', 0, '1', '1');
    -- a zero hi and lo in the same cycle, the sink stalled: lo is held
    step('1', 0, '1', 5, '0', '1', 5, '1', '1');
    step('0', 0, '0', 0, '0', '1', 5, '0', '0');
    step('0', 0, '0', 0, '1', '1', 5, '0', '0');
    step('0', 0, '0', 0, '1', '0', 0, '1', '1');
    -- the next round's hi offered while the round is open: not taken, the
    -- stalled answer unchanged; taken the cycle after the round closes
    step('1', 4, '0', 0, '0', '1', 4, '1', '1');
    step('1', 8, '0', 0, '0', '1', 4, '0', '1');
    step('1', 8, '1', 2, '1', '1', 4, '0', '1');
    step('1', 8, '0', 0, '1', '1', 8, '1', '1');
    step('0', 0, '1', 0, '1', '0', 0, '0', '1');
    step('0', 0, '0', 0, '1', '0', 0, '1', '1');
    report "priority: " & integer'image(cycle) & " cycles as expected";
    std.env.finish;
  end process;
end architecture;
