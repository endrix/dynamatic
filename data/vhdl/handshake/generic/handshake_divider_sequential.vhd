-- handshake_divider_sequential: the four integer division units (divui,
-- divsi, remui, remsi) as one division at a time on one register set: the
-- restoring long division of the Vitis IP, a shifted remainder minus the
-- divisor, stepped DATA_TYPE times. After the last step the dividend register
-- holds the quotient and the remainder register the remainder, so the four
-- units are this one iteration and differ only in which register leaves and
-- in what the signs do. The operands are joined and taken when the unit is
-- idle and no result is waiting; the result is held until it is taken,
-- DATA_TYPE + 1 cycles after the operands.
--
-- A signed unit divides the magnitudes: each operand is negated on the way
-- in when it is negative and the result on the way out when it should be,
-- the quotient when the operands' signs differ and the remainder when the
-- dividend is negative (the quotient truncates toward zero, the remainder
-- takes the dividend's sign). A zero divisor never borrows: the unsigned
-- quotient is all ones and the unsigned remainder the dividend.
--
-- One generic entity for every width, with an architecture per unit (the
-- `arch-name` of its entry in the RTL configuration), each the core below
-- with its two settings: the logic the unit generator
-- (tools/unit-generators/vhdl/generators/support/sequential_divider.py)
-- writes. The sequential units carry no extra signals.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity handshake_divider_sequential_core is
  generic (
    DATA_TYPE : integer;
    IS_SIGNED : boolean; -- the operands and the result are two's complement
    REMAINDER : boolean  -- the remainder leaves, not the quotient
  );
  port (
    clk, rst     : in  std_logic;
    -- input channel lhs
    lhs          : in  std_logic_vector(DATA_TYPE - 1 downto 0);
    lhs_valid    : in  std_logic;
    lhs_ready    : out std_logic;
    -- input channel rhs
    rhs          : in  std_logic_vector(DATA_TYPE - 1 downto 0);
    rhs_valid    : in  std_logic;
    rhs_ready    : out std_logic;
    -- output channel result
    result       : out std_logic_vector(DATA_TYPE - 1 downto 0);
    result_valid : out std_logic;
    result_ready : in  std_logic
  );
end entity;

architecture arch of handshake_divider_sequential_core is
  -- the bits of n in binary: the width of the step counter
  function bit_length(n : natural) return natural is
    variable bits : natural := 0;
    variable rest : natural := n;
  begin
    while rest > 0 loop
      bits := bits + 1;
      rest := rest / 2;
    end loop;
    return bits;
  end function;

  signal join_valid, accept, idle : std_logic;
  signal busy, done               : std_logic;
  signal count                    : unsigned(bit_length(DATA_TYPE) - 1 downto 0);
  signal dividend, divisor, remd  : unsigned(DATA_TYPE - 1 downto 0);
  signal comb                     : unsigned(DATA_TYPE - 1 downto 0);
  signal cal                      : unsigned(DATA_TYPE downto 0);
  -- what goes into the iteration and what leaves it
  signal lhs_mag, rhs_mag, leaving : unsigned(DATA_TYPE - 1 downto 0);
  -- a signed unit only: whether the result leaving is to be negated, decided
  -- from the operands' signs when they are taken
  signal negate                   : std_logic;
begin
  -- the operands are taken together, when nothing is running and no result
  -- is waiting (or it goes this cycle)
  idle <= (not busy) and ((not done) or result_ready);
  join_inputs : entity work.join generic map (2)
    port map(
      ins_valid(0) => lhs_valid,
      ins_valid(1) => rhs_valid,
      ins_ready(0) => lhs_ready,
      ins_ready(1) => rhs_ready,
      outs_valid   => join_valid,
      outs_ready   => idle
    );
  accept <= join_valid and idle;

  -- signed: the magnitudes go into the iteration
  gen_magnitudes : if IS_SIGNED generate
    lhs_mag <= (not unsigned(lhs)) + 1 when lhs(DATA_TYPE - 1) = '1' else unsigned(lhs);
    rhs_mag <= (not unsigned(rhs)) + 1 when rhs(DATA_TYPE - 1) = '1' else unsigned(rhs);
  end generate;
  gen_operands : if not IS_SIGNED generate
    lhs_mag <= unsigned(lhs);
    rhs_mag <= unsigned(rhs);
  end generate;

  -- one restoring step: the Vitis IP's, on registers instead of stages
  comb <= remd(DATA_TYPE - 2 downto 0) & dividend(DATA_TYPE - 1);
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
          dividend <= lhs_mag;
          divisor  <= rhs_mag;
          remd     <= (others => '0');
          count    <= (others => '0');
          busy     <= '1';
          if IS_SIGNED then
            if REMAINDER then
              negate <= lhs(DATA_TYPE - 1);
            else
              negate <= lhs(DATA_TYPE - 1) xor rhs(DATA_TYPE - 1);
            end if;
          end if;
        elsif busy = '1' then
          -- the quotient bit shifts in from the right; after DATA_TYPE steps
          -- the dividend register holds the quotient
          dividend <= dividend(DATA_TYPE - 2 downto 0) & (not cal(DATA_TYPE));
          if cal(DATA_TYPE) = '1' then
            remd <= comb;
          else
            remd <= cal(DATA_TYPE - 1 downto 0);
          end if;
          if count = DATA_TYPE - 1 then
            busy <= '0';
            done <= '1';
          end if;
          count <= count + 1;
        end if;
      end if;
    end if;
  end process;

  gen_quotient : if not REMAINDER generate
    leaving <= dividend;
  end generate;
  gen_remainder : if REMAINDER generate
    leaving <= remd;
  end generate;

  -- signed: the result is negated on the way out when the operands' signs
  -- differ (quotient) or the dividend is negative (remainder)
  gen_signed_result : if IS_SIGNED generate
    result <= std_logic_vector((not leaving) + 1) when negate = '1'
              else std_logic_vector(leaving);
  end generate;
  gen_result : if not IS_SIGNED generate
    result <= std_logic_vector(leaving);
  end generate;
  result_valid <= done;
end architecture;

library ieee;
use ieee.std_logic_1164.all;

entity handshake_divider_sequential is
  generic (
    DATA_TYPE : integer
  );
  port (
    clk, rst     : in  std_logic;
    -- input channel lhs
    lhs          : in  std_logic_vector(DATA_TYPE - 1 downto 0);
    lhs_valid    : in  std_logic;
    lhs_ready    : out std_logic;
    -- input channel rhs
    rhs          : in  std_logic_vector(DATA_TYPE - 1 downto 0);
    rhs_valid    : in  std_logic;
    rhs_ready    : out std_logic;
    -- output channel result
    result       : out std_logic_vector(DATA_TYPE - 1 downto 0);
    result_valid : out std_logic;
    result_ready : in  std_logic
  );
end entity;

-- the unsigned quotient
architecture divui of handshake_divider_sequential is
begin
  core : entity work.handshake_divider_sequential_core
    generic map (DATA_TYPE, false, false)
    port map(
      clk          => clk,
      rst          => rst,
      lhs          => lhs,
      lhs_valid    => lhs_valid,
      lhs_ready    => lhs_ready,
      rhs          => rhs,
      rhs_valid    => rhs_valid,
      rhs_ready    => rhs_ready,
      result       => result,
      result_valid => result_valid,
      result_ready => result_ready
    );
end architecture;

-- the signed quotient
architecture divsi of handshake_divider_sequential is
begin
  core : entity work.handshake_divider_sequential_core
    generic map (DATA_TYPE, true, false)
    port map(
      clk          => clk,
      rst          => rst,
      lhs          => lhs,
      lhs_valid    => lhs_valid,
      lhs_ready    => lhs_ready,
      rhs          => rhs,
      rhs_valid    => rhs_valid,
      rhs_ready    => rhs_ready,
      result       => result,
      result_valid => result_valid,
      result_ready => result_ready
    );
end architecture;

-- the unsigned remainder
architecture remui of handshake_divider_sequential is
begin
  core : entity work.handshake_divider_sequential_core
    generic map (DATA_TYPE, false, true)
    port map(
      clk          => clk,
      rst          => rst,
      lhs          => lhs,
      lhs_valid    => lhs_valid,
      lhs_ready    => lhs_ready,
      rhs          => rhs,
      rhs_valid    => rhs_valid,
      rhs_ready    => rhs_ready,
      result       => result,
      result_valid => result_valid,
      result_ready => result_ready
    );
end architecture;

-- the signed remainder
architecture remsi of handshake_divider_sequential is
begin
  core : entity work.handshake_divider_sequential_core
    generic map (DATA_TYPE, true, true)
    port map(
      clk          => clk,
      rst          => rst,
      lhs          => lhs,
      lhs_valid    => lhs_valid,
      lhs_ready    => lhs_ready,
      rhs          => rhs,
      rhs_valid    => rhs_valid,
      rhs_ready    => rhs_ready,
      result       => result,
      result_valid => result_valid,
      result_ready => result_ready
    );
end architecture;
