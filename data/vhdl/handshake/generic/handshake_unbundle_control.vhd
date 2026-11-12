-- handshake_unbundle_control: a control split into a bare valid, with its
-- ready supplied bare by the consumer. Pure wiring: `clk` and `rst` are
-- declared because every instance is handed them, and nothing here reads
-- them.
-- One entity, the one the unit generator
-- (tools/unit-generators/vhdl/generators/handshake/unbundle.py) writes for a
-- control without extra signals.

library ieee;
use ieee.std_logic_1164.all;

entity handshake_unbundle_control is
  port (
    clk, rst  : in  std_logic;
    -- input control
    ins_valid : in  std_logic;
    ins_ready : out std_logic;
    -- ready is supplied by the consumer as a bare signal
    ready     : in  std_logic;
    -- valid is produced as a bare signal
    valid     : out std_logic
  );
end entity;

architecture arch of handshake_unbundle_control is
begin
  valid     <= ins_valid;
  ins_ready <= ready;
end architecture;
