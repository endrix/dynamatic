def generate_stand_in(name, params):
    """Answers zero for a producer a commit stopped (`handshake.stand_in`).

    `outs` is `ins` while the producer answers. A kill ends the round: if its
    token has not passed, one zero is owed, offered from the next cycle on
    until taken; `ins` waits meanwhile. Two flip-flops: `sent` (this round's
    token has passed) and `owe`.

    `kill` has `size` bits, the kills of all the commits of the producer's
    domain (a domain may have several): any of them high ends ONE round, the
    unit otherwise the same whatever their number. The rounds of a domain
    never overlap -- a round of the domain starts only after the previous
    commit of the domain has transferred -- so at most one bit is high in a
    cycle, and it ends the round this unit is in. (Were state B's round to
    start before state A's commit transferred, A's kill would wipe it with
    A's round, and B's reader would wait for ever for this unit's token.) The
    producer's promise, asserted in simulation with the precondition.

    The zero is registered: offered in the kill cycle, `outs_valid` would
    depend on the decision's transfer, and the transfer on the readies of the
    units this channel feeds -- a combinational loop through them.

    The precondition: no kill while a token is offered at `outs` and not
    taken. A kill while the zero is owed and not taken would owe a second
    one, which two bits cannot hold (one zero for two rounds, and the
    decision waits for ever for the other); a kill while the producer's own
    token is offered and not taken resets the producer under `valid`, and
    the token becomes a zero before it transfers. So the stand-in's one
    reader must take a token the cycle it arrives, with nothing between that
    can hold it back (an eager fork whose other reader stalls, a join). A
    process between `pragma translate_off` and `translate_on` asserts it in
    simulation (severity failure), and the domain's promise (no two kills
    high in one cycle outside reset); synthesis skips both.
    """
    bitwidth = params["bitwidth"]
    size = params["size"]
    extra_signals = params.get("extra_signals", None)

    if size < 1:
        raise ValueError(
            "handshake.stand_in answers for a producer a commit stops, so it "
            "takes at least one kill")

    if bitwidth == 0:
        raise ValueError(
            "handshake.stand_in answers zero, so its channel carries data; a "
            "dataless stand-in would send a token nobody asked for")
    if extra_signals:
        raise ValueError(
            "handshake.stand_in passes its payload alone; a channel with "
            "extra signals would lose them (the op's verifier refuses it)")

    entity = f"""
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Entity of stand_in
entity {name} is
  port (
    clk : in std_logic;
    rst : in std_logic;
    -- input channel
    ins       : in  std_logic_vector({bitwidth} - 1 downto 0);
    ins_valid : in  std_logic;
    ins_ready : out std_logic;
    -- the commits' transfers, one bit a commit: any ends the round
    kill : in std_logic_vector({size} - 1 downto 0);
    -- output channel
    outs       : out std_logic_vector({bitwidth} - 1 downto 0);
    outs_valid : out std_logic;
    outs_ready : in  std_logic
  );
end entity;
"""

    architecture = f"""
-- Architecture of stand_in
architecture arch of {name} is
  constant NO_KILL : std_logic_vector({size} - 1 downto 0) := (others => '0');
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
  -- waits at `outs`, neither the zero owed nor the producer's own. And the
  -- domain's promise: its rounds never overlap, so no two of its commits
  -- transfer in one cycle (under reset every commit's kill is high).
  -- pragma translate_off
  process (clk) is
    variable kills_high : integer;
  begin
    if rising_edge(clk) and rst = '0' then
      if kill_any = '1' and outs_ready = '0' then
        assert owe = '0'
          report "stand_in: a round ended (kill) while the zero it owes was offered and not taken"
          severity failure;
        assert ins_valid = '0'
          report "stand_in: a round ended (kill) while the producer's token was offered and not taken"
          severity failure;
      end if;
      kills_high := 0;
      for i in kill'range loop
        if kill(i) = '1' then
          kills_high := kills_high + 1;
        end if;
      end loop;
      assert kills_high <= 1
        report "stand_in: two commits of its kill domain transferred in one cycle (the domain's rounds overlap)"
        severity failure;
    end if;
  end process;
  -- pragma translate_on
end architecture;
"""

    return entity + architecture
