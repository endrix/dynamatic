library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Answers zero for a producer a commit stopped (`handshake.stand_in`): `outs`
-- is `ins` while the producer answers; a kill ends the round, and if its token
-- has not passed one zero is owed, offered from the next cycle until taken,
-- `ins` waiting meanwhile. Two flip-flops, `sent` and `owe`. `kill` has SIZE
-- bits, one a commit (a domain may have several): any of them high ends ONE
-- round; the commits of a domain never end two rounds in one cycle (the
-- decisions they sit on are exclusive in time), the producer's promise. The
-- zero is
-- registered: offered in the kill cycle, `outs_valid` would depend on the
-- decision's transfer, and that on the readies of the units this channel
-- feeds, a combinational loop. The same circuit as the generator's
-- (tools/unit-generators/vhdl/generators/handshake/stand_in.py), with the
-- width and the number of kills lifted into generics.
--
-- The precondition: no kill while a token is offered at `outs` and not taken.
-- A kill while the zero is owed and not taken would owe a second one, which
-- two bits cannot hold (one zero for two rounds, and the decision waits for
-- ever for the other); a kill while the producer's own token is offered and
-- not taken resets the producer under `valid`, and the token becomes a zero
-- before it transfers. So the stand-in's one reader must take a token the
-- cycle it arrives, with nothing between that can hold it back (an eager fork
-- whose other reader stalls, a join). Asserted in simulation (severity
-- failure, between `pragma translate_off` and `translate_on`); synthesis
-- skips it.
entity stand_in is
  generic (
    SIZE      : integer;
    DATA_TYPE : integer
  );
  port (
    clk : in std_logic;
    rst : in std_logic;
    -- input channel
    ins       : in  std_logic_vector(DATA_TYPE - 1 downto 0);
    ins_valid : in  std_logic;
    ins_ready : out std_logic;
    -- the commits' transfers, one bit a commit: any ends the round
    kill : in std_logic_vector(SIZE - 1 downto 0);
    -- output channel
    outs       : out std_logic_vector(DATA_TYPE - 1 downto 0);
    outs_valid : out std_logic;
    outs_ready : in  std_logic
  );
end entity;

architecture arch of stand_in is
  constant NO_KILL : std_logic_vector(SIZE - 1 downto 0) := (others => '0');
  signal sent, owe : std_logic;
  signal passed    : std_logic;
  signal kill_any  : std_logic;
begin
  -- one round ends, whichever commit ends it
  kill_any   <= '0' when kill = NO_KILL else '1';
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
        if kill_any = '1' then
          sent <= '0';
        else
          sent <= sent or passed;
        end if;
        -- A round ended with its token not passed owes a zero; an owed zero
        -- is paid when taken.
        owe <= (kill_any and not (sent or passed)) or (owe and not outs_ready);
      end if;
    end if;
  end process;

  -- The precondition, in simulation only: a round ends only when no token
  -- waits at `outs`, neither the zero owed nor the producer's own.
  -- pragma translate_off
  process (clk) is
  begin
    if rising_edge(clk) and rst = '0' and kill_any = '1' and outs_ready = '0' then
      assert owe = '0'
        report "stand_in: a round ended (kill) while the zero it owes was offered and not taken"
        severity failure;
      assert ins_valid = '0'
        report "stand_in: a round ended (kill) while the producer's token was offered and not taken"
        severity failure;
    end if;
  end process;
  -- pragma translate_on
end architecture;
