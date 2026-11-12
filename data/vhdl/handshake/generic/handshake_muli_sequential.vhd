-- handshake_muli_sequential: one multiply at a time, STEP multiplier bits a
-- cycle; the low DATA_TYPE bits of the product, held until taken.
-- One generic entity for every width and step, with the logic the unit
-- generator (tools/unit-generators/vhdl/generators/handshake/muli.py, the
-- `sequential` implementation) writes. That multiplier carries no extra
-- signals; its latency is ceil(DATA_TYPE / STEP) + 1 cycles, which the
-- operation's LATENCY states and nothing here reads.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity handshake_muli_sequential is
  generic (
    STEP      : integer;
    DATA_TYPE : integer
  );
  port (
    clk          : in  std_logic;
    rst          : in  std_logic;
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

architecture arch of handshake_muli_sequential is
  -- The bits of a count up to n: 1 for 1, 2 for 2 and 3, 3 for 4 to 7.
  function bit_length(n : positive) return positive is
    variable bits : natural := 0;
    variable left : natural := n;
  begin
    while left > 0 loop
      bits := bits + 1;
      left := left / 2;
    end loop;
    return bits;
  end function;

  constant ITERATIONS : positive := (DATA_TYPE + STEP - 1) / STEP;
  constant PADDED     : positive := ITERATIONS * STEP;

  signal join_valid, accept, idle : std_logic;
  signal busy, done : std_logic;
  signal count : unsigned(bit_length(ITERATIONS) - 1 downto 0);
  signal a_reg : unsigned(DATA_TYPE - 1 downto 0);
  signal b_reg : unsigned(PADDED - 1 downto 0);
  signal acc : unsigned(DATA_TYPE - 1 downto 0);
  signal partial : unsigned(DATA_TYPE + STEP - 1 downto 0);
begin
  assert STEP >= 1 and STEP <= DATA_TYPE
    report "handshake_muli_sequential: a step of " & integer'image(STEP)
      & " for a width of " & integer'image(DATA_TYPE)
    severity failure;

  -- the operands are taken together, when nothing is running and no
  -- product is waiting (or it goes this cycle)
  idle <= (not busy) and ((not done) or result_ready);

  join_inputs : entity work.join(arch) generic map(2)
    port map(
      ins_valid(0) => lhs_valid,
      ins_valid(1) => rhs_valid,
      ins_ready(0) => lhs_ready,
      ins_ready(1) => rhs_ready,
      outs_valid   => join_valid,
      outs_ready   => idle
    );

  accept <= join_valid and idle;

  -- the multiplicand, already shifted, times the next STEP multiplier bits
  partial <= a_reg * b_reg(STEP - 1 downto 0);

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
          b_reg <= resize(unsigned(rhs), PADDED);
          acc   <= (others => '0');
          count <= (others => '0');
          busy  <= '1';
        elsif busy = '1' then
          acc   <= acc + partial(DATA_TYPE - 1 downto 0);
          a_reg <= shift_left(a_reg, STEP);
          b_reg <= shift_right(b_reg, STEP);
          if count = ITERATIONS - 1 then
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
