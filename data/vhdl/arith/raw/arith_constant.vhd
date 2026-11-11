-- arith_constant: a constant; VALUE is its bit string, most significant bit first on raw wires -- no valid, no ready, nothing clocked.
-- One generic entity for every width; `clk` and `rst` are declared because
-- every instance is handed them, and nothing here reads them. Every data port
-- is a vector, a one-bit one included ("raw-vector-ports" in the RTL
-- configuration makes the exporter associate a one-bit wire with element 0).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity arith_constant is
  generic (
    VALUE : std_logic_vector;
    DATA_WIDTH : integer
  );
  port (
    clk : in std_logic;
    rst : in std_logic;
    outs : out std_logic_vector(DATA_WIDTH - 1 downto 0)
  );
end entity;

architecture arch of arith_constant is
begin
  assert VALUE'length = DATA_WIDTH
    report "arith_constant: a value of " & integer'image(VALUE'length)
      & " bits for a width of " & integer'image(DATA_WIDTH)
    severity failure;

  outs <= VALUE;
end architecture;
