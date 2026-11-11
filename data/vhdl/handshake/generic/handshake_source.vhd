-- handshake_source: a control token at every cycle.
-- One generic entity for every source, with the logic the unit generator
-- (tools/unit-generators/vhdl/generators/handshake/source.py) writes for a
-- control without extra signals. A control with extra signals takes the
-- generator: its signal manager wraps this logic per parameter set.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity handshake_source is
  port (
    clk, rst   : in  std_logic;
    -- output channel
    outs_valid : out std_logic;
    outs_ready : in  std_logic
  );
end entity;

architecture arch of handshake_source is
begin
  outs_valid <= '1';
end architecture;
