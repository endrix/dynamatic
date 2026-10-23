-- The static load that drops on a kill (data/vhdl/handshake/load_kill_drop.vhd,
-- the file the vivado configuration emits) under the generator's name and
-- widths, so that load-kill-drop-tb.vhd drives both.
library ieee;
use ieee.std_logic_1164.all;

entity dut is
  port (
    clk, rst : in std_logic;
    addrIn : in std_logic_vector(1 downto 0); addrIn_valid : in std_logic; addrIn_ready : out std_logic;
    addrOut : out std_logic_vector(1 downto 0); addrOut_valid : out std_logic; addrOut_ready : in std_logic;
    dataFromMem : in std_logic_vector(7 downto 0); dataFromMem_valid : in std_logic; dataFromMem_ready : out std_logic;
    dataOut : out std_logic_vector(7 downto 0); dataOut_valid : out std_logic; dataOut_ready : in std_logic;
    kill : in std_logic
  );
end entity;

architecture wrap of dut is
begin
  l : entity work.load_kill_drop
    generic map (DATA_TYPE => 8, ADDR_TYPE => 2)
    port map (clk => clk, rst => rst, addrIn => addrIn, addrIn_valid => addrIn_valid,
              addrIn_ready => addrIn_ready, addrOut => addrOut, addrOut_valid => addrOut_valid,
              addrOut_ready => addrOut_ready, dataFromMem => dataFromMem,
              dataFromMem_valid => dataFromMem_valid, dataFromMem_ready => dataFromMem_ready,
              dataOut => dataOut, dataOut_valid => dataOut_valid, dataOut_ready => dataOut_ready,
              kill => kill);
end architecture;
