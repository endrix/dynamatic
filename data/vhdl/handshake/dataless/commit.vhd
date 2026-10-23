library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- `handshake.commit` on a control channel: valid and ready straight through,
-- `kill` the transfer ORed with the reset (see ../commit.vhd).
entity commit_dataless is
  port (
    clk : in std_logic;
    rst : in std_logic;
    -- input channel
    ins_valid : in  std_logic;
    ins_ready : out std_logic;
    -- output channel
    outs_valid : out std_logic;
    outs_ready : in  std_logic;
    -- the transfer, as the reset of what it stops
    kill : out std_logic
  );
end entity;

architecture arch of commit_dataless is
begin
  outs_valid <= ins_valid;
  ins_ready  <= outs_ready;
  kill       <= rst or (ins_valid and outs_ready);
end architecture;
