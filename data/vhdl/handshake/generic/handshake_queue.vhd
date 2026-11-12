-- handshake_queue: an elastic FIFO of NUM_SLOTS slots that publishes how full
-- it is: `outs_size` says how many tokens are queued, `ins_space` how many
-- more it can take, both off a count register. INITIAL_TOKENS is what the
-- queue holds at reset, first out first: each token's bits at the data width,
-- joined by commas, or "none".
-- One generic entity for every depth, width and set of initial tokens, with
-- the logic the unit generator
-- (tools/unit-generators/vhdl/generators/handshake/queue.py) writes for a
-- data channel that publishes both counts. A queue without data, or without
-- one of the counts, has other ports and takes the generator.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity handshake_queue is
  generic (
    NUM_SLOTS      : integer;
    DATA_WIDTH     : integer;
    SIZE_WIDTH     : integer;
    SPACE_WIDTH    : integer;
    INITIAL_TOKENS : string
  );
  port (
    clk, rst   : in  std_logic;
    -- input channel
    ins        : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
    ins_valid  : in  std_logic;
    ins_ready  : out std_logic;
    ins_space  : out std_logic_vector(SPACE_WIDTH - 1 downto 0);
    -- output channel
    outs       : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    outs_valid : out std_logic;
    outs_ready : in  std_logic;
    outs_size  : out std_logic_vector(SIZE_WIDTH - 1 downto 0)
  );
end entity;

architecture arch of handshake_queue is
  -- The number of tokens in the text: none for "none", else one more than
  -- its commas.
  function token_count(text : string) return natural is
    variable n : natural := 1;
  begin
    if text = "none" then
      return 0;
    end if;
    for i in text'range loop
      if text(i) = ',' then
        n := n + 1;
      end if;
    end loop;
    return n;
  end function;

  -- Token `index` of the text, which has to be DATA_WIDTH binary digits.
  function token_bits(text : string; index : natural) return std_logic_vector is
    variable bits  : std_logic_vector(DATA_WIDTH - 1 downto 0) := (others => '0');
    variable at    : natural := 0;
    variable taken : natural := 0;
  begin
    for i in text'range loop
      if text(i) = ',' then
        at := at + 1;
      elsif at = index then
        assert text(i) = '0' or text(i) = '1'
          report "handshake_queue: INITIAL_TOKENS """ & text & """ has a token that is not binary"
          severity failure;
        assert taken < DATA_WIDTH
          report "handshake_queue: INITIAL_TOKENS """ & text & """ has a token wider than the data"
          severity failure;
        bits := bits(DATA_WIDTH - 2 downto 0) & '0';
        if text(i) = '1' then
          bits(0) := '1';
        end if;
        taken := taken + 1;
      end if;
    end loop;
    assert taken = DATA_WIDTH
      report "handshake_queue: INITIAL_TOKENS """ & text & """ has a token narrower than the data"
      severity failure;
    return bits;
  end function;

  constant NUM_INITIAL : natural := token_count(INITIAL_TOKENS);

  -- The tokens held at reset, read once when the design is elaborated: what
  -- the queue could not hold is refused then.
  type token_table is array (natural range <>) of std_logic_vector(DATA_WIDTH - 1 downto 0);
  function tokens(text : string; count : natural) return token_table is
    variable table : token_table(0 to count - 1);
  begin
    for i in 0 to count - 1 loop
      table(i) := token_bits(text, i);
    end loop;
    return table;
  end function;
  constant INITIAL : token_table(0 to NUM_INITIAL - 1) := tokens(INITIAL_TOKENS, NUM_INITIAL);

  signal ReadEn  : std_logic := '0';
  signal WriteEn : std_logic := '0';
  signal Tail    : natural range 0 to NUM_SLOTS - 1;
  signal Head    : natural range 0 to NUM_SLOTS - 1;
  -- Counts 0 to NUM_SLOTS INCLUSIVE, so empty and full are distinguishable;
  -- the head and tail pointers alone are not.
  signal Count   : natural range 0 to NUM_SLOTS;
  signal Empty   : std_logic;
  signal Full    : std_logic;
  type FIFO_Memory is array (0 to NUM_SLOTS - 1) of std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal Memory : FIFO_Memory;
begin
  assert NUM_INITIAL <= NUM_SLOTS
    report "handshake_queue: more initial tokens than slots"
    severity failure;

  Empty <= '1' when Count = 0 else '0';
  Full  <= '1' when Count = NUM_SLOTS else '0';

  -- Accept a token whenever there is room, and not "or room is being made
  -- this cycle": registered, the ready ends here.
  ins_ready  <= not Full;
  outs_valid <= not Empty;

  ReadEn  <= outs_ready and not Empty;
  WriteEn <= ins_valid and not Full;

  -- One register, up on a write and down on a read; a simultaneous write and
  -- read leaves it alone. It starts at the tokens held at reset.
  CountUpdate_proc : process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        Count <= NUM_INITIAL;
      elsif WriteEn = '1' and ReadEn = '0' then
        Count <= Count + 1;
      elsif ReadEn = '1' and WriteEn = '0' then
        Count <= Count - 1;
      end if;
    end if;
  end process;

  -- The tail starts past the tokens held at reset.
  TailUpdate_proc : process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        Tail <= NUM_INITIAL mod NUM_SLOTS;
      elsif WriteEn = '1' then
        Tail <= (Tail + 1) mod NUM_SLOTS;
      end if;
    end if;
  end process;

  HeadUpdate_proc : process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        Head <= 0;
      elsif ReadEn = '1' then
        Head <= (Head + 1) mod NUM_SLOTS;
      end if;
    end if;
  end process;

  -- write to the tail slot
  gen_empty : if NUM_INITIAL = 0 generate
    FifoWrite_proc : process (clk)
    begin
      if rising_edge(clk) then
        if WriteEn = '1' then
          Memory(Tail) <= ins;
        end if;
      end if;
    end process;
  end generate;

  -- the reset writes the tokens held at reset into the slots the head reads
  -- first; the other slots are written before they are read
  gen_initial : if NUM_INITIAL > 0 generate
    FifoWrite_proc : process (clk)
    begin
      if rising_edge(clk) then
        if rst = '1' then
          for i in 0 to NUM_INITIAL - 1 loop
            Memory(i) <= INITIAL(i);
          end loop;
        elsif WriteEn = '1' then
          Memory(Tail) <= ins;
        end if;
      end if;
    end process;
  end generate;

  outs <= Memory(Head);

  outs_size <= std_logic_vector(to_unsigned(Count, SIZE_WIDTH));
  ins_space <= std_logic_vector(to_unsigned(NUM_SLOTS - Count, SPACE_WIDTH));
end architecture;
