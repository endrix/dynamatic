-- The static priority (data/vhdl/handshake/priority.vhd, the file the
-- characterization measures) under the generator's name and width, so that
-- priority-tb.vhd drives both.
library ieee;
use ieee.std_logic_1164.all;

entity dut is
  port (
    clk, rst : in std_logic;
    hi : in std_logic_vector(3 downto 0); hi_valid : in std_logic; hi_ready : out std_logic;
    lo : in std_logic_vector(3 downto 0); lo_valid : in std_logic; lo_ready : out std_logic;
    outs : out std_logic_vector(3 downto 0); outs_valid : out std_logic; outs_ready : in std_logic
  );
end entity;

architecture wrap of dut is
begin
  p : entity work.priority
    generic map (DATA_TYPE => 4)
    port map (clk => clk, rst => rst, hi => hi, hi_valid => hi_valid,
              hi_ready => hi_ready, lo => lo, lo_valid => lo_valid,
              lo_ready => lo_ready, outs => outs, outs_valid => outs_valid,
              outs_ready => outs_ready);
end architecture;
