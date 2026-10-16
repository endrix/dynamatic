# The units of a generator RTL config (data/rtl-config-vhdl.json), as
# export-rtl instantiates them.
#
# A circuit exported by export-rtl is made of these generators' RTL, not of
# the hand-written files rtl-config-vhdl-vivado.json lists: a fork in an
# exported design is `vhdl-unit-generator.py -t fork`, written at its size and
# width. A model measured on the hand-written files describes RTL no exported
# design contains, so a characterization for a design flow reads this config.
#
# A generator entry has no generics. export-rtl fills its command's variables
# -- from the operation's attributes (the entry's `parameters`: SIZE,
# PREDICATE, BUFFER_TYPE, ...) and from its port types (BITWIDTH,
# DATA_BITWIDTH, ..., and EXTRA_SIGNALS, which no entry declares) -- and the
# generator bakes them into the RTL. Each point of the sweep is then a unit of
# its own, generated and characterized at the one width it was written at,
# the way the sequential divider and multiplier are (utils.impl_variants).

import math
import re

from utils import parameters_ranges

# The variables a command names that are not the unit's: where to write it.
PATH_VARIABLES = ("DYNAMATIC", "OUTPUT_DIR", "MODULE_NAME")

# What export-rtl writes for a channel that carries no extra signal
# (RTL.cpp's serializeExtraSignals); the shell that runs the command removes
# the quotes, and the generator reads a dictionary.
NO_EXTRA_SIGNALS = "'{}'"

# The values an attribute is swept over, for an entry that declares it. A
# unit name has one entry in the model, so the delays are reduced over the
# values with the maximum, as over the six hand-written buffers: the model
# never says a path is shorter than some instance makes it.
#
#   SIZE       the base entry's size, the one the hand-written
#              characterization used (parameters_ranges); the other sizes
#              are entries of their own (SIZES below).
#   PREDICATE  every integer comparison: an equality is a tree of XORs, an
#              order is a carry chain, and both are `handshake.cmpi`.
#   TEHB       a mux or merge with and without its output buffer.
#   IMPL       the implementation named after the unit: the pipelined one.
#              The sequential divider and multiplier are models of their own
#              (utils.impl_variants), and an entry that asks for IMPL
#              "sequential" is theirs.
#   STEP       unused by a pipelined multiplier.
ATTRIBUTE_VALUES = {
    "SIZE": parameters_ranges["SIZE"],
    "PREDICATE": ["eq", "ne", "ult", "ule", "ugt", "uge",
                  "slt", "sle", "sgt", "sge"],
    "TEHB": [0, 1],
    "IMPL": ["pipelined"],
    "STEP": [1],
}

# The sizes a unit with a SIZE attribute is characterized at, each an entry
# `<name>.size.<N>` of its own: a fork's ready is an AND over its outputs and
# a mux's data a select over its inputs, so the delays grow with the
# size, and a design's forks reach two hundred outputs. TimingDatabase's
# getModel times an op by the smallest size at or above its own. Past the
# base size, a unit is written at the widths SIZED_WIDTHS only: a width is
# also looked up at the smallest one at or above it, and every size times
# the sweep's widths would be most of the run.
SIZES = [2, 3, 4, 8, 16, 32, 64, 128, 256]
SIZED_WIDTHS = [1, 8, 32, 64]


def size_key(unit_name, size):
    """The model key of a unit's entry at one size."""
    return f"{unit_name}.size.{size}"


def base_unit(key):
    """The unit a model key is an entry of: `handshake.fork.size.8` is
    `handshake.fork`'s."""
    return re.sub(r"\.size\.\d+$", "", key)


# A buffer's type decides its slots and its data-to-valid latency, which the
# buffer operation's verifier holds to (HandshakeOps.cpp, BufferOp::verify),
# so the three are swept together: the six types the hand-written
# characterization had a file for, at the depth it used for a FIFO.
BUFFER_CONFIGS = [
    {"BUFFER_TYPE": "ONE_SLOT_BREAK_DV", "NUM_SLOTS": 1, "DV_LATENCY": 1},
    {"BUFFER_TYPE": "ONE_SLOT_BREAK_R", "NUM_SLOTS": 1, "DV_LATENCY": 0},
    {"BUFFER_TYPE": "ONE_SLOT_BREAK_DVR", "NUM_SLOTS": 1, "DV_LATENCY": 1},
    {"BUFFER_TYPE": "FIFO_BREAK_NONE", "NUM_SLOTS": 2, "DV_LATENCY": 0},
    {"BUFFER_TYPE": "FIFO_BREAK_DV", "NUM_SLOTS": 2, "DV_LATENCY": 1},
    {"BUFFER_TYPE": "SHIFT_REG_BREAK_DV", "NUM_SLOTS": 2, "DV_LATENCY": 2},
]
BUFFER_ATTRIBUTES = ("BUFFER_TYPE", "NUM_SLOTS", "DV_LATENCY")


def type_variables(unit_name, width, size):
    """
    The variables export-rtl derives from a unit's port types
    (RTLMatch::registerParameters in lib/Support/RTL/RTL.cpp), for a unit
    whose data channels carry `width` bits.

    Args:
        unit_name (str): the operation, `handshake.fork`.
        width (int): the data width.
        size (int): the number of inputs or outputs a sized unit has.

    Returns:
        dict: variable name -> value.
    """
    index = max(1, math.ceil(math.log2(size))) if size > 1 else 1
    if unit_name in ("handshake.mux", "handshake.control_merge"):
        return {"DATA_BITWIDTH": width, "INDEX_BITWIDTH": index}
    if unit_name in ("handshake.load", "handshake.store"):
        return {"DATA_BITWIDTH": width,
                "ADDR_BITWIDTH": parameters_ranges["ADDR_TYPE"][0]}
    return {"BITWIDTH": width}


def substitute(command, variables):
    """
    Fill a generator command's variables, `$NAME` or `${NAME}`.

    export-rtl substitutes them with one regular expression per name; the
    longest names go first here, and a name only matches as a whole word, so
    that `$SIZE` cannot eat the start of `$SIZE_WIDTH`.

    Args:
        command (str): the entry's generator command.
        variables (dict): name -> value.

    Returns:
        str: the command, with every variable named in `variables` filled.
    """
    for name in sorted(variables, key=len, reverse=True):
        command = re.sub(r"\$\{?" + re.escape(name) + r"\}?(?![A-Za-z0-9_])",
                         str(variables[name]).replace("\\", "\\\\"), command)
    return command


def command_variables(command):
    """The unit's variables a generator command names (not the paths)."""
    names = set(re.findall(r"\$\{?([A-Za-z_][A-Za-z0-9_]*)", command))
    return names - set(PATH_VARIABLES)


# The variables only export-rtl's reading of the port types fills.
TYPE_VARIABLES = {"BITWIDTH", "DATA_BITWIDTH", "INDEX_BITWIDTH",
                  "ADDR_BITWIDTH", "EXTRA_SIGNALS"}


def bakes_types(entry):
    """
    Whether an entry is a generator that writes the unit at its port types.

    Such an entry has no width generic to sweep in a wrapper. The generators
    the hand-written config names (rtl-cmpi-generator and the like) copy a
    file with generics and fill only the predicate, and are not this; nor are
    the sequential units of utils.impl_variants, which say their own widths.
    """
    if "generic" in entry or "bitwidths" in entry or not entry.get("generator"):
        return False
    return bool(command_variables(entry["generator"]) & TYPE_VARIABLES)


def reference_latency(latency_table):
    """
    The cycles a reference model gives a unit: the operation's LATENCY
    attribute, which the compiler sets from the same table. The table maps a
    retiming path, then a width, then a delay to cycles; a pipelined unit has
    one value.

    Args:
        latency_table (dict): the unit's `latency` entry, or None.

    Returns:
        int: the cycles, 0 for a unit with no table.
    """
    cycles = [c for by_width in (latency_table or {}).values()
              for by_delay in by_width.values() for c in by_delay.values()]
    return int(max(cycles)) if cycles else 0


def entry_matches(entry, attributes):
    """
    Whether an entry is the one export-rtl would pick for these attributes:
    every parameter it constrains with `eq` has that value.
    """
    for param in entry.get("parameters", []):
        if "eq" in param and str(attributes.get(param["name"])) != str(param["eq"]):
            return False
    return True


def points(entries, widths, latency_table=None, sizes=None):
    """
    Every instance of a unit the sweep characterizes.

    Args:
        entries (list): the config's entries for one unit name, in order
            (export-rtl takes the first that matches).
        widths (list): the data widths to write it at.
        latency_table (dict): the unit's latency in the reference model, for
            a unit with a LATENCY attribute.
        sizes (list): the sizes to write a unit with a SIZE attribute at;
            the base size alone when None. Past the base size, the widths
            are SIZED_WIDTHS.

    Returns:
        list: (entry, variables, width) per instance; `variables` fills the
            entry's command.
    """
    unit_name = entries[0]["name"]
    declared = []
    for entry in entries:
        for param in entry.get("parameters", []):
            if param["name"] not in declared:
                declared.append(param["name"])

    # The attribute combinations: buffers' coupled triples, then the product
    # of every other declared attribute's values.
    combos = [{}]
    if any(name in BUFFER_ATTRIBUTES for name in declared):
        combos = [dict(config) for config in BUFFER_CONFIGS]
    for name in declared:
        if name in BUFFER_ATTRIBUTES:
            continue
        if name == "LATENCY":
            values = [reference_latency(latency_table)]
        elif name == "SIZE" and sizes:
            values = sizes
        else:
            assert name in ATTRIBUTE_VALUES, \
                f"{unit_name}: no values to sweep its attribute {name} over"
            values = ATTRIBUTE_VALUES[name]
        combos = [dict(combo, **{name: value})
                  for combo in combos for value in values]

    result = []
    for attributes in combos:
        entry = next((e for e in entries if entry_matches(e, attributes)), None)
        if entry is None:
            continue
        size = int(attributes.get("SIZE", ATTRIBUTE_VALUES["SIZE"][0]))
        point_widths = widths if size in ATTRIBUTE_VALUES["SIZE"] else SIZED_WIDTHS
        for width in point_widths:
            variables = dict(attributes)
            variables.update(type_variables(
                unit_name, width, int(attributes.get("SIZE", 1))))
            variables["EXTRA_SIGNALS"] = NO_EXTRA_SIGNALS
            missing = command_variables(entry["generator"]) - set(variables)
            assert not missing, f"{unit_name}: nothing fills {sorted(missing)}"
            result.append((entry, variables, width))
    return result
