-- arith_cmpi: a comparison, by the PREDICATE of arith.cmpi on raw wires -- no valid, no ready, nothing clocked.
-- One generic entity for every width; `clk` and `rst` are declared because
-- every instance is handed them, and nothing here reads them. Every data port
-- is a vector, a one-bit one included ("raw-vector-ports" in the RTL
-- configuration makes the exporter associate a one-bit wire with element 0).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity arith_cmpi is
  generic (
    PREDICATE : string;
    DATA_WIDTH : integer
  );
  port (
    clk : in std_logic;
    rst : in std_logic;
    lhs : in std_logic_vector(DATA_WIDTH - 1 downto 0);
    rhs : in std_logic_vector(DATA_WIDTH - 1 downto 0);
    result : out std_logic_vector(0 downto 0)
  );
end entity;

architecture arch of arith_cmpi is
begin
  p_eq : if PREDICATE = "eq" generate
    result(0) <= '1' when ((lhs) = (rhs)) else '0';
  end generate;
  p_ne : if PREDICATE = "ne" generate
    result(0) <= '1' when ((lhs) /= (rhs)) else '0';
  end generate;
  p_slt : if PREDICATE = "slt" generate
    result(0) <= '1' when (signed(lhs) < signed(rhs)) else '0';
  end generate;
  p_sle : if PREDICATE = "sle" generate
    result(0) <= '1' when (signed(lhs) <= signed(rhs)) else '0';
  end generate;
  p_sgt : if PREDICATE = "sgt" generate
    result(0) <= '1' when (signed(lhs) > signed(rhs)) else '0';
  end generate;
  p_sge : if PREDICATE = "sge" generate
    result(0) <= '1' when (signed(lhs) >= signed(rhs)) else '0';
  end generate;
  p_ult : if PREDICATE = "ult" generate
    result(0) <= '1' when (unsigned(lhs) < unsigned(rhs)) else '0';
  end generate;
  p_ule : if PREDICATE = "ule" generate
    result(0) <= '1' when (unsigned(lhs) <= unsigned(rhs)) else '0';
  end generate;
  p_ugt : if PREDICATE = "ugt" generate
    result(0) <= '1' when (unsigned(lhs) > unsigned(rhs)) else '0';
  end generate;
  p_uge : if PREDICATE = "uge" generate
    result(0) <= '1' when (unsigned(lhs) >= unsigned(rhs)) else '0';
  end generate;
end architecture;
