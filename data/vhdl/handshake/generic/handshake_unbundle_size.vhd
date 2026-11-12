-- handshake_unbundle_size: a channel that carries `size` downstream, the
-- occupancy of the queue it leaves, split into its control and bare data and
-- size signals, so that a circuit can read them without consuming the
-- channel. Pure wiring: `clk` and `rst` are declared because every instance
-- is handed them, and nothing here reads them.
-- One generic entity for every width, with the wiring the unit generator
-- (tools/unit-generators/vhdl/generators/handshake/unbundle.py) writes for a
-- channel whose only extra signal is a downstream `size`.
-- The bare ports are vectors at every width, a one-bit one included
-- ("raw-vector-ports" in the RTL configuration makes the exporter associate
-- a one-bit wire with element 0).

library ieee;
use ieee.std_logic_1164.all;

entity handshake_unbundle_size is
  generic (
    DATA_WIDTH : integer;
    SIZE_WIDTH : integer
  );
  port (
    clk, rst   : in  std_logic;
    -- input channel
    ins        : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
    ins_valid  : in  std_logic;
    ins_ready  : out std_logic;
    ins_size   : in  std_logic_vector(SIZE_WIDTH - 1 downto 0);
    -- the control, the data and the size, bare
    ctrl_valid : out std_logic;
    ctrl_ready : in  std_logic;
    data       : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    size       : out std_logic_vector(SIZE_WIDTH - 1 downto 0)
  );
end entity;

architecture arch of handshake_unbundle_size is
begin
  ctrl_valid <= ins_valid;
  ins_ready  <= ctrl_ready;
  data       <= ins;
  size       <= ins_size;
end architecture;
