-- handshake_constant: a constant, sent once per control token; VALUE is its bit
-- string, most significant bit first.
-- One generic entity for every value and width, with the logic the unit generator
-- (tools/unit-generators/vhdl/generators/handshake/constant.py) writes for a
-- channel without extra signals. A channel with extra signals takes the
-- generator: its signal manager wraps this logic per parameter set.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity handshake_constant is
  generic (
    VALUE     : std_logic_vector;
    DATA_WIDTH : integer
  );
  port (
    clk        : in  std_logic;
    rst        : in  std_logic;
    -- input channel
    ctrl_valid : in  std_logic;
    ctrl_ready : out std_logic;
    -- output channel
    outs       : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    outs_valid : out std_logic;
    outs_ready : in  std_logic
  );
end entity;

architecture arch of handshake_constant is
begin
  assert VALUE'length = DATA_WIDTH
    report "handshake_constant: a value of " & integer'image(VALUE'length)
      & " bits for a width of " & integer'image(DATA_WIDTH)
    severity failure;

  outs       <= VALUE;
  outs_valid <= ctrl_valid;
  ctrl_ready <= outs_ready;
end architecture;
