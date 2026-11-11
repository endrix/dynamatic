-- arith_shrui: a logical right shift on raw wires -- no valid, no ready, nothing clocked.
-- One generic entity for every width; `clk` and `rst` are declared because
-- every instance is handed them, and nothing here reads them. Every data port
-- is a vector, a one-bit one included ("raw-vector-ports" in the RTL
-- configuration makes the exporter associate a one-bit wire with element 0).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity arith_shrui is
  generic (
    DATA_WIDTH : integer
  );
  port (
    clk : in std_logic;
    rst : in std_logic;
    lhs : in std_logic_vector(DATA_WIDTH - 1 downto 0);
    rhs : in std_logic_vector(DATA_WIDTH - 1 downto 0);
    result : out std_logic_vector(DATA_WIDTH - 1 downto 0)
  );
end entity;

architecture arch of arith_shrui is
  signal amount   : natural;
  signal overflow : std_logic;
begin
  -- `to_integer` takes at most 31 bits; the amount is read from the low bits
  -- that fit, and a set bit above them is a shift by at least the width.
  narrow : if DATA_WIDTH <= 31 generate
    amount   <= to_integer(unsigned(rhs));
    overflow <= '0';
  end generate;
  wide : if DATA_WIDTH > 31 generate
    amount   <= to_integer(unsigned(rhs(30 downto 0)));
    overflow <= '0' when unsigned(rhs(DATA_WIDTH - 1 downto 31)) = 0 else '1';
  end generate;
  result <= std_logic_vector(shift_right(unsigned(lhs), amount)) when overflow = '0' else (others => '0');
end architecture;
