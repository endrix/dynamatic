-- handshake_shrsi: an arithmetic right shift of lhs by rhs, both joined.
-- One generic entity for every width, with the logic the unit generator
-- (tools/unit-generators/vhdl/generators/handshake/shrsi.py) writes for a
-- channel without extra signals. A channel with extra signals takes the
-- generator: its signal manager wraps this logic per parameter set.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity handshake_shrsi is
  generic (
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
    result       : out std_logic_vector(DATA_TYPE - 1 downto 0);
    result_valid : out std_logic;
    result_ready : in  std_logic
  );
end entity;

architecture arch of handshake_shrsi is
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

  -- The amount is the low DATA_TYPE - 1 bits of rhs, as the generator reads it.
  result <= std_logic_vector(shift_right(signed(lhs), to_integer(signed('0' & rhs(DATA_TYPE - 2 downto 0)))));
end architecture;
