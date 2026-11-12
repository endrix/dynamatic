-- handshake_bundle: a control and a bare data signal joined into a channel.
-- Pure wiring: `clk` and `rst` are declared because every instance is handed
-- them, and nothing here reads them.
-- One generic entity for every width, with the wiring the unit generator
-- (tools/unit-generators/vhdl/generators/handshake/bundle.py) writes for a
-- channel without extra signals. A channel with extra signals has a port for
-- each: handshake_bundle_space where it is the queue's `space`, the
-- generator otherwise.
-- The bare ports are vectors at every width, a one-bit one included
-- ("raw-vector-ports" in the RTL configuration makes the exporter associate
-- a one-bit wire with element 0).

library ieee;
use ieee.std_logic_1164.all;

entity handshake_bundle is
  generic (
    DATA_WIDTH : integer
  );
  port (
    clk, rst   : in  std_logic;
    -- the control and the data, bare
    ctrl_valid : in  std_logic;
    ctrl_ready : out std_logic;
    data       : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
    -- output channel
    outs       : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    outs_valid : out std_logic;
    outs_ready : in  std_logic
  );
end entity;

architecture arch of handshake_bundle is
begin
  outs_valid <= ctrl_valid;
  ctrl_ready <= outs_ready;
  outs       <= data;
end architecture;
