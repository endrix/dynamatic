-- handshake_merge: a merge of SIZE data channels, the arbiter
-- (handshake_merge_notehb) and the slot behind it that cuts ready, a register
-- per data bit.
-- One generic entity for every size and width, with the logic the unit
-- generator (tools/unit-generators/vhdl/generators/handshake/merge.py) writes
-- for channels without extra signals. Channels with extra signals take the
-- generator: its signal manager wraps this logic per parameter set.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.types.all;

entity handshake_merge is
  generic (
    SIZE      : integer;
    DATA_TYPE : integer
  );
  port (
    clk, rst   : in  std_logic;
    -- input channels
    ins        : in  data_array(SIZE - 1 downto 0)(DATA_TYPE - 1 downto 0);
    ins_valid  : in  std_logic_vector(SIZE - 1 downto 0);
    ins_ready  : out std_logic_vector(SIZE - 1 downto 0);
    -- output channel
    outs       : out std_logic_vector(DATA_TYPE - 1 downto 0);
    outs_valid : out std_logic;
    outs_ready : in  std_logic
  );
end entity;

architecture arch of handshake_merge is
  signal slot_data  : std_logic_vector(DATA_TYPE - 1 downto 0);
  signal slot_valid : std_logic;
  signal slot_ready : std_logic;
begin
  merge_ins : entity work.handshake_merge_notehb generic map (SIZE, DATA_TYPE)
    port map(
      clk        => clk,
      rst        => rst,
      ins        => ins,
      ins_valid  => ins_valid,
      ins_ready  => ins_ready,
      outs       => slot_data,
      outs_valid => slot_valid,
      outs_ready => slot_ready
    );

  slot : entity work.tehb generic map (DATA_TYPE)
    port map(
      clk        => clk,
      rst        => rst,
      ins        => slot_data,
      ins_valid  => slot_valid,
      ins_ready  => slot_ready,
      outs       => outs,
      outs_valid => outs_valid,
      outs_ready => outs_ready
    );
end architecture;
