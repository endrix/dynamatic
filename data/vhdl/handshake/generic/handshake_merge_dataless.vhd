-- handshake_merge_dataless: a merge of SIZE control channels, the arbiter
-- (handshake_merge_notehb_dataless) and the slot behind it that cuts ready.
-- One generic entity for every size, with the logic the unit generator
-- (tools/unit-generators/vhdl/generators/handshake/merge.py) writes.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity handshake_merge_dataless is
  generic (
    SIZE : integer
  );
  port (
    clk, rst   : in  std_logic;
    -- input channels
    ins_valid  : in  std_logic_vector(SIZE - 1 downto 0);
    ins_ready  : out std_logic_vector(SIZE - 1 downto 0);
    -- output channel
    outs_valid : out std_logic;
    outs_ready : in  std_logic
  );
end entity;

architecture arch of handshake_merge_dataless is
  signal slot_valid : std_logic;
  signal slot_ready : std_logic;
begin
  merge_ins : entity work.handshake_merge_notehb_dataless generic map (SIZE)
    port map(
      clk        => clk,
      rst        => rst,
      ins_valid  => ins_valid,
      ins_ready  => ins_ready,
      outs_valid => slot_valid,
      outs_ready => slot_ready
    );

  slot : entity work.tehb_dataless
    port map(
      clk        => clk,
      rst        => rst,
      ins_valid  => slot_valid,
      ins_ready  => slot_ready,
      outs_valid => outs_valid,
      outs_ready => outs_ready
    );
end architecture;
