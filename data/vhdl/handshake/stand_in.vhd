library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Answers zero for a producer a commit stopped (`handshake.stand_in`): `outs`
-- is `ins` while the producer answers; `kill` ends the round, and if its token
-- has not passed one zero is owed, offered from the next cycle until taken,
-- `ins` waiting meanwhile. Two flip-flops, `sent` and `owe`. The zero is
-- registered: offered in the kill cycle, `outs_valid` would depend on the
-- decision's transfer, and that on the readies of the units this channel
-- feeds, a combinational loop. The same circuit as the generator's
-- (tools/unit-generators/vhdl/generators/handshake/stand_in.py), with the
-- width lifted into a generic.
entity stand_in is
  generic (
    DATA_TYPE : integer
  );
  port (
    clk : in std_logic;
    rst : in std_logic;
    -- input channel
    ins       : in  std_logic_vector(DATA_TYPE - 1 downto 0);
    ins_valid : in  std_logic;
    ins_ready : out std_logic;
    -- the commit's transfer: the end of a round
    kill : in std_logic;
    -- output channel
    outs       : out std_logic_vector(DATA_TYPE - 1 downto 0);
    outs_valid : out std_logic;
    outs_ready : in  std_logic
  );
end entity;

architecture arch of stand_in is
  signal sent, owe : std_logic;
  signal passed    : std_logic;
begin
  outs_valid <= owe or ins_valid;
  outs       <= (others => '0') when owe = '1' else ins;
  ins_ready  <= outs_ready and not owe;
  -- the producer's token goes through this cycle
  passed     <= ins_valid and outs_ready and not owe;

  process (clk) is
  begin
    if rising_edge(clk) then
      if rst = '1' then
        sent <= '0';
        owe  <= '0';
      else
        -- A kill ends the round: the next one has sent nothing yet.
        if kill = '1' then
          sent <= '0';
        else
          sent <= sent or passed;
        end if;
        -- A round ended with its token not passed owes a zero; an owed zero
        -- is paid when taken.
        owe <= (kill and not (sent or passed)) or (owe and not outs_ready);
      end if;
    end if;
  end process;
end architecture;
