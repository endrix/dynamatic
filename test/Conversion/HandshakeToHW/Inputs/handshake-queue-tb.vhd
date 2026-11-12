-- The generic queue (data/vhdl/handshake/generic/handshake_queue.vhd) alone,
-- used by handshake-queue-tokens-ghdl.mlir: what it holds after reset, read
-- out token by token, and then a token written and read back.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb is
  generic (
    W      : positive := 8;
    SLOTS  : positive := 4;
    TOKENS : string   := "none"
  );
end entity;

architecture sim of tb is
  signal clk                  : std_logic := '0';
  signal rst                  : std_logic := '1';
  signal d_in, d_out          : std_logic_vector(W - 1 downto 0) := (others => '0');
  signal in_valid, in_ready   : std_logic := '0';
  signal out_valid, out_ready : std_logic := '0';
  signal space, size          : std_logic_vector(3 downto 0);

  procedure tick(signal c : out std_logic) is
  begin
    wait for 4 ns; c <= '1'; wait for 5 ns; c <= '0'; wait for 1 ns;
  end procedure;
begin
  q : entity work.handshake_queue(arch) generic map(SLOTS, W, 4, 4, TOKENS)
    port map(clk => clk, rst => rst, ins => d_in, ins_valid => in_valid, ins_ready => in_ready,
             ins_space => space, outs => d_out, outs_valid => out_valid, outs_ready => out_ready,
             outs_size => size);

  process
  begin
    tick(clk); tick(clk);
    rst <= '0';
    wait for 1 ns;
    report "after reset: size " & integer'image(to_integer(unsigned(size)))
           & " space " & integer'image(to_integer(unsigned(space)));
    out_ready <= '1';
    wait for 1 ns;
    while out_valid = '1' loop
      report "token " & integer'image(to_integer(unsigned(d_out)));
      tick(clk);
      wait for 1 ns;
    end loop;
    report "empty: size " & integer'image(to_integer(unsigned(size)))
           & " space " & integer'image(to_integer(unsigned(space)));
    out_ready <= '0';
    in_valid  <= '1';
    d_in      <= std_logic_vector(to_unsigned(1, W));
    tick(clk);
    in_valid <= '0';
    wait for 1 ns;
    report "written: token " & integer'image(to_integer(unsigned(d_out)))
           & " size " & integer'image(to_integer(unsigned(size)));
    wait;
  end process;
end architecture;
