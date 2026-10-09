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
    # and port map: `fakeram` (FakeRAM2.0, the default: a macro of any size
    # from the name pattern `sram_name`, a format with {size}, {width} and
    # {addr}) or `openram` (OpenRAM's 1rw1r macros, one read-write and one
    # read port, fixed sizes). `sram_ports` is how many ports the memory
    # needs (the RAM's PORTS parameter, from the front end's
    # `handshake.ram_ports`; 2 when it is not given): under `fakeram`, 1 is
    # the one-port RAM (fakeram7_{size}x{width} by default) and 2 the
    # dual-port one (fakeram7_dp_{size}x{width}), the store on one port and
    # the load on the other. Two ports serve a load and a store in one
    # cycle, which the flop model does and the memory controller issues
    # where nothing orders them (twice on one of MPEG-4 texture's RAMs, its
    # output wrong with a one-port view); one is enough where something
    # does. OpenRAM's macros have the two ports whatever the number.
    # `sram_macros` lists the
    # macros on hand as (name, words, width[, area]); the smallest one that
    # holds the memory is taken, padded with zeros where it is deeper or
    # wider, and a memory no macro holds is tiled: rows x columns of one
    # macro, the kind of least total area (_pick_tiling). FakeRAM generates
    # a macro of the memory's own size from the name pattern and reads no
    # list: its view is one macro, never padded. Every view reads a word
    # never stored since reset as zero, its declared content
    # (_with_written_bits). See _generate_ram_sram, _generate_ram_sram_dp,
    # _generate_ram_openram and _generate_ram_openram_tiled.
    sram_threshold = params.get("sram_threshold", 0)
    sram_interface = params.get("sram_interface", "fakeram")
    sram_ports = int(params.get("sram_ports") or 2)
    if sram_ports not in (1, 2):
        raise ValueError(f"sram_ports {sram_ports} is not 1 or 2")
    sram_name = params.get("sram_name") or (
        "fakeram7_{size}x{width}" if sram_ports == 1 else "fakeram7_dp_{size}x{width}")
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
        gen = _generate_ram_sram if sram_ports == 1 else _generate_ram_sram_dp
        view = gen(name, data_width, addr_width, size, macro)
    elif (macro := _pick_macro(sram_macros, size, data_width)) is not None:
        view = _generate_ram_openram(name, data_width, addr_width, size, macro)
    else:
        tiling = _pick_tiling(sram_macros, size, data_width)
        if tiling is None:
            sys.stderr.write(f"{name}: no macro in sram_macros holds {size} x {data_width} "
                             "and none tiles it; the memory stays flops\n")
            return code
        view = _generate_ram_openram_tiled(name, data_width, addr_width, size, *tiling)
    return code, {f"sram/{name}.vhd": _with_written_bits(view, size, data_width)}


def _with_written_bits(view: str, size: int, data_width: int) -> str:
    """A view that reads a word never stored since reset as zero.

    A view is written only for a memory whose declared content is all
    zeros (_is_sram), and a program may load a word before it stores one,
    relying on that zero: MPEG-4 texture's 832 x 13 RAM in the inverse AC
    prediction loads seven words before any store reaches them. The flop
    model has the zero from its reset (reset_content); a macro powers up
    with whatever its bitcells hold, and with the macros' contents random
    the texture's output was wrong (119 to 128 values in three seeds).

    So the view keeps one bit a word beside the macro, in flip-flops: all
    cleared by the reset, set by a store to the word. A load registers its
    word's bit at the edge that samples its address, as the macro registers
    the word, and loadData is the macro's word when the bit was set and
    zero when it was not. A load and a store to one word in one cycle read
    the bit from before the store, as they read the old word. `size`
    flip-flops and a `size`-way mux, no cycle: the bit is ready when the
    word is."""
    arch = view.index("architecture arch of")
    head, body = view[:arch], view[arch:]
    # the view's own drive of loadData goes to `raw`, masked below
    body = body.replace("loadData", "raw")
    decl = (f"  signal raw     : std_logic_vector({data_width} - 1 downto 0);\n"
            f"  signal written : std_logic_vector({size} - 1 downto 0);\n"
            "  signal word_written : std_logic;\n")
    logic = f"""
  -- a word never stored since reset reads as zero, its declared content
  written_proc : process(clk)
  begin
    if rising_edge(clk) then
      if (rst = '1') then
        written      <= (others => '0');
        word_written <= '0';
      else
        if (loadEn = '1') then
          word_written <= written(to_integer(unsigned(loadAddr)));
        end if;
        if (storeEn = '1') then
          written(to_integer(unsigned(storeAddr))) <= '1';
        end if;
      end if;
    end if;
  end process;
  loadData <= raw when word_written = '1' else (others => '0');
"""
    at = body.index("\nbegin\n")
    body = body[:at] + "\n" + decl.rstrip("\n") + body[at:]
    end = body.rindex("end architecture;")
    return head + body[:end] + logic.lstrip("\n") + body[end:]


def _pick_macro(macros, size: int, width: int):
    """The smallest macro of `macros`, (name, words, width) triples, that
    holds a memory of `size` words of `width` bits: the fewest words, then
    the narrowest; None when no macro does (or the list is empty)."""
    fits = [tuple(m) for m in macros if int(m[1]) >= int(size) and int(m[2]) >= int(width)]
    if not fits:
        return None
    return min(fits, key=lambda m: (int(m[1]), int(m[2])))


def _pick_tiling(macros, size: int, width: int):
    """A memory no single macro holds, as `rows` x `cols` copies of one macro
    of `macros`: rows = ceil(size / words) tiles in depth, cols = ceil(width /
    macro width) in width. Returns (macro, rows, cols), or None when no macro
    tiles it (the list is empty, or no macro has a power-of-two depth: the
    tile is the address's top bits, so a tile's depth must be a power of
    two).

    The kind taken is the one of least TOTAL MACRO AREA, rows x cols x the
    macro's area, then the fewest macros: a macro is 0.1 to 0.7 mm^2 on
    sky130, the decode around it a few hundred cells, so area is what a
    tiling costs and the count is the tie-break. The area is a triple's
    optional fourth element (the liberty's `area`); without it, its
    capacity, words x width -- the bits it spends, padding included. The
    proxy ignores a macro's periphery, which makes a small macro cost more
    per bit than a large one: on OpenRAM's sky130 macros it agrees with the
    liberties' areas on MPEG-4 texture's 832 x 13 (13 x 44x64, 36,608 bits
    and 1.37 mm^2, before 4 x 64x256, 65,536 bits and 1.68 mm^2) but not on
    1,024 x 200 (it takes 80 x 44x64, 8.5 mm^2, where 8 x 128x256 is 5.8
    mm^2). A table meant for large memories carries the areas."""
    best = None
    for m in macros:
        words, mwidth = int(m[1]), int(m[2])
        if words < 1 or mwidth < 1 or words & (words - 1):
            continue
        rows, cols = -(-int(size) // words), -(-int(width) // mwidth)
        area = float(m[3]) if len(m) > 3 else words * mwidth
        key = (rows * cols * area, rows * cols, words, mwidth)
        if best is None or key < best[0]:
            best = (key, (tuple(m[:3]), rows, cols))
    return None if best is None else best[1]


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
    such cycles), but MPEG-4 texture's does, twice on one RAM, and its output
    is wrong with this view: a design that does needs two ports, the
    dual-port view (_generate_ram_sram_dp) or the OpenRAM one."""
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
end architecture;\n"""


def _generate_ram_sram_dp(
    name: str,
    data_width: int,
    addr_width: int,
    size: int,
    macro: tuple,
):
    """The synthesis view on a FakeRAM2.0 dual-port RAM (two read-write
    ports, `a` and `b`: we, addr, din, dout and clk each): the entity of
    _generate_ram, its body a component instantiation with the store on port
    a and the load on port b, both clocked by the design's clock. A load and
    a store in ONE cycle are both served, as the flop model serves them; at
    the same address the load reads the old word, as in the flop model.

    The macro has no enable: port b reads loadAddr at every rising edge and
    its registered dout is the flop model's loadData in the cycle after a
    load, which is when the memory controller's read arbiter samples it
    (sel_prev in read_data_signals); between loads the flop model holds its
    last word and the macro reads whatever loadAddr is, a word the arbiter
    does not sample. Port b never writes (we_b low, din_b zero) and port a's
    dout is left open."""
    macro = macro[0]
    return f"""
-- Synthesis view of {name}: the same entity as ../{name}.vhd, its body the
-- dual-port SRAM macro {macro} ({size} x {data_width}): the store on port
-- a, the load on port b.
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
      we_a   : in  std_logic;
      addr_a : in  std_logic_vector({addr_width} - 1 downto 0);
      din_a  : in  std_logic_vector({data_width} - 1 downto 0);
      dout_a : out std_logic_vector({data_width} - 1 downto 0);
      clk_a  : in  std_logic;
      we_b   : in  std_logic;
      addr_b : in  std_logic_vector({addr_width} - 1 downto 0);
      din_b  : in  std_logic_vector({data_width} - 1 downto 0);
      dout_b : out std_logic_vector({data_width} - 1 downto 0);
      clk_b  : in  std_logic
    );
  end component;
begin
  macro : {macro}
    port map (
      we_a   => storeEn,
      addr_a => storeAddr,
      din_a  => storeData,
      dout_a => open,
      clk_a  => clk,
      we_b   => '0',
      addr_b => loadAddr,
      din_b  => (others => '0'),
      dout_b => loadData,
      clk_b  => clk
    );
end architecture;\n"""


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
end architecture;\n"""


def _generate_ram_openram_tiled(
    name: str,
    data_width: int,
    addr_width: int,
    size: int,
    macro: tuple,
    rows: int,
    cols: int,
):
    """The OpenRAM view of a memory no single macro holds: `rows` x `cols`
    copies of the 1rw1r macro `macro`, from _pick_tiling. Each macro keeps
    _generate_ram_openram's port map -- the store on the read-write port 0,
    the load on the read port 1 -- so a load and a store in one cycle are
    both served here too, wherever they fall.

    DEPTH. A tile holds `words` (a power of two, 2^k) consecutive words: the
    address's low k bits are the macro's address, its top bits the tile. A
    store selects one row: only that row's port-0 chip select goes low
    (every macro sees the same address, data and write enable, and a macro
    not selected ignores them). A load selects one row's port 1 the same
    way. The read data is launched by the falling edge of the cycle that
    sampled the load's address, and the reader samples it at the next
    rising edge (see _generate_ram_openram), so the row it comes from is the
    one that load selected: a register, `rd_row`, takes the one-hot row
    select at the load's rising edge, and loadData is the AND-OR of each
    row's dout1 with its bit. The register changes only on a load, so the
    select stays put through the half cycle in which dout1 settles; one-hot
    keeps the path from dout1 to loadData one AND and an OR tree, no
    decoder, inside the half cycle the falling edge leaves. A row index past
    the last tile (a memory of 832 words on 13 tiles of 64 has 16 row codes)
    selects no row: no address of the memory reaches it.

    WIDTH. A memory wider than the macro is `cols` macros side by side in
    each row, column c holding bits c*width .. (c+1)*width - 1, the last
    column padded with zeros; they share every control.

    The flop model's behaviour is kept where the memory controller reads it:
    loadData the cycle after the load (its read arbiter samples read data
    only then, sel_prev in read_data_signals, and holds it itself). In the
    cycles between loads the flop model holds the last word and the macros'
    model drives X; nothing samples it. A load and a store at the same
    address in one cycle read undefined data, as on one macro."""
    mname, words, mwidth = macro[0], int(macro[1]), int(macro[2])
    k = (words - 1).bit_length()
    maddr = max(1, k)
    masks = -(-mwidth // 8)
    rowbits = addr_width - k
    total = cols * mwidth

    def row_of(addr):
        if rows == 1:
            return None
        return f"unsigned({addr}({addr_width} - 1 downto {k}))"

    if rows == 1:
        csb0 = "  csb0(0) <= not storeEn;\n"
        csb1 = "  csb1(0) <= not loadEn;\n"
        addr0 = f"  addr0  <= std_logic_vector(resize(unsigned(storeAddr), {maddr}));\n"
        addr1 = f"  addr1  <= std_logic_vector(resize(unsigned(loadAddr), {maddr}));\n"
        select = f"  loadData <= dout1(0)({data_width} - 1 downto 0);\n"
        rd_decl = ""
    else:
        csb0 = (f"  st_row <= {row_of('storeAddr')};\n"
                f"  ld_row <= {row_of('loadAddr')};\n"
                f"  rows_sel : for r in 0 to {rows} - 1 generate\n"
                f"    csb0(r) <= '0' when storeEn = '1' and st_row = r else '1';\n"
                f"    csb1(r) <= '0' when loadEn = '1' and ld_row = r else '1';\n"
                f"  end generate;\n")
        csb1 = ""
        addr0 = f"  addr0  <= storeAddr({k} - 1 downto 0);\n"
        addr1 = f"  addr1  <= loadAddr({k} - 1 downto 0);\n"
        select = f"""  -- the row the load selected, one-hot, held until the next load
  rd_row_reg : process(clk)
  begin
    if rising_edge(clk) then
      if loadEn = '1' then
        rd_row <= not csb1;
      end if;
    end if;
  end process;

  -- loadData: the AND-OR of each row's read data with its select bit
  read_mux : process(rd_row, dout1)
    variable acc : std_logic_vector({total} - 1 downto 0);
  begin
    acc := (others => '0');
    for r in 0 to {rows} - 1 loop
      if rd_row(r) = '1' then
        acc := acc or dout1(r);
      end if;
    end loop;
    loadData <= acc({data_width} - 1 downto 0);
  end process;\n"""
        rd_decl = (f"  signal st_row, ld_row     : unsigned({rowbits} - 1 downto 0);\n"
                   f"  signal rd_row             : std_logic_vector({rows} - 1 downto 0);\n")
    return f"""
-- Synthesis view of {name}: the same entity as ../{name}.vhd, its body
-- {rows} x {cols} OpenRAM 1rw1r macros {mname} ({words} x {mwidth} each,
-- {rows * words} x {total} in all, holding {size} x {data_width}): {rows} row(s) in
-- depth, {cols} column(s) in width. Every macro takes the store on port 0
-- and the load on port 1; a row's chip selects are its address's.
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
  type row_data is array (0 to {rows} - 1) of std_logic_vector({total} - 1 downto 0);
  signal csb0, csb1         : std_logic_vector({rows} - 1 downto 0);
  signal web0               : std_logic;
  signal wmask0             : std_logic_vector({masks} - 1 downto 0);
  signal addr0, addr1       : std_logic_vector({maddr} - 1 downto 0);
  signal din0               : std_logic_vector({total} - 1 downto 0);
  signal dout0, dout1       : row_data;
{rd_decl}begin
  -- chip select and write enable are active low; every byte lane is written;
  -- only the row the address names is selected
  web0   <= not storeEn;
  wmask0 <= (others => '1');
{csb0}{csb1}  -- the address within a tile; the data padded with zeros to the columns
{addr0}{addr1}  din0   <= std_logic_vector(resize(unsigned(storeData), {total}));
{select}
  tiles : for r in 0 to {rows} - 1 generate
    columns : for c in 0 to {cols} - 1 generate
      macro : {mname}
        port map (
          clk0   => clk,
          csb0   => csb0(r),
          web0   => web0,
          wmask0 => wmask0,
          addr0  => addr0,
          din0   => din0((c + 1) * {mwidth} - 1 downto c * {mwidth}),
          dout0  => dout0(r)((c + 1) * {mwidth} - 1 downto c * {mwidth}),
          clk1   => clk,
          csb1   => csb1(r),
          addr1  => addr1,
          dout1  => dout1(r)((c + 1) * {mwidth} - 1 downto c * {mwidth})
        );
    end generate;
  end generate;
end architecture;\n"""


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
