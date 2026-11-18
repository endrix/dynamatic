-- handshake_init_state: the init of a state register's loop.
--
-- A state variable of an actor is a token that never leaves a closed loop:
--
--   next value -> bundle -> init -> one slot (ONE_SLOT_BREAK_DV) -> unbundle
--                   ^                                                  |
--                   +------------------- control ----------------------+
--
-- The unbundle's control is read by the bundle and by nothing else, so no
-- unit outside the loop sees or drives its valids and readies; the next
-- value and the value read are bare wires. lower-handshake-to-hw gives the
-- init and the slot of such a loop this unit and handshake_buffer_state,
-- and only of such a loop: outside one, this is NOT an init.
--
-- In that loop handshake_init holds its token for one cycle, the first
-- after reset, and is a wire from then on: its output's ready is the slot's
-- ins_ready, (not outputValid) or outs_ready, and that outs_ready is the
-- init's own ins_ready, so the slot always takes what the init offers, the
-- init never fills again, and its data register never loads. What is left
-- is a flag for that first cycle and the reset value put out in it. Every
-- port carries, at every cycle, what handshake_init's carries in the loop
-- (test/Conversion/HandshakeToHW/state-loop-ghdl.mlir holds the two loops
-- together).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity handshake_init_state is
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

architecture arch of handshake_init_state is
  -- The decimal string as DATA_TYPE bits, as handshake_init reads it.
  function reset_bits(text : string) return std_logic_vector is
    variable acc   : unsigned(DATA_TYPE + 3 downto 0) := (others => '0');
    variable digit : natural;
  begin
    assert text'length > 0
      report "handshake_init_state: INITIAL_VALUE is empty"
      severity failure;
    for i in text'range loop
      assert text(i) >= '0' and text(i) <= '9'
        report "handshake_init_state: INITIAL_VALUE """ & text & """ is not an unsigned decimal number"
        severity failure;
      digit := character'pos(text(i)) - character'pos('0');
      acc   := resize(acc * 10, acc'length) + digit;
      assert acc(DATA_TYPE + 3 downto DATA_TYPE) = 0
        report "handshake_init_state: INITIAL_VALUE " & text & " does not fit the width"
        severity failure;
    end loop;
    return std_logic_vector(acc(DATA_TYPE - 1 downto 0));
  end function;

  constant RESET_VALUE : std_logic_vector(DATA_TYPE - 1 downto 0) := reset_bits(INITIAL_VALUE);

  -- the first cycle after reset
  signal first : std_logic;
begin
  process (clk) is
  begin
    if (rising_edge(clk)) then
      if (rst = '1') then
        first <= '1';
      else
        first <= '0';
      end if;
    end if;
  end process;

  outs       <= RESET_VALUE when first = '1' else ins;
  outs_valid <= ins_valid or first;
  ins_ready  <= not first;
end architecture;
