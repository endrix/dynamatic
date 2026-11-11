-- arith_extui: a zero extension on raw wires -- no valid, no ready, nothing clocked.
-- One generic entity for every width; `clk` and `rst` are declared because
-- every instance is handed them, and nothing here reads them. Every data port
-- is a vector, a one-bit one included ("raw-vector-ports" in the RTL
-- configuration makes the exporter associate a one-bit wire with element 0).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity arith_extui is
  generic (
    INPUT_WIDTH : integer;
    OUTPUT_WIDTH : integer
  );
  port (
    clk : in std_logic;
    rst : in std_logic;
    ins : in std_logic_vector(INPUT_WIDTH - 1 downto 0);
    outs : out std_logic_vector(OUTPUT_WIDTH - 1 downto 0)
  );
end entity;

architecture arch of arith_extui is
begin
  outs(OUTPUT_WIDTH - 1 downto INPUT_WIDTH) <= (others => '0');
  outs(INPUT_WIDTH - 1 downto 0) <= ins;
end architecture;
