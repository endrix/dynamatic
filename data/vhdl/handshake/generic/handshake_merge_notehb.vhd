-- handshake_merge_notehb: a merge of SIZE data channels with no slot behind
-- its arbiter (TEHB = 0). The first valid input wins, found by a parallel
-- prefix OR; the data is an AND-OR of the one-hot `first` with the inputs.
-- One generic entity for every size and width, with the logic the unit
-- generator (tools/unit-generators/vhdl/generators/handshake/merge_notehb.py)
-- writes for channels without extra signals.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.types.all;

entity handshake_merge_notehb is
  generic (
    SIZE      : integer;
    DATA_TYPE : integer
  );
  port (
    clk, rst   : in  std_logic;
    -- input channels
    ins        : in  data_array(SIZE - 1 downto 0)(DATA_TYPE - 1 downto 0);
    ins_valid  : in  std_logic_vector(SIZE - 1 downto 0);
    ins_ready  : out std_logic_vector(SIZE - 1 downto 0);
    -- output channel
    outs       : out std_logic_vector(DATA_TYPE - 1 downto 0);
    outs_valid : out std_logic;
    outs_ready : in  std_logic
  );
end entity;

architecture arch of handshake_merge_notehb is
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
  type masked_t is array (0 to SIZE - 1) of std_logic_vector(DATA_TYPE - 1 downto 0);
  signal masked : masked_t;
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
  gen_mask : for i in 0 to SIZE - 1 generate
    masked(i) <= ins(i) when first(i) = '1' else (others => '0');
  end generate;
  process (masked)
    variable acc : std_logic_vector(DATA_TYPE - 1 downto 0);
  begin
    acc := (others => '0');
    for i in 0 to SIZE - 1 loop
      acc := acc or masked(i);
    end loop;
    outs <= acc;
  end process;
  outs_valid <= '1' when unsigned(ins_valid) /= 0 else '0';
  ins_ready  <= first when outs_ready = '1' else (others => '0');
end architecture;
