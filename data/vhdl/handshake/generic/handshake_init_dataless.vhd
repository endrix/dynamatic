-- handshake_init_dataless: a one-slot buffer that holds a token at reset.
-- The init of a control, and the handshake of handshake_init. The logic the
-- unit generator (tools/unit-generators/vhdl/generators/handshake/init.py)
-- writes for a control without extra signals.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity handshake_init_dataless is
  port (
    clk, rst   : in  std_logic;
    -- input channel
    ins_valid  : in  std_logic;
    ins_ready  : out std_logic;
    -- output channel
    outs_valid : out std_logic;
    outs_ready : in  std_logic
  );
end entity;

architecture arch of handshake_init_dataless is
  signal fullReg, outputValid : std_logic;
begin
  outputValid <= ins_valid or fullReg;

  process (clk) is
  begin
    if (rising_edge(clk)) then
      if (rst = '1') then
        fullReg <= '1';
      else
        fullReg <= outputValid and not outs_ready;
      end if;
    end if;
  end process;

  ins_ready  <= not fullReg;
  outs_valid <= outputValid;
end architecture;
