-- handshake_control_merge: a merge of SIZE data channels that also says
-- which input it took: the arbiter (a merge without its slot), a slot that
-- cuts ready and holds the data and the index, and a fork of the token to
-- the output and the index channels.
-- One generic entity for every size and width, with the logic the unit
-- generator (tools/unit-generators/vhdl/generators/handshake/control_merge.py)
-- writes for channels without extra signals. Channels with extra signals
-- take the generator: its signal manager wraps this logic per parameter set.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.types.all;

entity handshake_control_merge is
  generic (
    SIZE       : integer;
    DATA_TYPE  : integer;
    INDEX_TYPE : integer
  );
  port (
    clk, rst    : in  std_logic;
    -- input channels
    ins         : in  data_array(SIZE - 1 downto 0)(DATA_TYPE - 1 downto 0);
    ins_valid   : in  std_logic_vector(SIZE - 1 downto 0);
    ins_ready   : out std_logic_vector(SIZE - 1 downto 0);
    -- data output channel
    outs        : out std_logic_vector(DATA_TYPE - 1 downto 0);
    outs_valid  : out std_logic;
    outs_ready  : in  std_logic;
    -- index output channel
    index       : out std_logic_vector(INDEX_TYPE - 1 downto 0);
    index_valid : out std_logic;
    index_ready : in  std_logic
  );
end entity;

architecture arch of handshake_control_merge is
  signal merge_outs                    : std_logic_vector(DATA_TYPE - 1 downto 0);
  signal merge_outs_valid              : std_logic;
  signal buf_ins_ready, buf_outs_valid : std_logic;
  signal fork_ins_ready                : std_logic;
  signal index_internal                : std_logic_vector(INDEX_TYPE - 1 downto 0);
  -- the slot holds the data above the index
  signal buf_ins, buf_outs             : std_logic_vector(DATA_TYPE + INDEX_TYPE - 1 downto 0);
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

  merge_ins : entity work.handshake_merge generic map (SIZE, DATA_TYPE, 0)
    port map(
      clk        => clk,
      rst        => rst,
      ins        => ins,
      ins_valid  => ins_valid,
      ins_ready  => ins_ready,
      outs       => merge_outs,
      outs_valid => merge_outs_valid,
      outs_ready => buf_ins_ready
    );

  buf_ins <= merge_outs & index_internal;
  slot : entity work.tehb generic map (DATA_TYPE + INDEX_TYPE)
    port map(
      clk        => clk,
      rst        => rst,
      ins        => buf_ins,
      ins_valid  => merge_outs_valid,
      ins_ready  => buf_ins_ready,
      outs       => buf_outs,
      outs_valid => buf_outs_valid,
      outs_ready => fork_ins_ready
    );
  index <= buf_outs(INDEX_TYPE - 1 downto 0);
  outs  <= buf_outs(DATA_TYPE + INDEX_TYPE - 1 downto INDEX_TYPE);

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
