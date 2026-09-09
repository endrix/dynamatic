def generate_merge_notehb(name, params):
    # Number of input ports
    size = params["size"]

    bitwidth = params.get("bitwidth", 0)

    if bitwidth == 0:
        return _generate_merge_notehb_dataless(name, size)
    else:
        return _generate_merge_notehb(name, size, bitwidth)


def _generate_merge_notehb_dataless(name, size):
    stages = max(1, (size - 1).bit_length())
    entity = f"""
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Entity of merge_notehb_dataless
entity {name} is
  port (
    clk : in std_logic;
    rst : in std_logic;
    -- input channels
    ins_valid : in  std_logic_vector({size} - 1 downto 0);
    ins_ready : out std_logic_vector({size} - 1 downto 0);
    -- output channel
    outs_valid : out std_logic;
    outs_ready : in  std_logic
  );
end entity;
"""

    architecture = f"""
-- Architecture of merge_notehb_dataless
--
-- The first valid input wins. `before(i)` says whether any input below i is
-- valid, computed as a parallel prefix OR in log2(size) stages rather than
-- by the `for ... exit` loop it was, which synthesised as a chain one level
-- per input: seventy-one inputs were 477 ps for this unit alone, 1.5 ns with
-- data.
architecture arch of {name} is
  constant STAGES : natural := {stages};
  type prefix_t is array (0 to STAGES) of std_logic_vector({size} - 1 downto 0);
  signal before  : prefix_t;
  signal first   : std_logic_vector({size} - 1 downto 0);
begin
  -- stage 0: what is strictly below each input, one step
  gen_stage0 : for i in 0 to {size} - 1 generate
    gen_low : if i = 0 generate
      before(0)(i) <= '0';
    end generate;
    gen_rest : if i > 0 generate
      before(0)(i) <= ins_valid(i - 1);
    end generate;
  end generate;
  -- stage s: doubling the reach
  gen_stages : for s in 1 to STAGES generate
    gen_bits : for i in 0 to {size} - 1 generate
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
"""
    return entity + architecture


def _generate_merge_notehb(name, size, bitwidth):
    stages = max(1, (size - 1).bit_length())
    entity = f"""
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.types.all;

-- Entity of merge_notehb
entity {name} is
  port (
    clk : in std_logic;
    rst : in std_logic;
    -- input channels
    ins       : in  data_array({size} - 1 downto 0)({bitwidth} - 1 downto 0);
    ins_valid : in  std_logic_vector({size} - 1 downto 0);
    ins_ready : out std_logic_vector({size} - 1 downto 0);
    -- output channel
    outs       : out std_logic_vector({bitwidth} - 1 downto 0);
    outs_valid : out std_logic;
    outs_ready : in  std_logic
  );
end entity;
"""

    architecture = f"""
-- Architecture of merge_notehb
--
-- As the dataless one: the first valid input wins, found by a parallel prefix
-- OR; the data is an AND-OR of the one-hot `first` with the inputs, which
-- the mapper balances, where the `for ... exit` loop it was made a chain one
-- level per input.
architecture arch of {name} is
  constant STAGES : natural := {stages};
  type prefix_t is array (0 to STAGES) of std_logic_vector({size} - 1 downto 0);
  signal before  : prefix_t;
  signal first   : std_logic_vector({size} - 1 downto 0);
  type masked_t is array (0 to {size} - 1) of std_logic_vector({bitwidth} - 1 downto 0);
  signal masked  : masked_t;
begin
  gen_stage0 : for i in 0 to {size} - 1 generate
    gen_low : if i = 0 generate
      before(0)(i) <= '0';
    end generate;
    gen_rest : if i > 0 generate
      before(0)(i) <= ins_valid(i - 1);
    end generate;
  end generate;
  gen_stages : for s in 1 to STAGES generate
    gen_bits : for i in 0 to {size} - 1 generate
      gen_far : if i >= 2 ** (s - 1) generate
        before(s)(i) <= before(s - 1)(i) or before(s - 1)(i - 2 ** (s - 1));
      end generate;
      gen_near : if i < 2 ** (s - 1) generate
        before(s)(i) <= before(s - 1)(i);
      end generate;
    end generate;
  end generate;
  first <= ins_valid and not before(STAGES);
  gen_mask : for i in 0 to {size} - 1 generate
    masked(i) <= ins(i) when first(i) = '1' else (others => '0');
  end generate;
  process (masked)
    variable acc : std_logic_vector({bitwidth} - 1 downto 0);
  begin
    acc := (others => '0');
    for i in 0 to {size} - 1 loop
      acc := acc or masked(i);
    end loop;
    outs <= acc;
  end process;
  outs_valid <= '1' when unsigned(ins_valid) /= 0 else '0';
  ins_ready  <= first when outs_ready = '1' else (others => '0');
end architecture;
"""
    return entity + architecture
