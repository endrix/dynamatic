-- The static commit (data/vhdl/handshake/commit.vhd, the entity the vivado
-- configuration emits for the transfer's commit with data) under the
-- generator's name and width, so that commit-tb.vhd drives both.
library ieee;
use ieee.std_logic_1164.all;

entity dut is
  port (
    clk, rst : in std_logic;
    ins : in std_logic_vector(2 downto 0);
    ins_valid : in std_logic;
    ins_ready : out std_logic;
    outs : out std_logic_vector(2 downto 0);
    outs_valid : out std_logic;
    outs_ready : in std_logic;
    kill : out std_logic
  );
end entity;

architecture arch of dut is
begin
  c : entity work.commit
    generic map (DATA_TYPE => 3)
    port map (clk => clk, rst => rst, ins => ins, ins_valid => ins_valid,
              ins_ready => ins_ready, outs => outs, outs_valid => outs_valid,
              outs_ready => outs_ready, kill => kill);
end architecture;
