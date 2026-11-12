-- handshake_join: the join of SIZE control channels. The output is valid when
-- every input is; an input is ready when every other input is valid and the
-- output is ready.
-- One generic entity for every size, with the logic the unit generator
-- (tools/unit-generators/vhdl/generators/handshake/top_join.py) writes for
-- channels without extra signals: the support join, with a clock and a reset
-- it does not use.

library ieee;
use ieee.std_logic_1164.all;

entity handshake_join is
  generic (
    SIZE : integer
  );
  port (
    clk, rst   : in  std_logic;
    -- input channels
    ins_valid  : in  std_logic_vector(SIZE - 1 downto 0);
    ins_ready  : out std_logic_vector(SIZE - 1 downto 0);
    -- output channel
    outs_valid : out std_logic;
    outs_ready : in  std_logic
  );
end entity;

architecture arch of handshake_join is
begin
  join_inputs : entity work.join generic map (SIZE)
    port map(
      ins_valid  => ins_valid,
      outs_ready => outs_ready,
      outs_valid => outs_valid,
      ins_ready  => ins_ready
    );
end architecture;
