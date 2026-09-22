from generators.handshake.join import generate_join


def generate_sequential_divider(name, op, bitwidth, signed, remainder):
    """The restoring long division of the Vitis IP run on ONE register set
    instead of one stage per bit: a shifted remainder minus the divisor, the
    quotient bit the borrow's complement, the remainder the difference when
    it did not borrow, stepped BITWIDTH times. After the last step the
    dividend register holds the quotient and the remainder register the
    remainder, so the four integer units are this one iteration and differ
    only in which register leaves and in what the signs do.

    `signed` divides the magnitudes: each operand is negated on the way in
    when it is negative and the result on the way out when it should be, the
    quotient when the operands' signs differ and the remainder when the
    dividend is negative. That is the Vitis signed core's own arrangement,
    and it is C99's and RISC-V's: the quotient truncates toward zero and the
    remainder takes the dividend's sign. Neither conversion costs a cycle --
    they are combinational on either side of the register set -- so a signed
    unit has the latency of an unsigned one.

    A zero divisor never borrows, so every quotient bit is one and the
    remainder register ends up holding the dividend: the unsigned quotient is
    all ones and the unsigned remainder the dividend, which is what RISC-V
    asks for. Signed, the magnitude quotient is all ones and the sign is then
    applied to it, so a negative dividend divided by zero gives one rather
    than minus one; that is the Vitis signed core's answer bit for bit, and
    the unit is a replacement for it and not a correction of it.

    The operands are joined and taken when the unit is idle and no result is
    waiting; the result is held until it is taken. A new division starts the
    cycle the result goes, BITWIDTH + 1 cycles after the operands."""

    join_name = f"{name}_join"
    dependencies = generate_join(join_name, {"size": 2})
    # what the unit's register set hands out, for the comments below
    what = "remainder" if remainder else "quotient"
    sign_rule = ("the dividend is negative" if remainder
                 else "the operands' signs differ")

    entity = f"""
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Entity of {op} (sequential)
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

    # The signed unit keeps two more registers: whether the result leaving is
    # to be negated, decided from the operands' signs when they are taken.
    sign_decls = f"""
  signal lhs_mag, rhs_mag : unsigned({bitwidth} - 1 downto 0);
  signal negate : std_logic;""" if signed else ""

    sign_conv = f"""
  -- the magnitudes go into the iteration; the result is negated on the way
  -- out when {sign_rule}
  lhs_mag <= (not unsigned(lhs)) + 1 when lhs({bitwidth} - 1) = '1' else unsigned(lhs);
  rhs_mag <= (not unsigned(rhs)) + 1 when rhs({bitwidth} - 1) = '1' else unsigned(rhs);
""" if signed else ""

    take_lhs = "lhs_mag" if signed else "unsigned(lhs)"
    take_rhs = "rhs_mag" if signed else "unsigned(rhs)"
    negate_at_accept = (
        f"\n          negate   <= lhs({bitwidth} - 1) xor rhs({bitwidth} - 1);"
        if signed and not remainder
        else f"\n          negate   <= lhs({bitwidth} - 1);"
        if signed
        else "")

    out_reg = "remd" if remainder else "dividend"
    if signed:
        result_assign = f"""  result       <= std_logic_vector((not {out_reg}) + 1) when negate = '1'
                  else std_logic_vector({out_reg});"""
    else:
        result_assign = f"  result       <= std_logic_vector({out_reg});"

    architecture = f"""
-- Architecture of {op} (sequential)
architecture arch of {name} is
  signal join_valid, accept, idle : std_logic;
  signal busy, done : std_logic;
  signal count : unsigned({bitwidth.bit_length()} - 1 downto 0);
  signal dividend, divisor, remd : unsigned({bitwidth} - 1 downto 0);
  signal comb : unsigned({bitwidth} - 1 downto 0);
  signal cal : unsigned({bitwidth} downto 0);{sign_decls}
begin
  -- the operands are taken together, when nothing is running and no
  -- {what} is waiting (or it goes this cycle)
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
{sign_conv}
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
          dividend <= {take_lhs};
          divisor  <= {take_rhs};
          remd     <= (others => '0');
          count    <= (others => '0');
          busy     <= '1';{negate_at_accept}
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

{result_assign}
  result_valid <= done;
end architecture;
"""

    return dependencies + entity + architecture
