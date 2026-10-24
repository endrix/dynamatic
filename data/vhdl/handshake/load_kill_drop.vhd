library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- A load whose requester a commit can stop (`handshake.load` under
-- `handshake.kill_domain`). The memory controller cannot forget a granted read
-- and an address in the load's own slot will be granted in its turn, so the
-- load is not reset with the units it serves: it counts the words it owes them
-- (addresses accepted, less words passed on) and, on `kill`, every word still
-- owed is a dead evaluation's and is taken from the controller and offered to
-- nobody. At most three are owed (the two slots and the controller's word
-- register for the port): two bits. The same circuit as the generator's
-- (tools/unit-generators/vhdl/generators/handshake/load.py, kill_drop), with
-- the widths lifted into generics.
entity load_kill_drop is
  generic (
    DATA_TYPE : integer;
    ADDR_TYPE : integer
  );
  port (
    clk : in  std_logic;
    rst : in std_logic;
    -- address from circuit channel
    addrIn       : in  std_logic_vector(ADDR_TYPE - 1 downto 0);
    addrIn_valid : in  std_logic;
    addrIn_ready : out std_logic;
    -- address to interface channel
    addrOut       : out std_logic_vector(ADDR_TYPE - 1 downto 0);
    addrOut_valid : out std_logic;
    addrOut_ready : in  std_logic;
    -- data from interface channel
    dataFromMem       : in  std_logic_vector(DATA_TYPE - 1 downto 0);
    dataFromMem_valid : in  std_logic;
    dataFromMem_ready : out std_logic;
    -- data from memory channel
    dataOut       : out std_logic_vector(DATA_TYPE - 1 downto 0);
    dataOut_valid : out std_logic;
    dataOut_ready : in  std_logic;
    -- the requester was stopped: what it is owed is dropped
    kill : in std_logic
  );
end entity;

architecture arch of load_kill_drop is
  signal addr_ready, word_valid, word_ready : std_logic;
  signal accepted, passed, dropping         : std_logic;
  signal owed, drop                         : unsigned(1 downto 0);
begin
  addr_one_slot_break_r : entity work.tehb(arch)
    generic map(
      DATA_TYPE => ADDR_TYPE
    )
    port map(
      clk => clk,
      rst => rst,
      -- input channel
      ins       => addrIn,
      ins_valid => addrIn_valid,
      ins_ready => addr_ready,
      -- output channel
      outs       => addrOut,
      outs_valid => addrOut_valid,
      outs_ready => addrOut_ready
    );

  data_one_slot_break_r : entity work.tehb(arch)
    generic map(
      DATA_TYPE => DATA_TYPE
    )
    port map(
      clk => clk,
      rst => rst,
      -- input channel
      ins       => dataFromMem,
      ins_valid => dataFromMem_valid,
      ins_ready => dataFromMem_ready,
      -- output channel
      outs       => dataOut,
      outs_valid => word_valid,
      outs_ready => word_ready
    );

  addrIn_ready  <= addr_ready;
  -- A word owed to a stopped evaluation is taken and offered to nobody.
  dropping      <= '1' when drop /= 0 else '0';
  dataOut_valid <= word_valid and not dropping;
  word_ready    <= dataOut_ready or dropping;

  accepted <= addrIn_valid and addr_ready;
  passed   <= word_valid and word_ready;

  process (clk) is
    variable owed_next : unsigned(1 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        owed <= (others => '0');
        drop <= (others => '0');
      else
        owed_next := owed;
        if accepted = '1' then
          owed_next := owed_next + 1;
        end if;
        if passed = '1' then
          owed_next := owed_next - 1;
        end if;
        owed <= owed_next;
        -- Everything still owed after the kill cycle is the dead
        -- evaluation's: an address accepted in it included, a word passed on
        -- in it not.
        if kill = '1' then
          drop <= owed_next;
        elsif dropping = '1' and passed = '1' then
          drop <= drop - 1;
        end if;
      end if;
    end if;
  end process;
end architecture;
