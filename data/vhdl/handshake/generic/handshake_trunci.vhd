-- handshake_trunci: the low OUTPUT_TYPE bits of the input.
-- One generic entity for every pair of widths, with the logic the unit generator
-- (tools/unit-generators/vhdl/generators/handshake/trunci.py) writes for a
-- channel without extra signals. A channel with extra signals takes the
-- generator: its signal manager wraps this logic per parameter set.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity handshake_trunci is
  generic (
    INPUT_TYPE  : integer;
    OUTPUT_TYPE : integer
  );
  port (
    clk        : in  std_logic;
    rst        : in  std_logic;
    -- input channel
    ins        : in  std_logic_vector(INPUT_TYPE - 1 downto 0);
    ins_valid  : in  std_logic;
    ins_ready  : out std_logic;
    -- output channel
    outs       : out std_logic_vector(OUTPUT_TYPE - 1 downto 0);
    outs_valid : out std_logic;
    outs_ready : in  std_logic
  );
end entity;

architecture arch of handshake_trunci is
begin
  outs <= ins(OUTPUT_TYPE - 1 downto 0);

  -- combinatorial unit forwards handshaking
  outs_valid <= ins_valid;
  ins_ready  <= outs_ready;
end architecture;
