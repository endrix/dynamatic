import sys
from typing import List


def generate_ram(name, params):
    data_width = params["data_width"]
    addr_width = params["addr_width"]
    size = params["size"]
    values = params["values"]
    # SRAM macros: a memory of at least `sram_threshold` words (0: none)
    # with no initial content also gets a synthesis view under sram/, the
    # same entity wrapping a macro. `sram_interface` says which macro family
    # and port map: `fakeram` (FakeRAM2.0, one read-write port, a macro of
    # any size from the name pattern `sram_name`, a format with {size},
    # {width} and {addr}) or `openram` (OpenRAM's 1rw1r macros, one
    # read-write and one read port, fixed sizes). `sram_macros` lists the
    # macros on hand as (name, words, width) triples; the smallest one that
    # holds the memory is taken, padded with zeros where it is deeper or
    # wider. FakeRAM generates a macro of the memory's own size from the
    # name pattern and reads no list: its view is never padded. See
    # _generate_ram_sram and _generate_ram_openram.
    sram_threshold = params.get("sram_threshold", 0)
    sram_name = params.get("sram_name", "fakeram7_{size}x{width}")
    sram_interface = params.get("sram_interface", "fakeram")
    sram_macros = params.get("sram_macros", [])
    # RESET TO THE DECLARED CONTENT, for a target that has no other way to
    # load it. Off by default: on an FPGA the bitstream already loads the
    # declared content, and a reset in the write process stops the tool
    # inferring block RAM at all (measured with yosys synth_xilinx on a
    # 1024x32 ROM: one RAMB36E1 without it, some 32,800 flip-flops with
    # it). A cell library has no bitstream, so there the flow turns it on.
    # See `_gen_write_body`. The value is 0 or 1; the command line is read
    # with ast.literal_eval, so `true` or `yes` is refused rather than read.
    reset_content = bool(params.get("reset_content", 0))
    code = _generate_ram(
        name,
        data_width,
        addr_width,
        size,
        values,
        reset_content,
    )
    if not _is_sram(size, values, sram_threshold):
        return code
    if sram_interface not in ("fakeram", "openram"):
        raise ValueError(f"sram_interface {sram_interface!r} is not fakeram or openram")
    if sram_interface == "fakeram":
        macro = (sram_name.format(size=size, width=data_width, addr=addr_width), size, data_width)
    else:
        macro = _pick_macro(sram_macros, size, data_width)
    if macro is None:
        sys.stderr.write(f"{name}: no macro in sram_macros holds {size} x {data_width}; "
                         "the memory stays flops\n")
        return code
    view = (_generate_ram_openram if sram_interface == "openram" else _generate_ram_sram)(
        name, data_width, addr_width, size, macro)
    return code, {f"sram/{name}.vhd": view}


def _pick_macro(macros, size: int, width: int):
    """The smallest macro of `macros`, (name, words, width) triples, that
    holds a memory of `size` words of `width` bits: the fewest words, then
    the narrowest; None when no macro does (or the list is empty)."""
    fits = [tuple(m) for m in macros if int(m[1]) >= int(size) and int(m[2]) >= int(width)]
    if not fits:
        return None
    return min(fits, key=lambda m: (int(m[1]), int(m[2])))


def _generate_ram(
    name: str,
    data_width: int,
    addr_width: int,
    size: int,
    values: List[int],
    reset_content: bool = False,
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
  {_gen_intial_block(data_width, size, values, reset_content)}
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
{_gen_write_body(values, reset_content)}
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
    macro: tuple,
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
    such cycles); a design that does needs a 1R1W macro: the OpenRAM view."""
    macro = macro[0]
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


def _generate_ram_openram(
    name: str,
    data_width: int,
    addr_width: int,
    size: int,
    macro: tuple,
):
    """The synthesis view on an OpenRAM 1rw1r macro (`macro` is a (name,
    words, width) triple from `sram_macros`): the entity of _generate_ram,
    its body a component instantiation with OpenRAM's port names -- port 0
    (clk0, csb0, web0, wmask0, addr0, din0, dout0) is read-write and serves
    the store, port 1 (clk1, csb1, addr1, dout1) is read-only and serves the
    load, so a load and a store in ONE cycle at different addresses are
    both served; at the same address the macro's read data is undefined
    (OpenRAM's model says so), where the flop model reads the old word.
    Chip select and write
    enable are active low; the write mask is byte-wise (ceil(width / 8)
    lanes) and all lanes are written. A macro deeper or wider than the
    memory is padded: the address and the data extended with zeros, the
    read data sliced.

    OpenRAM's read data is launched by the FALLING edge of the cycle that
    sampled the address (the liberty times dout against clk falling), so it
    is valid before the next rising edge, where the memory controller's
    read arbiter samples the flop model's registered loadData: the same
    cycle, half of it for the path from dout1 to the arbiter."""
    mname, words, mwidth = macro[0], int(macro[1]), int(macro[2])
    maddr = max(1, (words - 1).bit_length())
    masks = -(-mwidth // 8)
    return f"""
-- Synthesis view of {name}: the same entity as ../{name}.vhd, its body the
-- OpenRAM 1rw1r macro {mname} ({words} x {mwidth}, holding {size} x
-- {data_width}): the store on port 0, the load on port 1.
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
  component {mname}
    port (
      clk0   : in  std_logic;
      csb0   : in  std_logic;
      web0   : in  std_logic;
      wmask0 : in  std_logic_vector({masks} - 1 downto 0);
      addr0  : in  std_logic_vector({maddr} - 1 downto 0);
      din0   : in  std_logic_vector({mwidth} - 1 downto 0);
      dout0  : out std_logic_vector({mwidth} - 1 downto 0);
      clk1   : in  std_logic;
      csb1   : in  std_logic;
      addr1  : in  std_logic_vector({maddr} - 1 downto 0);
      dout1  : out std_logic_vector({mwidth} - 1 downto 0)
    );
  end component;
  signal csb0, web0, csb1 : std_logic;
  signal wmask0           : std_logic_vector({masks} - 1 downto 0);
  signal addr0, addr1     : std_logic_vector({maddr} - 1 downto 0);
  signal din0, dout0      : std_logic_vector({mwidth} - 1 downto 0);
  signal dout1            : std_logic_vector({mwidth} - 1 downto 0);
begin
  -- chip select and write enable are active low; every byte lane is written
  csb0   <= not storeEn;
  web0   <= not storeEn;
  wmask0 <= (others => '1');
  csb1   <= not loadEn;
  -- a macro deeper or wider than the memory: zeros above the memory's bits
  addr0  <= std_logic_vector(resize(unsigned(storeAddr), {maddr}));
  din0   <= std_logic_vector(resize(unsigned(storeData), {mwidth}));
  addr1  <= std_logic_vector(resize(unsigned(loadAddr), {maddr}));
  loadData <= dout1({data_width} - 1 downto 0);

  macro : {mname}
    port map (
      clk0   => clk,
      csb0   => csb0,
      web0   => web0,
      wmask0 => wmask0,
      addr0  => addr0,
      din0   => din0,
      dout0  => dout0,
      clk1   => clk,
      csb1   => csb1,
      addr1  => addr1,
      dout1  => dout1
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


def _gen_write_body(init_vals: List[int], reset_content: bool = False) -> str:
    """THE DECLARED CONTENT AS A RESET, when the target asks for it.

    A declared initial value is a simulator's and an FPGA bitstream's; a
    cell library has neither. Left as a declaration alone it is honoured in
    simulation and dropped on the way to cells, so the netlist that is
    verified and the netlist that could be fabricated hold different things
    at power-up. Measured on the picorv32 register file, 32 words of 32
    bits: all 1,330 of its flip-flops mapped to a cell with no reset pin,
    and the zeroes the model assumes came from a Verilog `initial` block
    that Verilator honours and silicon does not.

    With `reset_content`, the content is a constant, the declaration keeps
    it for the simulator, and the write resets to it: a mux in front of
    each flop and not one more register (on that register file, 219 cells
    and 26 ps). Without it the unit is exactly what it was, which is what an
    FPGA wants: there the bitstream loads the content and a reset would stop
    block RAM being inferred.

    Every memory this flow builds declares content -- a `memref.alloca`
    becomes a memory of zeros, and the flow reads a never-written word as
    zero -- so on a cell library every memory resets, zeros included. The
    empty case is kept for a caller that passes none.

    `_is_sram` treats all-zero content as no content, so a memory of zeros
    large enough for a macro gets an SRAM view that does not reset while its
    flop model here does. That view is what the macro is; the divergence is
    known and applies only under HDL_SRAM=1.
    """

    store = ("        ram(to_integer(unsigned(storeAddr))) <= storeData;\n"
             "      end if;")
    if not (reset_content and init_vals):
        return "      if (storeEn = '1') then\n" + store
    return ("      if (rst = '1') then\n"
            "        ram <= ram_init;\n"
            "      elsif (storeEn = '1') then\n" + store)


def _gen_intial_block(data_width: int, size: int, init_vals: List[int],
                      reset_content: bool = False):

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
    if not (reset_content and init_vals):
        return "signal ram : ram_type := (" + ",\n".join(named) + ");"
    # With the reset, the content is a constant so that the declaration and
    # the reset name one thing: the declaration is what a simulator honours,
    # the reset is what the cells implement. See `_gen_write_body`.
    return ("constant ram_init : ram_type := (" + ",\n".join(named) + ");\n"
            "  signal ram : ram_type := ram_init;")
