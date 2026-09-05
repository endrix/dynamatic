library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.types.all;

-- A first-wins merge with full consumption.
--
-- `merge` forwards one input and consumes ONE token per firing. `first`
-- consumes exactly one token on EVERY input per round and emits one, and the
-- payload it emits is the first non-zero one to ARRIVE. Payload 0 is reserved
-- for "nothing selected", so a winner is distinguishable from a loser and an
-- all-zero round emits zero. Simultaneous arrivals are resolved by index
-- order, which is free to choose because the operands are incomparable.
--
-- Emitting early and consuming everything are opposite deadlines. The `seen`
-- mask reconciles them: an input that has given its token is not ready again
-- until the round closes, so the round boundary is local state and no
-- round-start signal is needed anywhere.
--
-- `ins_ready` is a function of REGISTERS ONLY -- nothing here reads outs_ready
-- or any ins_valid -- so this unit cannot close a valid -> ready -> valid ring
-- the way a lazy fork can. Valid and data are combinational: latency zero, one
-- round per cycle when every input is valid and the sink is ready.
entity first is
  generic (
    SIZE      : integer;
    DATA_TYPE : integer
  );
  port (
    clk : in std_logic;
    rst : in std_logic;
    -- input channels
    ins       : in  data_array(SIZE - 1 downto 0)(DATA_TYPE - 1 downto 0);
    ins_valid : in  std_logic_vector(SIZE - 1 downto 0);
    ins_ready : out std_logic_vector(SIZE - 1 downto 0);
    -- output channel
    outs       : out std_logic_vector(DATA_TYPE - 1 downto 0);
    outs_valid : out std_logic;
    outs_ready : in  std_logic
  );
end entity;

architecture arch of first is
  constant ALL_TAKEN : std_logic_vector(SIZE - 1 downto 0) := (others => '1');

  -- Round state.
  signal seen    : std_logic_vector(SIZE - 1 downto 0);
  signal winner  : std_logic_vector(DATA_TYPE - 1 downto 0);
  signal has_win : std_logic;
  signal emitted : std_logic;

  signal taken, seen_next : std_logic_vector(SIZE - 1 downto 0);
  signal cand             : std_logic_vector(DATA_TYPE - 1 downto 0);
  signal cand_v           : std_logic;
  signal closing          : std_logic;
  signal valid_i          : std_logic;
  signal fire, done       : std_logic;
begin
  ins_ready <= not seen;
  taken     <= ins_valid and not seen;
  seen_next <= seen or taken;

  -- The first non-zero payload among the tokens taken THIS cycle, by index
  -- order.
  process (taken, ins)
    variable v : std_logic;
    variable d : std_logic_vector(DATA_TYPE - 1 downto 0);
  begin
    v := '0';
    d := (others => '0');
    for i in 0 to SIZE - 1 loop
      if v = '0' and taken(i) = '1' and unsigned(ins(i)) /= 0 then
        v := '1';
        d := ins(i);
      end if;
    end loop;
    cand_v <= v;
    cand   <= d;
  end process;

  closing <= '1' when seen_next = ALL_TAKEN else '0';

  -- Emit the instant a winner exists, or emit "nothing selected" when the
  -- round closes without one.
  valid_i    <= (has_win or cand_v or closing) and not emitted;
  outs_valid <= valid_i;
  outs       <= winner when has_win = '1' else cand;

  fire <= valid_i and outs_ready;
  -- The round is over once every input has given its token AND the output has
  -- been taken. Those can happen in either order.
  done <= closing and (emitted or fire);

  process (clk) is
  begin
    if (rising_edge(clk)) then
      if (rst = '1' or done = '1') then
        seen    <= (others => '0');
        winner  <= (others => '0');
        has_win <= '0';
        emitted <= '0';
      else
        seen <= seen_next;
        -- A token taken while the sink is stalled is still TAKEN, so it is
        -- latched here and held rather than lost.
        if has_win = '0' and cand_v = '1' then
          has_win <= '1';
          winner  <= cand;
        end if;
        -- Having emitted early, stay quiet while absorbing the stragglers.
        if fire = '1' then
          emitted <= '1';
        end if;
      end if;
    end if;
  end process;
end architecture;
