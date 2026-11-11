-- arith_select: a two-way selection on raw wires -- no valid, no ready, nothing clocked.
-- One generic entity for every width; `clk` and `rst` are declared because
-- every instance is handed them, and nothing here reads them. Every data port
-- is a vector, a one-bit one included ("raw-vector-ports" in the RTL
-- configuration makes the exporter associate a one-bit wire with element 0).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity arith_select is
  generic (
    DATA_WIDTH : integer
  );
  port (
    clk : in std_logic;
    rst : in std_logic;
    condition : in std_logic_vector(0 downto 0);
    true_value : in std_logic_vector(DATA_WIDTH - 1 downto 0);
    false_value : in std_logic_vector(DATA_WIDTH - 1 downto 0);
    result : out std_logic_vector(DATA_WIDTH - 1 downto 0)
  );
end entity;

architecture arch of arith_select is
begin
  result <= true_value when condition(0) = '1' else false_value;
end architecture;
