-- handshake_init: a one-slot buffer that holds a token at reset, whose value
-- is INITIAL_VALUE: a decimal string, the value's bits read as an unsigned
-- number of DATA_TYPE bits.
-- One generic entity for every width and value, with the logic the unit
-- generator (tools/unit-generators/vhdl/generators/handshake/init.py) writes
-- for a channel without extra signals. A channel with extra signals takes the
-- generator: its signal manager wraps this logic per parameter set.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity handshake_init is
  generic (
    INITIAL_VALUE : string;
    DATA_TYPE     : integer
  );
  port (
    clk, rst   : in  std_logic;
    -- input channel
    ins        : in  std_logic_vector(DATA_TYPE - 1 downto 0);
    ins_valid  : in  std_logic;
    ins_ready  : out std_logic;
    -- output channel
    outs       : out std_logic_vector(DATA_TYPE - 1 downto 0);
    outs_valid : out std_logic;
    outs_ready : in  std_logic
  );
end entity;

architecture arch of handshake_init is
  -- The decimal string as DATA_TYPE bits, of any width. The value has to fit
  -- the width: no prefix of its digits is above it, so four bits over the
  -- width hold every step of the accumulation, and a step that sets one of
  -- them is a value that does not fit.
  function reset_bits(text : string) return std_logic_vector is
    variable acc   : unsigned(DATA_TYPE + 3 downto 0) := (others => '0');
    variable digit : natural;
  begin
    assert text'length > 0
      report "handshake_init: INITIAL_VALUE is empty"
      severity failure;
    for i in text'range loop
      assert text(i) >= '0' and text(i) <= '9'
        report "handshake_init: INITIAL_VALUE """ & text & """ is not an unsigned decimal number"
        severity failure;
      digit := character'pos(text(i)) - character'pos('0');
      acc   := resize(acc * 10, acc'length) + digit;
      assert acc(DATA_TYPE + 3 downto DATA_TYPE) = 0
        report "handshake_init: INITIAL_VALUE " & text & " does not fit the width"
        severity failure;
    end loop;
    return std_logic_vector(acc(DATA_TYPE - 1 downto 0));
  end function;

  constant RESET_VALUE : std_logic_vector(DATA_TYPE - 1 downto 0) := reset_bits(INITIAL_VALUE);

  signal regEnable, regNotFull : std_logic;
  signal dataReg               : std_logic_vector(DATA_TYPE - 1 downto 0);
begin
  regEnable <= regNotFull and ins_valid and not outs_ready;

  control : entity work.handshake_init_dataless
    port map(
      clk        => clk,
      rst        => rst,
      ins_valid  => ins_valid,
      ins_ready  => regNotFull,
      outs_valid => outs_valid,
      outs_ready => outs_ready
    );

  process (clk) is
  begin
    if (rising_edge(clk)) then
      if (rst = '1') then
        dataReg <= RESET_VALUE;
      elsif (regEnable) then
        dataReg <= ins;
      end if;
    end if;
  end process;

  process (regNotFull, dataReg, ins) is
  begin
    if (regNotFull) then
      outs <= ins;
    else
      outs <= dataReg;
    end if;
  end process;

  ins_ready <= regNotFull;
end architecture;
