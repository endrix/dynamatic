from generators.support.arith_binary import generate_arith_binary
from generators.handshake.join import generate_join


def generate_divui(name, params):
    impl = params.get("impl", "pipelined")
    if impl == "sequential":
        return _generate_divui_sequential(name, params)
    if impl != "pipelined":
        raise ValueError(f"divui: unknown impl {impl!r} (pipelined or sequential)")
    return _generate_divui_pipelined(name, params)


def _generate_divui_pipelined(name, params):
    """The Vitis long-division IP: one stage per bit, a new division every
    cycle, the quotient BITWIDTH + 3 cycles after the operands."""

    latency = params["latency"]
    # FIXME: The latency of the long division depends on the bitwidth, but it
    # was hardcoded to 35 in the performance model.
    #
    # Here, we use the actual latency of the Vitis IP (see below for the
    # formula). This wouldn't change most of our benchmarks in the integration
    # tests (they use 32-bit division in any case), but we need to remember to
    # change the timing model to reflect this.
    bitwidth = params["bitwidth"]
    # The long division algorithm in the Vitis IP needs:
    # 2 cycles from the input/output regs
    # 1 cycle from the input reg of the division unit
    # BITWIDTH number for the actual division.
    latency = bitwidth + 2 + 1

    extra_signals = params.get("extra_signals", None)

    body = f"""
    divui_vitis_hls_wrapper_U1 : entity work.divui_vitis_hls_wrapper
    generic map({bitwidth}, {bitwidth}, {bitwidth})
    port map(
      clk   => clk,
      reset => rst,
      ce    => valid_buffer_ready,
      din0  => lhs,
      din1  => rhs,
      dout  => result
    );
    """

    return generate_arith_binary(
        name=name,
        handshake_op="divui",
        bitwidth=bitwidth,
        body=body,
        latency=latency,
        extra_signals=extra_signals
    )


def _generate_divui_sequential(name, params):
    """One division at a time, one quotient bit per cycle: the Vitis IP's
    restoring step (a shifted remainder minus the divisor; the bit is the
    borrow's complement, the remainder the difference when it did not
    borrow) run BITWIDTH times over one register set instead of BITWIDTH
    stages, so the quotient is the IP's bit for bit, division by zero
    included (every step fails to borrow: all ones). The operands are
    joined and taken when the unit is idle and no quotient is waiting; the
    quotient is held until it is taken. A new division starts the cycle
    the quotient goes, BITWIDTH + 1 cycles after the operands."""

    bitwidth = params["bitwidth"]
    extra_signals = params.get("extra_signals", None)
    if extra_signals:
        raise ValueError("divui: the sequential divider carries no extra signals")

    join_name = f"{name}_join"
    dependencies = generate_join(join_name, {"size": 2})

    entity = f"""
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Entity of divui (sequential)
entity {name} is
  port(
    clk: in std_logic;
    rst: in std_logic;
    -- input channel lhs
    lhs: in std_logic_vector({bitwidth} - 1 downto 0);
    lhs_valid: in std_logic;
    lhs_ready: out std_logic;
    -- input channel rhs
    rhs: in std_logic_vector({bitwidth} - 1 downto 0);
    rhs_valid: in std_logic;
    rhs_ready: out std_logic;
    -- output channel result
    result : out std_logic_vector({bitwidth} - 1 downto 0);
    result_valid: out std_logic;
    result_ready: in std_logic
  );
end entity;
"""

    architecture = f"""
-- Architecture of divui (sequential)
architecture arch of {name} is
  signal join_valid, accept, idle : std_logic;
  signal busy, done : std_logic;
  signal count : unsigned({bitwidth.bit_length()} - 1 downto 0);
  signal dividend, divisor, remd : unsigned({bitwidth} - 1 downto 0);
  signal comb : unsigned({bitwidth} - 1 downto 0);
  signal cal : unsigned({bitwidth} downto 0);
begin
  -- the operands are taken together, when nothing is running and no
  -- quotient is waiting (or it goes this cycle)
  idle <= (not busy) and ((not done) or result_ready);
  join_inputs : entity work.{join_name}(arch)
    port map(
      ins_valid(0) => lhs_valid,
      ins_valid(1) => rhs_valid,
      ins_ready(0) => lhs_ready,
      ins_ready(1) => rhs_ready,
      outs_valid   => join_valid,
      outs_ready   => idle
    );
  accept <= join_valid and idle;

  -- one restoring step: the Vitis IP's, on registers instead of stages
  comb <= remd({bitwidth} - 2 downto 0) & dividend({bitwidth} - 1);
  cal  <= ('0' & comb) - ('0' & divisor);

  process (clk) is
  begin
    if rising_edge(clk) then
      if rst = '1' then
        busy  <= '0';
        done  <= '0';
        count <= (others => '0');
      else
        if done = '1' and result_ready = '1' then
          done <= '0';
        end if;
        if accept = '1' then
          dividend <= unsigned(lhs);
          divisor  <= unsigned(rhs);
          remd     <= (others => '0');
          count    <= (others => '0');
          busy     <= '1';
        elsif busy = '1' then
          -- the quotient bit shifts in from the right; after BITWIDTH steps
          -- the dividend register holds the quotient
          dividend <= dividend({bitwidth} - 2 downto 0) & (not cal({bitwidth}));
          if cal({bitwidth}) = '1' then
            remd <= comb;
          else
            remd <= cal({bitwidth} - 1 downto 0);
          end if;
          if count = {bitwidth} - 1 then
            busy <= '0';
            done <= '1';
          end if;
          count <= count + 1;
        end if;
      end if;
    end if;
  end process;

  result       <= std_logic_vector(dividend);
  result_valid <= done;
end architecture;
"""

    return dependencies + entity + architecture
