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
-- The round closes in the cycle it completes: an input that has given its
-- token is ready again the cycle the last one arrives with the answer taken or
-- being taken, and gives the next round's; with the answer out earlier, a
-- winner among those goes in that same cycle. `ins_ready` reads the other
-- inputs' valid and outs_ready, as a join's does, never its own input's valid,
-- and `outs_valid` never reads outs_ready.
-- Valid and data are combinational: latency zero, one round per cycle when
-- every input is valid and the sink is ready.
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

  signal taken, seen_next, carries : std_logic_vector(SIZE - 1 downto 0);
  signal done_wo, again, early_in  : std_logic_vector(SIZE - 1 downto 0);
  signal cand, cand_again, cand_early : std_logic_vector(DATA_TYPE - 1 downto 0);
  signal cand_v, again_v, early       : std_logic;
  signal closing                      : std_logic;
  signal valid_i                      : std_logic;
  signal fire, done                   : std_logic;
begin
  -- Each input gives exactly one token per round: once it has, it is not
  -- ready again until the round completes -- and then at once, in the cycle
  -- it completes.
  taken     <= ins_valid and not seen;
  seen_next <= seen or taken;

  -- The first non-zero payload among the tokens taken THIS cycle, by index
  -- order. Simultaneous arrivals are incomparable actions, so any of them is
  -- a conformant winner and index order is as good as anything.
  process (taken, ins)
    variable v : std_logic;
    variable d : std_logic_vector(DATA_TYPE - 1 downto 0);
  begin
    v := '0';
    d := (others => '0');
    for i in 0 to SIZE - 1 loop
      if unsigned(ins(i)) /= 0 then
        carries(i) <= taken(i);
      else
        carries(i) <= '0';
      end if;
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
  valid_i <= (has_win or cand_v or closing) and not emitted;

  fire <= valid_i and outs_ready;
  -- The round is over once every input has given its token AND the output has
  -- been taken. Those can happen in either order, and usually do not coincide.
  done <= closing and (emitted or fire);

  -- An input that has given its token is ready again the cycle the round
  -- completes, which it reads from the OTHER inputs alone (its own token is
  -- in): every other input given its token, the answer taken or being taken.
  -- Its ready never reads its own valid and the output's valid never its
  -- ready, so the unit closes no valid -> ready -> valid ring that a join
  -- would not. The next round's tokens it takes then; with the answer out
  -- earlier the output is free, and a winner among them goes now.
  process (seen_next, carries, has_win, emitted, outs_ready, ins_valid, seen, ins)
    variable all_others, any_other : std_logic;
    variable va, ve : std_logic;
    variable da, de : std_logic_vector(DATA_TYPE - 1 downto 0);
  begin
    va := '0';
    ve := '0';
    da := (others => '0');
    de := (others => '0');
    for k in 0 to SIZE - 1 loop
      all_others := '1';
      any_other  := '0';
      for j in 0 to SIZE - 1 loop
        if j /= k then
          all_others := all_others and seen_next(j);
          any_other  := any_other or carries(j);
        end if;
      end loop;
      done_wo(k)  <= all_others and (emitted or ((has_win or any_other or all_others) and outs_ready));
      again(k)    <= ins_valid(k) and seen(k) and all_others and (emitted or ((has_win or any_other or all_others) and outs_ready));
      early_in(k) <= ins_valid(k) and seen(k) and all_others and emitted;
      if va = '0' and ins_valid(k) = '1' and seen(k) = '1' and all_others = '1' and
         (emitted = '1' or ((has_win = '1' or any_other = '1' or all_others = '1') and outs_ready = '1')) and
         unsigned(ins(k)) /= 0 then
        va := '1';
        da := ins(k);
      end if;
      if ve = '0' and ins_valid(k) = '1' and seen(k) = '1' and all_others = '1' and emitted = '1' and
         unsigned(ins(k)) /= 0 then
        ve := '1';
        de := ins(k);
      end if;
    end loop;
    again_v    <= va;
    cand_again <= da;
    early      <= ve;
    cand_early <= de;
  end process;
  ins_ready  <= not seen or done_wo;

  outs_valid <= valid_i or early;
  outs       <= cand_early when emitted = '1' else
                winner when has_win = '1' else
                cand;

  process (clk) is
  begin
    if (rising_edge(clk)) then
      if (rst = '1') then
        seen    <= (others => '0');
        winner  <= (others => '0');
        has_win <= '0';
        emitted <= '0';
      elsif (done = '1') then
        -- The next round, from what it gave in this cycle.
        seen    <= again;
        has_win <= again_v;
        winner  <= cand_again;
        emitted <= early and outs_ready;
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
