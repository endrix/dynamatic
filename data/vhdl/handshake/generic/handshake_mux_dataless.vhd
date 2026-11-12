-- handshake_mux_dataless: of SIZE control channels, the one the index
-- selects. An input is taken with the index; an input that is not valid is
-- ready. Behind the select sits a slot that cuts ready, unless TEHB is 0: a
-- consumer that cuts ready itself needs no second one, and the select then
-- drives the output channel, combinational from its ready to the inputs'.
-- One generic entity for every size, with the logic the unit generator
-- (tools/unit-generators/vhdl/generators/handshake/mux.py) writes.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity handshake_mux_dataless is
  generic (
    SIZE        : integer;
    SELECT_TYPE : integer;
    TEHB        : integer
  );
  port (
    clk, rst    : in  std_logic;
    -- data input channels
    ins_valid   : in  std_logic_vector(SIZE - 1 downto 0);
    ins_ready   : out std_logic_vector(SIZE - 1 downto 0);
    -- index input channel
    index       : in  std_logic_vector(SELECT_TYPE - 1 downto 0);
    index_valid : in  std_logic;
    index_ready : out std_logic;
    -- output channel
    outs_valid  : out std_logic;
    outs_ready  : in  std_logic
  );
end entity;

architecture arch of handshake_mux_dataless is
  -- the select's output channel
  signal sel_valid, sel_ready : std_logic;
begin
  process (ins_valid, outs_ready, index, index_valid, sel_ready)
    variable selectedData_valid, indexEqual : std_logic;
  begin
    selectedData_valid := '0';

    for i in SIZE - 1 downto 0 loop
      if unsigned(index) = to_unsigned(i, index'length) then
        indexEqual := '1';
      else
        indexEqual := '0';
      end if;
      if indexEqual and index_valid and ins_valid(i) then
        selectedData_valid := '1';
      end if;
      ins_ready(i) <= (indexEqual and index_valid and ins_valid(i) and sel_ready) or (not ins_valid(i));
    end loop;

    index_ready <= (not index_valid) or (selectedData_valid and sel_ready);
    sel_valid   <= selectedData_valid;
  end process;

  gen_slot : if TEHB /= 0 generate
    slot : entity work.tehb_dataless
      port map(
        clk        => clk,
        rst        => rst,
        ins_valid  => sel_valid,
        ins_ready  => sel_ready,
        outs_valid => outs_valid,
        outs_ready => outs_ready
      );
  end generate;

  -- no slot: the select drives the output channel and reads its ready
  gen_bare : if TEHB = 0 generate
    outs_valid <= sel_valid;
    sel_ready  <= outs_ready;
  end generate;
end architecture;
