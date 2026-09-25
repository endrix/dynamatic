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

    `initial_tokens` is what the queue holds at reset, first out first: each
    token's bits at the data width, joined by commas ("none", or nothing, for
    none). The reset writes them to the first slots of the memory and starts
    the count at their number and the tail past them, so from reset the output
    is valid on the first of them, `size` counts them and `space` is the slots
    left -- the queue a dataflow network's channel is when it starts with
    tokens on it. A queue that starts empty is generated as it was.
    """
    num_slots = params["num_slots"]
    bitwidth = params["bitwidth"]
    size_width = params.get("size_width", 0)
    space_width = params.get("space_width", 0)
    initial = _initial_tokens(name, params.get("initial_tokens", ""),
                              num_slots, bitwidth)

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

    if initial:
        # The tokens held at reset are written by the reset, into the slots
        # the head reads first; the other slots are written before they are
        # read, as in a queue that starts empty.
        preload = "\n".join(f'        Memory({i}) <= "{bits}";'
                            for i, bits in enumerate(initial))
        write_proc = f"""
  -- write to the tail slot; the reset writes the tokens held at reset
  FifoWrite_proc : process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
{preload}
      elsif WriteEn = '1' then
        Memory(Tail) <= ins;
      end if;
    end if;
  end process;

  outs <= Memory(Head);
""" if bitwidth > 0 else ""
    else:
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
    # The count and the tail start past the tokens held at reset.
    count_reset = len(initial)
    tail_reset = len(initial) % num_slots

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

  -- accept a token whenever there is room. Not "or room is being made this
  -- cycle": that made ins_ready the consumer's outs_ready whenever the queue
  -- was full, a combinational path from the consumer's decision into the
  -- producer's, and on the CalPy picorv32 core the critical path ran that
  -- way across the network, from one actor's round through the queue into
  -- the next actor's. Registered, the ready ends here. A full queue takes
  -- its next token the cycle after one leaves and settles one below full at
  -- one token a cycle; the decoder networks are bit-exact at the same cycles.
  ins_ready  <= not Full;
  outs_valid <= not Empty;

  ReadEn  <= outs_ready and not Empty;
  WriteEn <= ins_valid and not Full;

  -- One register, up on a write and down on a read; a simultaneous write and
  -- read leaves it alone.
  CountUpdate_proc : process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        Count <= {count_reset};
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
        Tail <= {tail_reset};
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


def _initial_tokens(name, text, num_slots, bitwidth):
    """The tokens a queue holds at reset, as VHDL bit strings of `bitwidth`
    bits, from the comma-separated bit strings HandshakeToHW hands over.
    Refuses what the RTL could not hold: more tokens than slots, a token on a
    dataless channel, a token of another width or not in binary."""
    text = str(text).strip()
    if not text or text == "none":
        return []
    tokens = [t.strip() for t in text.split(",")]
    if len(tokens) > num_slots:
        raise ValueError(
            f"queue {name}: {len(tokens)} initial tokens but {num_slots} slots")
    if bitwidth == 0:
        raise ValueError(
            f"queue {name}: initial tokens on a dataless channel")
    for t in tokens:
        if len(t) != bitwidth or any(ch not in "01" for ch in t):
            raise ValueError(
                f"queue {name}: initial token '{t}' is not {bitwidth} bits")
    return tokens
