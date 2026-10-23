library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- A wire that says when its token has passed (`handshake.commit`): `outs` is
-- `ins`, valid, data and ready straight through, no register. `kill` is the
-- transfer, ORed with the reset: it is the reset of the units the transfer
-- stops (`handshake.kill_domain`), which take it in place of the circuit's
-- `rst`, so it resets them at power-on too. The same circuit as the
-- generator's (tools/unit-generators/vhdl/generators/handshake/commit.py),
-- with the width lifted into a generic.
entity commit is
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
    -- output channel
    outs       : out std_logic_vector(DATA_TYPE - 1 downto 0);
    outs_valid : out std_logic;
    outs_ready : in  std_logic;
    -- the transfer, as the reset of what it stops
    kill : out std_logic
  );
end entity;

architecture arch of commit is
begin
  outs       <= ins;
  outs_valid <= ins_valid;
  ins_ready  <= outs_ready;
  kill       <= rst or (ins_valid and outs_ready);
end architecture;
