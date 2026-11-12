-- handshake_control_merge_dataless: a merge of SIZE control channels that
-- also says which input it took: the arbiter (a merge without its slot), a
-- slot that cuts ready and holds the index, and a fork of the token to the
-- output and the index channels.
-- One generic entity for every size and index width, with the logic the unit
-- generator (tools/unit-generators/vhdl/generators/handshake/control_merge.py)
-- writes.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity handshake_control_merge_dataless is
  generic (
    SIZE       : integer;
    INDEX_TYPE : integer
  );
  port (
    clk, rst    : in  std_logic;
    -- input channels
    ins_valid   : in  std_logic_vector(SIZE - 1 downto 0);
    ins_ready   : out std_logic_vector(SIZE - 1 downto 0);
    -- output channel
    outs_valid  : out std_logic;
    outs_ready  : in  std_logic;
    -- index output channel
    index       : out std_logic_vector(INDEX_TYPE - 1 downto 0);
    index_valid : out std_logic;
    index_ready : in  std_logic
  );
end entity;

architecture arch of handshake_control_merge_dataless is
  signal merge_outs_valid              : std_logic;
  signal buf_ins_ready, buf_outs_valid : std_logic;
  signal fork_ins_ready                : std_logic;
  signal index_internal                : std_logic_vector(INDEX_TYPE - 1 downto 0);
begin
  -- the index of the first valid input
  process (ins_valid)
  begin
    index_internal <= (INDEX_TYPE - 1 downto 0 => '0');
    for i in 0 to (SIZE - 1) loop
      if (ins_valid(i) = '1') then
        index_internal <= std_logic_vector(to_unsigned(i, INDEX_TYPE));
        exit;
      end if;
    end loop;
  end process;

  merge_ins : entity work.handshake_merge_dataless generic map (SIZE, 0)
    port map(
      clk        => clk,
      rst        => rst,
      ins_valid  => ins_valid,
      ins_ready  => ins_ready,
      outs_valid => merge_outs_valid,
      outs_ready => buf_ins_ready
    );

  slot : entity work.tehb generic map (INDEX_TYPE)
    port map(
      clk        => clk,
      rst        => rst,
      ins        => index_internal,
      ins_valid  => merge_outs_valid,
      ins_ready  => buf_ins_ready,
      outs       => index,
      outs_valid => buf_outs_valid,
      outs_ready => fork_ins_ready
    );

  fork_valid : entity work.fork_dataless generic map (2)
    port map(
      clk           => clk,
      rst           => rst,
      ins_valid     => buf_outs_valid,
      ins_ready     => fork_ins_ready,
      outs_valid(0) => outs_valid,
      outs_valid(1) => index_valid,
      outs_ready(0) => outs_ready,
      outs_ready(1) => index_ready
    );
end architecture;
