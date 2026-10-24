-- The static first (data/vhdl/handshake/first.vhd, the file the vivado
-- configuration emits) under the generator's name and size, so that
-- first-tb.vhd drives both.
library ieee;
use ieee.std_logic_1164.all;
use work.types.all;

entity dut is
  port (
    clk, rst : in std_logic;
    ins : in data_array(2 downto 0)(1 downto 0);
    ins_valid : in std_logic_vector(2 downto 0); ins_ready : out std_logic_vector(2 downto 0);
    outs : out std_logic_vector(1 downto 0); outs_valid : out std_logic; outs_ready : in std_logic
  );
end entity;

architecture wrap of dut is
begin
  f : entity work.first
    generic map (SIZE => 3, DATA_TYPE => 2)
    port map (clk => clk, rst => rst, ins => ins, ins_valid => ins_valid,
              ins_ready => ins_ready, outs => outs, outs_valid => outs_valid,
              outs_ready => outs_ready);
end architecture;
