from typing import List


def generate_ram(name, params):
    data_width = params["data_width"]
    addr_width = params["addr_width"]
    size = params["size"]
    values = params["values"]
    # SRAM macros: a memory of at least `sram_threshold` words (0: none)
    # with no initial content also gets a synthesis view under sram/, the
    # same entity wrapping the 1RW macro `sram_name` names (a format with
    # {size}, {width} and {addr}). See _generate_ram_sram.
    sram_threshold = params.get("sram_threshold", 0)
    sram_name = params.get("sram_name", "fakeram7_{size}x{width}")
    code = _generate_ram(
        name,
        data_width,
        addr_width,
        size,
        values,
    )
    if not _is_sram(size, values, sram_threshold):
        return code
    macro = sram_name.format(size=size, width=data_width, addr=addr_width)
    return code, {
        f"sram/{name}.vhd": _generate_ram_sram(name, data_width, addr_width,
                                               size, macro)
    }


def _generate_ram(
    name: str,
    data_width: int,
    addr_width: int,
    size: int,
    values: List[int],
):
    entity = f"""
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity {name} is
  port (
    clk       : in std_logic;
    rst       : in std_logic;
    -- from circuit (mem_controller / LSQ)
    loadEn    : in std_logic;
    loadAddr  : in std_logic_vector({addr_width} - 1 downto 0);
    storeEn   : in std_logic;
    storeAddr : in std_logic_vector({addr_width} - 1 downto 0);
    storeData : in std_logic_vector({data_width} - 1 downto 0);
    -- to circuit (mem_controller / LSQ)
    loadData  : out std_logic_vector({data_width} - 1 downto 0)
  );
end entity;
    """

    architecture = f"""
architecture arch of {name} is
  type ram_type is array (0 to {size} - 1) of std_logic_vector({data_width} - 1 downto 0);
  {_gen_intial_block(data_width, size, values)}
begin
  read_proc : process(clk)
  begin
    if (rising_edge(clk)) then
      if (loadEn = '1') then
        loadData <= ram(to_integer(unsigned(loadAddr)));
      end if;
    end if;
  end process;

  write_proc : process(clk)
  begin
    if (rising_edge(clk)) then
      if (storeEn = '1') then
        ram(to_integer(unsigned(storeAddr))) <= storeData;
      end if;
    end if;
  end process;
end architecture;
    """

    return entity + architecture


def _is_sram(size: int, values: List[int], threshold: int) -> bool:
    """Whether the memory gets the SRAM synthesis view: at least `threshold`
    words (0: never), and no initial content -- a macro powers up with
    nothing in it, and the flop model's initial values are the memory's
    reset content, which only flops carry."""
    return int(threshold) > 0 and int(size) >= int(threshold) \
        and all(float(v) == 0 for v in values)


def _generate_ram_sram(
    name: str,
    data_width: int,
    addr_width: int,
    size: int,
    macro: str,
):
    """The synthesis view: the entity of _generate_ram, its body a component
    instantiation of a 1RW SRAM macro with FakeRAM2.0's port names (rd_out,
    addr_in, we_in, wd_in, clk, ce_in). Written beside the flop model, under
    sram/, so that a simulation reading the export's directory still gets the
    flops and a synthesis that overlays sram/ gets the macro.

    One port serves both sides: the address is the store's when it stores,
    the load's otherwise, and the chip is enabled by either. The macro's
    registered read data is the flop model's loadData, valid the cycle after
    the load, which is when the memory controller's read arbiter samples it
    (sel_prev in read_data_signals); a store in that next cycle changes
    rd_out one cycle later still, so the arbiter never sees it. What the
    macro cannot give is a load and a store in ONE cycle: the flop model
    serves both (the load reads the old word); here the store takes the port
    and the load is lost. The lowering's per-memory access chain never issues
    the two together (measured on the transposer's two 64-word buffers, zero
    such cycles); a design that does needs a 1R1W macro, not this view."""
    return f"""
-- Synthesis view of {name}: the same entity as ../{name}.vhd, its body the
-- 1RW SRAM macro {macro} ({size} x {data_width}). A load and a store in
-- one cycle cannot both be served: the store takes the port.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity {name} is
  port (
    clk       : in std_logic;
    rst       : in std_logic;
    -- from circuit (mem_controller / LSQ)
    loadEn    : in std_logic;
    loadAddr  : in std_logic_vector({addr_width} - 1 downto 0);
    storeEn   : in std_logic;
    storeAddr : in std_logic_vector({addr_width} - 1 downto 0);
    storeData : in std_logic_vector({data_width} - 1 downto 0);
    -- to circuit (mem_controller / LSQ)
    loadData  : out std_logic_vector({data_width} - 1 downto 0)
  );
end entity;

architecture arch of {name} is
  component {macro}
    port (
      rd_out  : out std_logic_vector({data_width} - 1 downto 0);
      addr_in : in  std_logic_vector({addr_width} - 1 downto 0);
      we_in   : in  std_logic;
      wd_in   : in  std_logic_vector({data_width} - 1 downto 0);
      clk     : in  std_logic;
      ce_in   : in  std_logic
    );
  end component;
  signal addr : std_logic_vector({addr_width} - 1 downto 0);
  signal ce   : std_logic;
begin
  -- one port: the store's address when it stores, the load's otherwise
  addr <= storeAddr when storeEn = '1' else loadAddr;
  ce   <= loadEn or storeEn;

  macro : {macro}
    port map (
      rd_out  => loadData,
      addr_in => addr,
      we_in   => storeEn,
      wd_in   => storeData,
      clk     => clk,
      ce_in   => ce
    );
end architecture;
"""


"""
Returns the 2's complement binary representation of integer `n` with
the given `bitwidth`.
"""


def _to_twos_complement(n, bitwidth, addr):
    if n < 0:
        n = (1 << bitwidth) + n
    if n >= (1 << bitwidth) or n < 0:
        raise ValueError(
            f"""
            The memory cannot be correctly instantiated, since the value
            {n} at address {addr} doesn't fit in {bitwidth} bits.
            """
        )
    return format(n, f"0{bitwidth}b")


def _gen_intial_block(data_width: int, size: int, init_vals: List[int]):

    if init_vals == []:
        return "  signal ram : ram_type;\n"

    init_strings = []

    for addr, val in enumerate(init_vals):
        init_strings.append(
            '"' + _to_twos_complement(val, data_width, addr) + '"')

    if len(init_vals) < int(size):
        for _ in range(int(size) - len(init_vals)):
            init_strings.append('"' + f"{0:0{data_width}b}" + '"')

    # NAMED association, always. A positional aggregate of ONE element is
    # ambiguous in VHDL -- `("0000")` is a string literal, not a one-element
    # array -- so a size-1 memory produced code GHDL rejects with "can't match
    # string literal with type array subtype". Naming the index is valid for
    # every size and removes the special case.
    named = [f"{addr} => {val}" for addr, val in enumerate(init_strings)]
    return "signal ram : ram_type := (" + ",\n".join(named) + ");"
