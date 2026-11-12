-- handshake_merge_notehb_dataless: a merge of SIZE control channels with no
-- slot behind its arbiter (TEHB = 0). The first valid input wins; `before(i)`
-- says whether any input below i is valid, a parallel prefix OR in
-- ceil(log2(SIZE)) stages.
-- One generic entity for every size, with the logic the unit generator
-- (tools/unit-generators/vhdl/generators/handshake/merge_notehb.py) writes.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity handshake_merge_notehb_dataless is
  generic (
    SIZE : integer
  );
  port (
    clk, rst   : in  std_logic;
    -- input channels
    ins_valid  : in  std_logic_vector(SIZE - 1 downto 0);
    ins_ready  : out std_logic_vector(SIZE - 1 downto 0);
    -- output channel
    outs_valid : out std_logic;
    outs_ready : in  std_logic
  );
end entity;

architecture arch of handshake_merge_notehb_dataless is
  -- ceil(log2(SIZE)), at least one: the stages of the parallel prefix
  function prefix_stages(n : positive) return positive is
    variable s : natural := 0;
  begin
    while 2 ** s < n loop
      s := s + 1;
    end loop;
    if s = 0 then
      return 1;
    end if;
    return s;
  end function;
  constant STAGES : natural := prefix_stages(SIZE);
  type prefix_t is array (0 to STAGES) of std_logic_vector(SIZE - 1 downto 0);
  signal before : prefix_t;
  signal first  : std_logic_vector(SIZE - 1 downto 0);
begin
  -- stage 0: what is strictly below each input, one step
  gen_stage0 : for i in 0 to SIZE - 1 generate
    gen_low : if i = 0 generate
      before(0)(i) <= '0';
    end generate;
    gen_rest : if i > 0 generate
      before(0)(i) <= ins_valid(i - 1);
    end generate;
  end generate;
  -- stage s: doubling the reach
  gen_stages : for s in 1 to STAGES generate
    gen_bits : for i in 0 to SIZE - 1 generate
      gen_far : if i >= 2 ** (s - 1) generate
        before(s)(i) <= before(s - 1)(i) or before(s - 1)(i - 2 ** (s - 1));
      end generate;
      gen_near : if i < 2 ** (s - 1) generate
        before(s)(i) <= before(s - 1)(i);
      end generate;
    end generate;
  end generate;
  first      <= ins_valid and not before(STAGES);
  outs_valid <= '1' when unsigned(ins_valid) /= 0 else '0';
  ins_ready  <= first when outs_ready = '1' else (others => '0');
end architecture;
