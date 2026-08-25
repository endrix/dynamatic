from generators.support.utils import data


def generate_queue(name, params):
    """`handshake.queue` -- an elastic FIFO that publishes how full it is.

    `size` on the output channel says how many tokens are queued, `space` on
    the input channel how many more it can take. Both are optional: a queue
    nobody queries is an ordinary FIFO, and SIZE_WIDTH/SPACE_WIDTH are zero.

    Both come off a COUNT REGISTER rather than being derived from the head and
    tail pointers. Two reasons. The pointers are ambiguous at equal values --
    empty and full look alike -- so a count needs a separate bit anyway. And
    registering the count is what keeps a consumer that steers on `space` from
    closing a combinational loop, its decision driving the `valid` that the
    `ready` behind `space` is answering.
    """
    num_slots = params["num_slots"]
    bitwidth = params["bitwidth"]
    size_width = params.get("size_width", 0)
    space_width = params.get("space_width", 0)

    ports = []
    if bitwidth > 0:
        ports.append(f"ins : in std_logic_vector({bitwidth} - 1 downto 0)")
    ports.append("ins_valid : in std_logic")
    ports.append("ins_ready : out std_logic")
    if space_width > 0:
        # Upstream on the input channel: published back to whoever writes.
        ports.append(
            f"ins_space : out std_logic_vector({space_width} - 1 downto 0)")
    if bitwidth > 0:
        ports.append(f"outs : out std_logic_vector({bitwidth} - 1 downto 0)")
    ports.append("outs_valid : out std_logic")
    ports.append("outs_ready : in std_logic")
    if size_width > 0:
        # Downstream on the output channel: published to whoever reads.
        ports.append(
            f"outs_size : out std_logic_vector({size_width} - 1 downto 0)")

    port_block = ";\n    ".join(ports)

    mem_decl = (f"  type FIFO_Memory is array (0 to {num_slots} - 1) of "
                f"std_logic_vector({bitwidth} - 1 downto 0);\n"
                f"  signal Memory : FIFO_Memory;\n") if bitwidth > 0 else ""

    write_proc = f"""
  -- write to the tail slot
  FifoWrite_proc : process (clk)
  begin
    if rising_edge(clk) then
      if WriteEn = '1' then
        Memory(Tail) <= ins;
      end if;
    end if;
  end process;

  outs <= Memory(Head);
""" if bitwidth > 0 else ""

    publish = []
    if size_width > 0:
        publish.append(
            f"  outs_size <= std_logic_vector(to_unsigned(Count, {size_width}));")
    if space_width > 0:
        publish.append(
            f"  ins_space <= std_logic_vector(to_unsigned({num_slots} - Count, "
            f"{space_width}));")
    publish_block = "\n".join(publish)

    return f"""
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Entity of queue, an elastic FIFO publishing its occupancy
entity {name} is
  port (
    clk : in std_logic;
    rst : in std_logic;
    {port_block}
  );
end entity;

-- Architecture of queue
architecture arch of {name} is

  signal ReadEn  : std_logic := '0';
  signal WriteEn : std_logic := '0';
  signal Tail    : natural range 0 to {num_slots} - 1;
  signal Head    : natural range 0 to {num_slots} - 1;
  -- Counts 0 to {num_slots} INCLUSIVE, so empty and full are distinguishable;
  -- the head and tail pointers alone are not.
  signal Count   : natural range 0 to {num_slots};
  signal Empty   : std_logic;
  signal Full    : std_logic;
{mem_decl}
begin

  Empty <= '1' when Count = 0 else '0';
  Full  <= '1' when Count = {num_slots} else '0';

  -- accept a token whenever there is room, or room is being made this cycle
  ins_ready  <= not Full or outs_ready;
  outs_valid <= not Empty;

  ReadEn  <= outs_ready and not Empty;
  WriteEn <= ins_valid and (not Full or outs_ready);

  -- One register, up on a write and down on a read; a simultaneous write and
  -- read leaves it alone.
  CountUpdate_proc : process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        Count <= 0;
      elsif WriteEn = '1' and ReadEn = '0' then
        Count <= Count + 1;
      elsif ReadEn = '1' and WriteEn = '0' then
        Count <= Count - 1;
      end if;
    end if;
  end process;

  TailUpdate_proc : process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        Tail <= 0;
      elsif WriteEn = '1' then
        Tail <= (Tail + 1) mod {num_slots};
      end if;
    end if;
  end process;

  HeadUpdate_proc : process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        Head <= 0;
      elsif ReadEn = '1' then
        Head <= (Head + 1) mod {num_slots};
      end if;
    end if;
  end process;
{write_proc}
{publish_block}
end architecture;
"""
