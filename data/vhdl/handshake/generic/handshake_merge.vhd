-- handshake_merge: a merge of SIZE data channels. The first valid input wins,
-- found by a parallel prefix OR in ceil(log2(SIZE)) stages; the data is an
-- AND-OR of the one-hot `first` with the inputs. Behind the arbiter sits a
-- slot that cuts ready, a register per data bit, unless TEHB is 0: a consumer
-- that cuts ready itself needs no second one, and the arbiter then drives
-- the output channel.
-- One generic entity for every size and width, with the logic the unit
-- generator (tools/unit-generators/vhdl/generators/handshake/merge.py and
-- merge_notehb.py) writes for channels without extra signals. Channels with
-- extra signals take the generator: its signal manager wraps this logic per
-- parameter set.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.types.all;

entity handshake_merge is
  generic (
    SIZE      : integer;
    DATA_TYPE : integer;
    TEHB      : integer
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

architecture arch of handshake_merge is
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
  -- the arbiter's output channel
  signal arb_data             : std_logic_vector(DATA_TYPE - 1 downto 0);
  signal arb_valid, arb_ready : std_logic;
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
  first <= ins_valid and not before(STAGES);
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
    arb_data <= acc;
  end process;
  arb_valid <= '1' when unsigned(ins_valid) /= 0 else '0';
  ins_ready <= first when arb_ready = '1' else (others => '0');

  gen_slot : if TEHB /= 0 generate
    slot : entity work.tehb generic map (DATA_TYPE)
      port map(
        clk        => clk,
        rst        => rst,
        ins        => arb_data,
        ins_valid  => arb_valid,
        ins_ready  => arb_ready,
        outs       => outs,
        outs_valid => outs_valid,
        outs_ready => outs_ready
      );
  end generate;

  -- no slot: the arbiter drives the output channel and reads its ready
  gen_bare : if TEHB = 0 generate
    outs       <= arb_data;
    outs_valid <= arb_valid;
    arb_ready  <= outs_ready;
  end generate;
end architecture;
