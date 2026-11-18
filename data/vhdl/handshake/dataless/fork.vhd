-- The eager fork: each output takes the token of `ins` at its own time, and
-- `ins` is taken in the cycle the last output takes it.
--
-- The fork remembers, per output, whether the output still owes the token:
-- transmit(i). With one or two outputs, transmit(i) is a register of its own
-- (eager_fork_register_block). The cycle the token completes, every one of
-- them is set again, so the completion (no output stops) drives SIZE
-- registers, behind the logic that computes it.
--
-- From PHASE_MIN outputs on, transmit(i) is stored against a phase:
--
--   transmit(i) = emitted(i) xor phase
--
--   an output's own transfer writes   emitted(i) := phase      (owes nothing)
--   the token's completion flips      phase                    (all owe again)
--   a cycle without a valid input     emitted(i) := not phase  (all owe)
--
-- emitted(i) reads ins_valid, its own outs_ready and the two registers; only
-- phase reads the completion. transmit(i) is, cycle for cycle and for every
-- input sequence, the register of the first form. Both are 1 out of reset,
-- and then:
--
--   ins_valid = 0         both are 1 next (the phase holds);
--   the token completes   the first form sets every register; here every
--                         emitted(i) is `phase` next (written now, or so
--                         already) and the phase flips;
--   otherwise             an output that transfers goes to 0 in both, and
--                         any other holds in both.
--
-- outs_valid and ins_ready read nothing else, so the two forms are one unit
-- at their ports. The second costs one flip-flop more and an xor between
-- the registers and the ports, and the phase drives every output's xor where
-- the completion drove every output's register: the fan-out moves from the
-- end of the paths into the fork to the start of the paths out of it.
--
-- One and two outputs keep the first form: the completion drives at most two
-- registers there. The unit generator's fork is this logic at every size
-- (tools/unit-generators/vhdl/generators/handshake/fork.py).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fork_dataless is
  generic (
    SIZE : integer
  );
  port (
    clk, rst : in std_logic;
    -- input channel
    ins_valid : in  std_logic;
    ins_ready : out std_logic;
    -- output channels
    outs_valid : out std_logic_vector(SIZE - 1 downto 0);
    outs_ready : in  std_logic_vector(SIZE - 1 downto 0)
  );
end entity;

architecture arch of fork_dataless is
  constant PHASE_MIN : integer := 3;
begin
  gen_plain : if SIZE < PHASE_MIN generate
    signal blockStopArray : std_logic_vector(SIZE - 1 downto 0);
    signal anyBlockStop   : std_logic;
    signal backpressure   : std_logic;
  begin
    anyBlockFull : entity work.or_n generic map (SIZE)
      port map(
        blockStopArray,
        anyBlockStop
      );

    ins_ready    <= not anyBlockStop;
    backpressure <= ins_valid and anyBlockStop;

    generateBlocks : for i in SIZE - 1 downto 0 generate
      regblock : entity work.eager_fork_register_block(arch)
        port map(
          clk          => clk,
          rst          => rst,
          ins_valid    => ins_valid,
          outs_ready   => outs_ready(i),
          backpressure => backpressure,
          outs_valid   => outs_valid(i),
          blockStop    => blockStopArray(i)
        );
    end generate;
  end generate;

  gen_phase : if SIZE >= PHASE_MIN generate
    signal phase        : std_logic;
    signal emitted      : std_logic_vector(SIZE - 1 downto 0);
    signal transmit     : std_logic_vector(SIZE - 1 downto 0);
    signal blockStop    : std_logic_vector(SIZE - 1 downto 0);
    signal anyBlockStop : std_logic;
    signal complete     : std_logic;
  begin
    transmit  <= emitted xor (SIZE - 1 downto 0 => phase);
    blockStop <= transmit and not outs_ready;
    anyBlockStop <= '0' when blockStop = (SIZE - 1 downto 0 => '0') else '1';
    ins_ready  <= not anyBlockStop;
    outs_valid <= transmit and (SIZE - 1 downto 0 => ins_valid);
    complete   <= ins_valid and not anyBlockStop;

    process (clk)
    begin
      if rising_edge(clk) then
        if rst = '1' then
          phase   <= '0';
          emitted <= (others => '1');
        else
          phase <= phase xor complete;
          for i in 0 to SIZE - 1 loop
            if ins_valid = '0' then
              emitted(i) <= not phase;
            elsif transmit(i) = '1' and outs_ready(i) = '1' then
              emitted(i) <= phase;
            end if;
          end loop;
        end if;
      end if;
    end process;
  end generate;
end architecture;
