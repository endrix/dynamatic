-- handshake_bundle_control: a bare valid made a control, whose ready is
-- handed back bare. Pure wiring: `clk` and `rst` are declared because every
-- instance is handed them, and nothing here reads them.
-- One entity, the one the unit generator
-- (tools/unit-generators/vhdl/generators/handshake/bundle.py) writes for a
-- control without extra signals.

library ieee;
use ieee.std_logic_1164.all;

entity handshake_bundle_control is
  port (
    clk, rst   : in  std_logic;
    -- valid is supplied as a bare signal
    valid      : in  std_logic;
    -- output control
    ctrl_valid : out std_logic;
    ctrl_ready : in  std_logic;
    -- ready is handed back as a bare signal
    ready      : out std_logic
  );
end entity;

architecture arch of handshake_bundle_control is
begin
  ctrl_valid <= valid;
  ready      <= ctrl_ready;
end architecture;
