def generate_priority(name, params):
    """A priority merge that waits for its high input only.

    `hi` when it carries something, `lo` otherwise. Payload 0 is reserved for
    "nothing selected", as for `first`. The unit consumes exactly one token on
    each input per round, each the cycle it arrives, and emits exactly one:
    `hi` the cycle a non-zero `hi` arrives, whether `lo` has arrived or not;
    when `hi` arrives zero, `lo` the cycle `lo` is there (it may have come
    first, and is then held). The round closes once both inputs are in and the
    answer has been taken.

    The step `hi | (lo & (hi == 0))` built from stock units is made of joins
    and waits for `lo` even when `hi` decides; `first` would let a non-zero
    `lo` that arrives first win. This one waits for `hi`, always, and for `lo`
    only when `hi` is zero.

    One data register holds the answer as far as it is known: `hi` once a
    non-zero `hi` is in, `lo` before that. A non-zero `hi` makes `lo`
    irrelevant, so the two never need holding together.
    """
    bitwidth = params["bitwidth"]
    extra_signals = params.get("extra_signals", None)

    if bitwidth == 0:
        raise ValueError(
            "handshake.priority has no dataless form: the payload is the "
            "answer, and zero is 'nothing selected'. A dataless priority is "
            "a join.")
    if extra_signals:
        raise ValueError(
            "handshake.priority holds its payload alone; a channel with "
            "extra signals would lose them (the op's verifier refuses it)")

    return _generate_priority(name, bitwidth)


def _generate_priority(name, bitwidth):
    entity = f"""
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Entity of priority
entity {name} is
  port (
    clk : in std_logic;
    rst : in std_logic;
    -- input channels
    hi       : in  std_logic_vector({bitwidth} - 1 downto 0);
    hi_valid : in  std_logic;
    hi_ready : out std_logic;
    lo       : in  std_logic_vector({bitwidth} - 1 downto 0);
    lo_valid : in  std_logic;
    lo_ready : out std_logic;
    -- output channel
    outs       : out std_logic_vector({bitwidth} - 1 downto 0);
    outs_valid : out std_logic;
    outs_ready : in  std_logic
  );
end entity;
"""

    architecture = f"""
-- Architecture of priority
architecture arch of {name} is
  -- Round state: which inputs have given their token, whether the answer has
  -- been taken, whether a non-zero hi is in, and the answer so far.
  signal seen_hi, seen_lo : std_logic;
  signal emitted          : std_logic;
  signal hi_nz_r          : std_logic;
  signal held             : std_logic_vector({bitwidth} - 1 downto 0);

  signal take_hi, take_lo : std_logic;
  signal hi_here, lo_here : std_logic;
  signal hi_now_nz, hi_nz : std_logic;
  signal valid_i          : std_logic;
  signal fire, done       : std_logic;
begin
  -- Each input gives exactly one token per round. Ready is a function of
  -- REGISTERS ONLY, so this unit cannot close a valid -> ready -> valid ring.
  hi_ready <= not seen_hi;
  lo_ready <= not seen_lo;
  take_hi  <= hi_valid and not seen_hi;
  take_lo  <= lo_valid and not seen_lo;
  hi_here  <= seen_hi or take_hi;
  lo_here  <= seen_lo or take_lo;

  hi_now_nz <= take_hi when unsigned(hi) /= 0 else '0';
  hi_nz     <= hi_nz_r or hi_now_nz;

  -- hi decides alone when it is non-zero; otherwise lo decides once it is
  -- here. Never before hi is here, once a round. Combinational: latency zero.
  valid_i    <= not emitted and hi_here and (hi_nz or lo_here);
  outs_valid <= valid_i;
  outs       <= hi when hi_now_nz = '1' else
                held when hi_nz_r = '1' or take_lo = '0' else
                lo;

  fire <= valid_i and outs_ready;
  -- The round is over once both inputs have given their token AND the answer
  -- has been taken, in either order.
  done <= hi_here and lo_here and (emitted or fire);

  process (clk) is
  begin
    if rising_edge(clk) then
      if rst = '1' or done = '1' then
        seen_hi <= '0';
        seen_lo <= '0';
        emitted <= '0';
        hi_nz_r <= '0';
        held    <= (others => '0');
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
"""

    return entity + architecture
