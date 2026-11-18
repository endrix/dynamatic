-- handshake_buffer_state: the slot of a state register's loop, the flip-flops
-- the state variable lives in (handshake_init_state.vhd draws the loop and
-- says when a unit is given this entity). Outside such a loop this is NOT a
-- buffer.
--
-- In that loop the one-slot buffer (oehb) loads at every clock: its input,
-- the init's output, is valid at every cycle, and its ins_ready, (not
-- outputValid) or outs_ready, is 1 at every cycle, since outputValid is 0
-- only in the first cycle after reset and outs_ready, the init's ins_ready,
-- is 1 from the next one. So the register has no enable. The valid stays, a
-- flip-flop that is 0 for that first cycle, and so does ins_ready, so that
-- every port carries what the oehb's carries in the loop.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity handshake_buffer_state is
  generic (
    DATA_TYPE : integer
  );
  port (
    clk, rst   : in  std_logic;
    -- input channel
    ins        : in  std_logic_vector(DATA_TYPE - 1 downto 0);
    ins_valid  : in  std_logic;
    ins_ready  : out std_logic;
    -- output channel
    outs       : out std_logic_vector(DATA_TYPE - 1 downto 0);
    outs_valid : out std_logic;
    outs_ready : in  std_logic
  );
end entity;

architecture arch of handshake_buffer_state is
  signal outputValid : std_logic;
begin
  process (clk) is
  begin
    if (rising_edge(clk)) then
      if (rst = '1') then
        outputValid <= '0';
        outs        <= (others => '0');
      else
        outputValid <= '1';
        outs        <= ins;
      end if;
    end if;
  end process;

  outs_valid <= outputValid;
  ins_ready  <= (not outputValid) or outs_ready;
end architecture;
