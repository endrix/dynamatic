-- handshake_cmpi: a comparison of lhs and rhs, both joined, by PREDICATE.
-- One generic entity for every predicate and width, with the logic the unit generator
-- (tools/unit-generators/vhdl/generators/handshake/cmpi.py) writes for a
-- channel without extra signals. A channel with extra signals takes the
-- generator: its signal manager wraps this logic per parameter set.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity handshake_cmpi is
  generic (
    PREDICATE : string;
    DATA_TYPE : integer
  );
  port (
    clk          : in  std_logic;
    rst          : in  std_logic;
    -- input channel lhs
    lhs          : in  std_logic_vector(DATA_TYPE - 1 downto 0);
    lhs_valid    : in  std_logic;
    lhs_ready    : out std_logic;
    -- input channel rhs
    rhs          : in  std_logic_vector(DATA_TYPE - 1 downto 0);
    rhs_valid    : in  std_logic;
    rhs_ready    : out std_logic;
    -- output channel result
    result       : out std_logic_vector(1 - 1 downto 0);
    result_valid : out std_logic;
    result_ready : in  std_logic
  );
end entity;

architecture arch of handshake_cmpi is
begin
  join_inputs : entity work.join(arch) generic map(2)
    port map(
      ins_valid(0) => lhs_valid,
      ins_valid(1) => rhs_valid,
      ins_ready(0) => lhs_ready,
      ins_ready(1) => rhs_ready,
      outs_valid   => result_valid,
      outs_ready   => result_ready
    );

  -- A predicate none of the branches below takes would leave the result
  -- undriven. The names are those of handshake.cmpi, in lower case.
  assert PREDICATE = "eq"
    or PREDICATE = "ne"
    or PREDICATE = "slt"
    or PREDICATE = "sle"
    or PREDICATE = "sgt"
    or PREDICATE = "sge"
    or PREDICATE = "ult"
    or PREDICATE = "ule"
    or PREDICATE = "ugt"
    or PREDICATE = "uge"
    report "handshake_cmpi: unknown predicate " & PREDICATE
    severity failure;

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
