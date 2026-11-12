-- handshake_mux: of SIZE data channels, the one the index selects. An input
-- is taken with the index; an input that is not valid is ready. Behind the
-- select sits a slot that cuts ready, a register per data bit, unless TEHB
-- is 0: a consumer that cuts ready itself needs no second one, and the
-- select then drives the output channel, combinational from its ready to the
-- inputs'.
-- One generic entity for every size and width, with the logic the unit
-- generator (tools/unit-generators/vhdl/generators/handshake/mux.py) writes
-- for channels without extra signals. Channels with extra signals take the
-- generator: its signal manager wraps this logic per parameter set.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.types.all;

entity handshake_mux is
  generic (
    SIZE        : integer;
    DATA_TYPE   : integer;
    SELECT_TYPE : integer;
    TEHB        : integer
  );
  port (
    clk, rst    : in  std_logic;
    -- data input channels
    ins         : in  data_array(SIZE - 1 downto 0)(DATA_TYPE - 1 downto 0);
    ins_valid   : in  std_logic_vector(SIZE - 1 downto 0);
    ins_ready   : out std_logic_vector(SIZE - 1 downto 0);
    -- index input channel
    index       : in  std_logic_vector(SELECT_TYPE - 1 downto 0);
    index_valid : in  std_logic;
    index_ready : out std_logic;
    -- output channel
    outs        : out std_logic_vector(DATA_TYPE - 1 downto 0);
    outs_valid  : out std_logic;
    outs_ready  : in  std_logic
  );
end entity;

architecture arch of handshake_mux is
  -- the select's output channel
  signal sel_data             : std_logic_vector(DATA_TYPE - 1 downto 0);
  signal sel_valid, sel_ready : std_logic;
begin
  process (ins, ins_valid, outs_ready, index, index_valid, sel_ready)
    variable selectedData                   : std_logic_vector(DATA_TYPE - 1 downto 0);
    variable selectedData_valid, indexEqual : std_logic;
  begin
    selectedData       := ins(0);
    selectedData_valid := '0';

    for i in SIZE - 1 downto 0 loop
      if unsigned(index) = to_unsigned(i, index'length) then
        indexEqual := '1';
      else
        indexEqual := '0';
      end if;
      if indexEqual and index_valid and ins_valid(i) then
        selectedData       := ins(i);
        selectedData_valid := '1';
      end if;
      ins_ready(i) <= (indexEqual and index_valid and ins_valid(i) and sel_ready) or (not ins_valid(i));
    end loop;

    index_ready <= (not index_valid) or (selectedData_valid and sel_ready);
    sel_data    <= selectedData;
    sel_valid   <= selectedData_valid;
  end process;

  gen_slot : if TEHB /= 0 generate
    slot : entity work.tehb generic map (DATA_TYPE)
      port map(
        clk        => clk,
        rst        => rst,
        ins        => sel_data,
        ins_valid  => sel_valid,
        ins_ready  => sel_ready,
        outs       => outs,
        outs_valid => outs_valid,
        outs_ready => outs_ready
      );
  end generate;

  -- no slot: the select drives the output channel and reads its ready
  gen_bare : if TEHB = 0 generate
    outs       <= sel_data;
    outs_valid <= sel_valid;
    sel_ready  <= outs_ready;
  end generate;
end architecture;
