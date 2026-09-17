from generators.support.arith_binary import generate_arith_binary
from generators.handshake.join import generate_join


def generate_muli(name, params):
    impl = params.get("impl", "pipelined")
    if impl == "sequential":
        return _generate_muli_sequential(name, params)
    if impl != "pipelined":
        raise ValueError(f"muli: unknown impl {impl!r} (pipelined or sequential)")
    return _generate_muli_pipelined(name, params)


def _generate_muli_pipelined(name, params):
    """The product in one cycle behind LATENCY registers: operand registers,
    the whole multiply, and delay registers -- a shape an FPGA tool retimes
    into its DSP pipeline. On a cell library nothing retimes it: the full
    array multiplier sits between two registers."""

    bitwidth = params["bitwidth"]
    latency = params["latency"]

    signals = f"""
  signal a_reg : std_logic_vector({bitwidth} - 1 downto 0);
  signal b_reg : std_logic_vector({bitwidth} - 1 downto 0);
  signal q0    : std_logic_vector({bitwidth} - 1 downto 0);
  signal q1    : std_logic_vector({bitwidth} - 1 downto 0);
  signal q2    : std_logic_vector({bitwidth} - 1 downto 0);
  signal mul   : std_logic_vector({bitwidth} - 1 downto 0);
    """

    body = f"""
  mul <= std_logic_vector(resize(unsigned(std_logic_vector(signed(a_reg) * signed(b_reg))), {bitwidth}));

  process (clk)
  begin
    if (clk'event and clk = '1') then
      if (valid_buffer_ready = '1') then
        a_reg <= lhs;
        b_reg <= rhs;
        q0    <= mul;
        q1    <= q0;
        q2    <= q1;
      end if;
    end if;
  end process;

  result <= q2;
    """

    return generate_arith_binary(
        name=name,
        handshake_op="muli",
        bitwidth=bitwidth,
        signals=signals,
        body=body,
        extra_signals=params.get("extra_signals", None),
        latency=latency
    )


def _generate_muli_sequential(name, params):
    """One multiply at a time, STEP multiplier bits a cycle: each cycle adds
    the multiplicand times the next STEP bits of the multiplier, shifted, to
    the accumulator, all modulo 2^BITWIDTH -- the low BITWIDTH bits of the
    product, which are what the unit returns whatever the operands' sign
    (the two's complement of the low bits is the same). The operands are
    joined and taken when the unit is idle and no product is waiting; the
    product is held until taken; ceil(BITWIDTH / STEP) + 1 cycles a
    multiply. STEP multiplier bits a cycle cost STEP rows of adders."""

    bitwidth = params["bitwidth"]
    step = int(params.get("step", 1))
    if step < 1 or step > bitwidth:
        raise ValueError(f"muli: step {step} is not in 1..{bitwidth}")
    extra_signals = params.get("extra_signals", None)
    if extra_signals:
        raise ValueError("muli: the sequential multiplier carries no extra signals")
    iterations = -(-bitwidth // step)
    padded = iterations * step

    join_name = f"{name}_join"
    dependencies = generate_join(join_name, {"size": 2})

    entity = f"""
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Entity of muli (sequential, {step} bits a cycle)
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
-- Architecture of muli (sequential, {step} bits a cycle)
architecture arch of {name} is
  signal join_valid, accept, idle : std_logic;
  signal busy, done : std_logic;
  signal count : unsigned({iterations.bit_length()} - 1 downto 0);
  signal a_reg : unsigned({bitwidth} - 1 downto 0);
  signal b_reg : unsigned({padded} - 1 downto 0);
  signal acc : unsigned({bitwidth} - 1 downto 0);
  signal partial : unsigned({bitwidth} + {step} - 1 downto 0);
begin
  -- the operands are taken together, when nothing is running and no
  -- product is waiting (or it goes this cycle)
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

  -- the multiplicand, already shifted, times the next {step} multiplier bits
  partial <= a_reg * b_reg({step} - 1 downto 0);

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
          a_reg <= unsigned(lhs);
          b_reg <= resize(unsigned(rhs), {padded});
          acc   <= (others => '0');
          count <= (others => '0');
          busy  <= '1';
        elsif busy = '1' then
          acc   <= acc + partial({bitwidth} - 1 downto 0);
          a_reg <= shift_left(a_reg, {step});
          b_reg <= shift_right(b_reg, {step});
          if count = {iterations} - 1 then
            busy <= '0';
            done <= '1';
          end if;
          count <= count + 1;
        end if;
      end if;
    end if;
  end process;

  result       <= std_logic_vector(acc);
  result_valid <= done;
end architecture;
"""

    return dependencies + entity + architecture
