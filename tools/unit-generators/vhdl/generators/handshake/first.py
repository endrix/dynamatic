from generators.support.signal_manager import generate_concat_signal_manager
from generators.support.signal_manager.utils.concat import get_concat_extra_signals_bitwidth


def generate_first(name, params):
    """A first-wins merge with full consumption.

    Unlike `merge`, which forwards one input and consumes ONE token per firing,
    `first` consumes exactly one token on EVERY input per round and emits one.
    The emitted payload is the first non-zero one to arrive; if every input
    carries zero the output is zero. Payload 0 is reserved for "nothing
    selected", which is what makes a winner distinguishable from a loser.

    Consuming all inputs is what keeps a round aligned: a token left behind on
    one input reappears in the next round and shifts every later decision by
    one. Emitting early is what the unit exists for. The two deadlines are
    opposite, and the `seen` mask is what reconciles them -- an input that has
    given its token is simply not ready again until the round closes, so no
    round-start signal is needed anywhere.
    """
    size = params["size"]
    bitwidth = params["bitwidth"]
    extra_signals = params.get("extra_signals", None)

    if bitwidth == 0:
        raise ValueError(
            "handshake.first has no dataless form: the payload is what "
            "distinguishes a winner from a loser. A dataless first-wins unit "
            "is a join.")

    if extra_signals:
        return _generate_first_signal_manager(name, size, bitwidth, extra_signals)
    return _generate_first(name, size, bitwidth)


def _generate_first(name, size, bitwidth):
    entity = f"""
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.types.all;

-- Entity of first
entity {name} is
  port (
    clk : in std_logic;
    rst : in std_logic;
    -- input channels
    ins       : in  data_array({size} - 1 downto 0)({bitwidth} - 1 downto 0);
    ins_valid : in  std_logic_vector({size} - 1 downto 0);
    ins_ready : out std_logic_vector({size} - 1 downto 0);
    -- output channel
    outs       : out std_logic_vector({bitwidth} - 1 downto 0);
    outs_valid : out std_logic;
    outs_ready : in  std_logic
  );
end entity;
"""

    architecture = f"""
-- Architecture of first
architecture arch of {name} is
  constant ALL_TAKEN : std_logic_vector({size} - 1 downto 0) := (others => '1');

  -- Round state.
  signal seen    : std_logic_vector({size} - 1 downto 0);
  signal winner  : std_logic_vector({bitwidth} - 1 downto 0);
  signal has_win : std_logic;
  signal emitted : std_logic;

  signal taken, seen_next : std_logic_vector({size} - 1 downto 0);
  signal cand             : std_logic_vector({bitwidth} - 1 downto 0);
  signal cand_v           : std_logic;
  signal closing          : std_logic;
  signal valid_i          : std_logic;
  signal fire, done       : std_logic;
begin
  -- Each input gives exactly one token per round. Ready is a function of
  -- REGISTERS ONLY: nothing here reads outs_ready or any ins_valid, so this
  -- unit cannot close a valid -> ready -> valid ring the way a lazy fork can.
  ins_ready <= not seen;
  taken     <= ins_valid and not seen;
  seen_next <= seen or taken;

  -- The first non-zero payload among the tokens taken THIS cycle, by index
  -- order. Simultaneous arrivals are incomparable actions, so any of them is a
  -- conformant winner and index order is as good as anything.
  process (taken, ins)
    variable v : std_logic;
    variable d : std_logic_vector({bitwidth} - 1 downto 0);
  begin
    v := '0';
    d := (others => '0');
    for i in 0 to {size} - 1 loop
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
  -- round closes without one. Combinational in valid and data: latency zero.
  valid_i    <= (has_win or cand_v or closing) and not emitted;
  outs_valid <= valid_i;
  outs       <= winner when has_win = '1' else cand;

  fire <= valid_i and outs_ready;
  -- The round is over once every input has given its token AND the output has
  -- been taken. Those can happen in either order, and usually do not coincide.
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
"""

    return entity + architecture


def _generate_first_signal_manager(name, size, bitwidth, extra_signals):
    extra_signals_bitwidth = get_concat_extra_signals_bitwidth(extra_signals)
    return generate_concat_signal_manager(
        name,
        [{
            "name": "ins",
            "bitwidth": bitwidth,
            "extra_signals": extra_signals,
            "size": size
        }],
        [{
            "name": "outs",
            "bitwidth": bitwidth,
            "extra_signals": extra_signals
        }],
        extra_signals,
        lambda name: _generate_first(name, size, bitwidth + extra_signals_bitwidth))
