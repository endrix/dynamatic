-- The static stand_in (data/vhdl/handshake/stand_in.vhd, the entity the vivado
-- configuration emits) with two kills, under the generator's name and width,
-- so that stand-in2-tb.vhd drives both.
library ieee;
use ieee.std_logic_1164.all;

entity dut is
  port (
    clk, rst   : in  std_logic;
    ins        : in  std_logic_vector(1 downto 0);
    ins_valid  : in  std_logic;
    ins_ready  : out std_logic;
    kill       : in  std_logic_vector(1 downto 0);
    outs       : out std_logic_vector(1 downto 0);
    outs_valid : out std_logic;
    outs_ready : in  std_logic
  );
end entity;

architecture arch of dut is
begin
  s : entity work.stand_in generic map (SIZE => 2, DATA_TYPE => 2)
    port map (clk => clk, rst => rst, ins => ins, ins_valid => ins_valid,
              ins_ready => ins_ready, kill => kill, outs => outs,
              outs_valid => outs_valid, outs_ready => outs_ready);
end architecture;
