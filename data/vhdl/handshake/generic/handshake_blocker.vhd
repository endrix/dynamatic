-- handshake_blocker: the first input's data, passed when every input is
-- valid: a join of the SIZE inputs whose output carries input 0.
-- One generic entity for every size and width, with the logic the unit
-- generator (tools/unit-generators/vhdl/generators/handshake/blocker.py)
-- writes for channels without extra signals.

library ieee;
use ieee.std_logic_1164.all;
use work.types.all;

entity handshake_blocker is
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

architecture arch of handshake_blocker is
begin
  join_inputs : entity work.join generic map (SIZE)
    port map(
      ins_valid  => ins_valid,
      outs_ready => outs_ready,
      outs_valid => outs_valid,
      ins_ready  => ins_ready
    );

  outs <= ins(0);
end architecture;
