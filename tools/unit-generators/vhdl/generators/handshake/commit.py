def generate_commit(name, params):
    """A wire that says when its token has passed (`handshake.commit`).

    `outs` is `ins`, valid, data and ready straight through, no register.
    `kill` is the transfer, `ins_valid and outs_ready`, ORed with the reset:
    it is the reset of the units the transfer stops (`handshake.kill_domain`),
    which take it in place of the circuit's `rst`, so it must reset them at
    power-on too. Synchronous, as every unit's reset is: they are back in
    their reset state the cycle after the transfer.

    `kill_at_valid` (1): the kill in the FIRST cycle a token is offered
    instead, `ins_valid and not killed`, where `killed` (one flip-flop,
    reset low) is "offered and not taken last cycle"; the transfer of a
    token already killed is no kill. The kill reads no ready.
    """
    bitwidth = params["bitwidth"]
    extra_signals = params.get("extra_signals", None)
    at_valid = int(params.get("kill_at_valid", 0))

    if extra_signals:
        raise ValueError(
            "handshake.commit passes its payload alone; a channel with extra "
            "signals would lose them (the op's verifier refuses it)")
    if at_valid not in (0, 1):
        raise ValueError(
            f"handshake.commit: kill_at_valid is 0 or 1, not {at_valid}")

    data_in = f"ins : in std_logic_vector({bitwidth} - 1 downto 0);" \
        if bitwidth else ""
    data_out = f"outs : out std_logic_vector({bitwidth} - 1 downto 0);" \
        if bitwidth else ""
    data_wire = "outs <= ins;" if bitwidth else ""
    # what the kill is, in the form this commit has
    kill_comment = "the token's first offer" if at_valid else "the transfer"

    entity = f"""
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Entity of commit
entity {name} is
  port (
    clk : in std_logic;
    rst : in std_logic;
    -- input channel
    {data_in}
    ins_valid : in  std_logic;
    ins_ready : out std_logic;
    -- output channel
    {data_out}
    outs_valid : out std_logic;
    outs_ready : in  std_logic;
    -- {kill_comment}, as the reset of what it stops
    kill : out std_logic
  );
end entity;
"""

    if not at_valid:
        architecture = f"""
-- Architecture of commit
architecture arch of {name} is
begin
  {data_wire}
  outs_valid <= ins_valid;
  ins_ready  <= outs_ready;
  kill       <= rst or (ins_valid and outs_ready);
end architecture;
"""
        return entity + architecture

    architecture = f"""
-- Architecture of commit (the kill when the token is first offered)
architecture arch of {name} is
  -- the token now offered was offered last cycle and not taken: it has had
  -- its kill
  signal killed : std_logic;
begin
  {data_wire}
  outs_valid <= ins_valid;
  ins_ready  <= outs_ready;
  kill       <= rst or (ins_valid and not killed);

  process (clk) is
  begin
    if rising_edge(clk) then
      if rst = '1' then
        killed <= '0';
      else
        killed <= ins_valid and not outs_ready;
      end if;
    end if;
  end process;
end architecture;
"""
    return entity + architecture
