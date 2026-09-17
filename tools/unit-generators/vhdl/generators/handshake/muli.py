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


def _csa_rows_to_two(rows):
    """One Wallace reduction: 3:2 compressors take three rows to two, the
    odd rows fall through, until two are left. Every row is a word modulo
    2^BITWIDTH, so the carry row is the majority shifted left one place and
    what leaves the top is dropped. Returns the signal names it declares,
    the concurrent assignments, the last two rows and the number of levels
    -- the depth of full adders one cycle carries."""

    declared = []
    assignments = []
    level = 0
    cur = list(rows)
    while len(cur) > 2:
        nxt = []
        i = 0
        idx = 0
        while len(cur) - i >= 3:
            x, y, z = cur[i], cur[i + 1], cur[i + 2]
            s = f"csa{level}_s{idx}"
            c = f"csa{level}_c{idx}"
            declared += [s, c]
            assignments.append(f"  {s} <= {x} xor {y} xor {z};")
            assignments.append(
                f"  {c} <= shift_left(({x} and {y}) or ({x} and {z}) or "
                f"({y} and {z}), 1);")
            nxt += [s, c]
            i += 3
            idx += 1
        nxt += cur[i:]
        cur = nxt
        level += 1
    return declared, assignments, cur, level


def _generate_muli_sequential(name, params):
    """One multiply at a time, STEP multiplier bits a cycle, on a carry-save
    accumulator: the accumulator is a redundant (sum, carry) pair, and each
    cycle reduces the STEP partial-product rows -- the multiplicand times
    one multiplier bit, shifted -- together with those two rows back to two
    through a tree of 3:2 compressors. No carry crosses the word while the
    multiply runs: a cycle is a few full adders deep whatever the width.
    One carry-propagate add at the end resolves the pair into the result,
    and that cycle is the only one that carries a carry. Everything is
    modulo 2^BITWIDTH -- the low BITWIDTH bits of the product, which are
    what the unit returns whatever the operands' sign (the two's complement
    of the low bits is the same). The operands are joined and taken when
    the unit is idle and no product is waiting; the product is held until
    taken; ceil(BITWIDTH / STEP) + 2 cycles a multiply, the extra one the
    resolving add."""

    bitwidth = params["bitwidth"]
    step = int(params.get("step", 1))
    if step < 1 or step > bitwidth:
        raise ValueError(f"muli: step {step} is not in 1..{bitwidth}")
    extra_signals = params.get("extra_signals", None)
    if extra_signals:
        raise ValueError("muli: the sequential multiplier carries no extra signals")
    iterations = -(-bitwidth // step)
    padded = iterations * step

    # the rows a cycle reduces: the accumulator's two and one per multiplier
    # bit of the step
    rows = ["sum_reg", "carry_reg"] + [f"pp{i}" for i in range(step)]
    csa_signals, csa_body, (sum_next, carry_next), levels = _csa_rows_to_two(rows)

    pp_decl = "".join(
        f"  signal pp{i}, ppm{i} : unsigned({bitwidth} - 1 downto 0);\n"
        for i in range(step))
    pp_body = "".join(
        f"  ppm{i} <= (others => b_reg({i}));\n"
        f"  pp{i} <= {'a_reg' if i == 0 else f'shift_left(a_reg, {i})'} and ppm{i};\n"
        for i in range(step))
    csa_decl = "".join(
        f"  signal {s} : unsigned({bitwidth} - 1 downto 0);\n"
        for s in csa_signals)

    join_name = f"{name}_join"
    dependencies = generate_join(join_name, {"size": 2})

    entity = f"""
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Entity of muli (sequential carry-save, {step} bits a cycle)
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
-- Architecture of muli (sequential carry-save, {step} bits a cycle,
-- {levels} levels of 3:2 compressors a cycle)
architecture arch of {name} is
  signal join_valid, accept, idle : std_logic;
  signal busy, resolving, done : std_logic;
  signal count : unsigned({iterations.bit_length()} - 1 downto 0);
  signal a_reg : unsigned({bitwidth} - 1 downto 0);
  signal b_reg : unsigned({padded} - 1 downto 0);
  signal sum_reg, carry_reg : unsigned({bitwidth} - 1 downto 0);
{pp_decl}{csa_decl}begin
  -- the operands are taken together, when nothing is running and no
  -- product is waiting (or it goes this cycle)
  idle <= (not busy) and (not resolving) and ((not done) or result_ready);
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

  -- the multiplicand, already shifted, times each of the next {step}
  -- multiplier bits: one row a bit
{pp_body}
  -- those rows and the accumulator's two, reduced back to two by 3:2
  -- compressors -- a sum row and a carry row, the carry shifted one place
{chr(10).join(csa_body)}

  process (clk) is
  begin
    if rising_edge(clk) then
      if rst = '1' then
        busy      <= '0';
        resolving <= '0';
        done      <= '0';
        count     <= (others => '0');
      else
        if done = '1' and result_ready = '1' then
          done <= '0';
        end if;
        if accept = '1' then
          a_reg     <= unsigned(lhs);
          b_reg     <= resize(unsigned(rhs), {padded});
          sum_reg   <= (others => '0');
          carry_reg <= (others => '0');
          count     <= (others => '0');
          busy      <= '1';
        elsif busy = '1' then
          sum_reg   <= {sum_next};
          carry_reg <= {carry_next};
          a_reg     <= shift_left(a_reg, {step});
          b_reg     <= shift_right(b_reg, {step});
          if count = {iterations} - 1 then
            busy      <= '0';
            resolving <= '1';
          end if;
          count <= count + 1;
        elsif resolving = '1' then
          -- the one carry-propagate add: the pair resolved in place
          sum_reg   <= sum_reg + carry_reg;
          resolving <= '0';
          done      <= '1';
        end if;
      end if;
    end if;
  end process;

  result       <= std_logic_vector(sum_reg);
  result_valid <= done;
end architecture;
"""

    return dependencies + entity + architecture
