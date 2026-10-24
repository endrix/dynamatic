library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- A priority merge that waits for its high input only.
--
-- `hi` when it carries something, `lo` otherwise. Payload 0 is reserved for
-- "nothing selected", as for `first`. The unit consumes exactly one token on
-- each input per round, each the cycle it arrives, and emits exactly one:
-- `hi` the cycle a non-zero `hi` arrives, whether `lo` has arrived or not;
-- when `hi` arrives zero, `lo` the cycle `lo` is there (it may have come
-- first, and is then held). The round closes once both inputs are in and the
-- answer has been taken.
--
-- The step `hi | (lo & (hi == 0))` built from stock units is made of joins
-- and waits for `lo` even when `hi` decides; `first` would let a non-zero
-- `lo` that arrives first win. This one waits for `hi`, always, and for `lo`
-- only when `hi` is zero. The round closes in the cycle it completes: the
-- input that gave its token is ready again the cycle the other arrives with
-- the answer taken or being taken, and gives the next round's; a non-zero
-- next hi, with this round's answer out earlier, goes in that same cycle.
-- Ready reads the other input's valid and outs_ready, as a join's does, never
-- its own input's valid, and the output's valid never reads outs_ready; valid
-- and data out are combinational (latency zero). The same circuit as the generator's
-- (tools/unit-generators/vhdl/generators/handshake/priority.py), with the
-- width lifted into a generic.
entity priority is
  generic (
    DATA_TYPE : integer
  );
  port (
    clk : in std_logic;
    rst : in std_logic;
    -- input channels
    hi       : in  std_logic_vector(DATA_TYPE - 1 downto 0);
    hi_valid : in  std_logic;
    hi_ready : out std_logic;
    lo       : in  std_logic_vector(DATA_TYPE - 1 downto 0);
    lo_valid : in  std_logic;
    lo_ready : out std_logic;
    -- output channel
    outs       : out std_logic_vector(DATA_TYPE - 1 downto 0);
    outs_valid : out std_logic;
    outs_ready : in  std_logic
  );
end entity;

architecture arch of priority is
  -- Round state: which inputs have given their token, whether the answer has
  -- been taken, whether a non-zero hi is in, and the answer so far.
  signal seen_hi, seen_lo : std_logic;
  signal emitted          : std_logic;
  signal hi_nz_r          : std_logic;
  signal held             : std_logic_vector(DATA_TYPE - 1 downto 0);

  signal take_hi, take_lo   : std_logic;
  signal done_hi, done_lo   : std_logic;
  signal again_hi, again_lo : std_logic;
  signal hi_here, lo_here   : std_logic;
  signal hi_is_nz           : std_logic;
  signal hi_now_nz, hi_nz   : std_logic;
  signal again_nz           : std_logic;
  signal valid_i, early     : std_logic;
  signal fire, done         : std_logic;
begin
  take_hi  <= hi_valid and not seen_hi;
  take_lo  <= lo_valid and not seen_lo;
  hi_here  <= seen_hi or take_hi;
  lo_here  <= seen_lo or take_lo;

  hi_is_nz  <= '1' when unsigned(hi) /= 0 else '0';
  hi_now_nz <= take_hi and hi_is_nz;
  hi_nz     <= hi_nz_r or hi_now_nz;

  -- hi decides alone when it is non-zero; otherwise lo decides once it is
  -- here. Never before hi is here, once a round. Combinational: latency zero.
  valid_i <= not emitted and hi_here and (hi_nz or lo_here);

  fire <= valid_i and outs_ready;
  -- The round is over once both inputs have given their token AND the answer
  -- has been taken, in either order.
  done <= hi_here and lo_here and (emitted or fire);

  -- Each input gives exactly one token per round: once it has, it is not
  -- ready again until the round completes -- and then at once, in the cycle
  -- it completes, which it reads from the OTHER input alone (its own token
  -- is in) and the answer taken or being taken. Its ready never reads its
  -- own valid and the output's valid never its ready. The next round's
  -- tokens it takes then; with the answer out earlier the output is free,
  -- and a non-zero hi among them goes now.
  done_hi  <= lo_here and (emitted or ((hi_nz_r or lo_here) and outs_ready));
  done_lo  <= hi_here and (emitted or outs_ready);
  hi_ready <= not seen_hi or done_hi;
  lo_ready <= not seen_lo or done_lo;
  again_hi <= hi_valid and seen_hi and done_hi;
  again_lo <= lo_valid and seen_lo and done_lo;
  again_nz <= again_hi and hi_is_nz;
  early    <= hi_valid and seen_hi and lo_here and emitted and hi_is_nz;

  outs_valid <= valid_i or early;
  outs       <= hi when hi_now_nz = '1' or early = '1' else
                held when hi_nz_r = '1' or take_lo = '0' else
                lo;

  process (clk) is
  begin
    if rising_edge(clk) then
      if rst = '1' then
        seen_hi <= '0';
        seen_lo <= '0';
        emitted <= '0';
        hi_nz_r <= '0';
        held    <= (others => '0');
      elsif done = '1' then
        -- The next round, from what it gave in this cycle.
        seen_hi <= again_hi;
        seen_lo <= again_lo;
        hi_nz_r <= again_nz;
        emitted <= early and outs_ready;
        if again_nz = '1' then
          held <= hi;
        elsif again_lo = '1' then
          held <= lo;
        else
          held <= (others => '0');
        end if;
      else
        seen_hi <= hi_here;
        seen_lo <= lo_here;
        hi_nz_r <= hi_nz;
        -- An input taken while the sink is stalled is still TAKEN, so what
        -- the answer needs of it is held rather than lost: a non-zero hi,
        -- else lo.
        if hi_now_nz = '1' then
          held <= hi;
        elsif take_lo = '1' and hi_nz_r = '0' then
          held <= lo;
        end if;
        -- Having answered early, stay quiet while absorbing the late input.
        if fire = '1' then
          emitted <= '1';
        end if;
      end if;
    end if;
  end process;
end architecture;
