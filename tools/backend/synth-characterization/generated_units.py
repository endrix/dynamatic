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

from utils import parameters_ranges, dataless_units

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
#   KILL_DROP  a load with and without the count of the words it drops on a
#              kill: another circuit (HandshakeToHW sets it on a load in a
#              kill domain), an entry of its own (VARIANT_KEYS), not reduced
#              into the base entry, which stays the plain load every other
#              design has.
#   KILL_AT_VALID  a commit whose kill comes when its token is first offered
#              (a flip-flop more, the kill from the valid alone) and the
#              transfer's: another circuit, an entry of its own as KILL_DROP's
#              (`handshake.commit.at_valid`).
ATTRIBUTE_VALUES = {
    "SIZE": parameters_ranges["SIZE"],
    "PREDICATE": ["eq", "ne", "ult", "ule", "ugt", "uge",
                  "slt", "sle", "sgt", "sge"],
    "TEHB": [0, 1],
    "IMPL": ["pipelined"],
    "STEP": [1],
    "KILL_DROP": [0, 1],
    "KILL_AT_VALID": [0, 1],
}

# The attributes that, set, make a point another circuit with an entry of its
# own, `<name>.<suffix>`, rather than one more instance the base entry
# reduces over: attribute -> suffix.
VARIANT_KEYS = {
    "KILL_DROP": "kill_drop",
    "KILL_AT_VALID": "at_valid",
}


def variant_key(unit_name, variables):
    """The model key of a point that VARIANT_KEYS sends to an entry of its
    own, or None for a point of the base entry."""
    for name, suffix in VARIANT_KEYS.items():
        if int(variables.get(name, 0) or 0):
            return f"{unit_name}.{suffix}"
    return None


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


# THE RACE (`handshake.race`) is written at a structure, not at a size: its
# CANDIDATES name what each candidate reads and after whom it comes. An entry
# `handshake.race.size.<N>` times a race of at most N inputs (tokens and
# flags together) and N candidates (TimingDatabase's getUnitSize takes the
# larger of the two: each shape below has N inputs and at most N
# candidates), so each size is characterized at the nests a lowering makes
# of N inputs, and the model keeps the maximum over them, as over any unit's
# instances: a chain of priorities over one flag each (the deepest `after`),
# an F of N guards (the widest tie between winners), a guard over every flag
# (the widest AND), a chain of priorities over tokens (the hold's P over a
# settled network, at any width), and a mixed nest -- a token first, then
# guards over two flags, one of them negated, in turn P and F, as the
# per-state decisions of picorv32's Cpu are. A nest whose flag candidates
# need more distinct payloads than the width holds is not written at that
# width (each shape's payloads are distinct and non-zero; alternatives, two
# candidates of one payload, add candidates and no input, and are not
# characterized apart: getUnitSize counts them). The sizes go to 128:
# TimingDatabase times a larger op by the largest entry, a lower bound for
# it, and the cut and the placer would take such a race for fitting where
# it may not.
RACE_UNIT = "handshake.race"
RACE_SIZES = [2, 3, 4, 8, 16, 32, 64, 128]


def race_shapes(size):
    """The nests of `size` inputs the race is characterized at: name ->
    (tokens, flags, candidates as dicts with payload rank or token, flags,
    unless, after). A flag candidate's payload is given as its rank among the
    flag candidates (0, 1, ...), made a value at a width by race_encoding."""
    shapes = {}
    n = size
    # P(g(f0), P(g(f1), ...)): candidate k after every one before it
    shapes["chain"] = (0, n, [{"rank": k, "flags": [k], "unless": [],
                               "after": list(range(k))} for k in range(n)])
    # F(g(f0), ..., g(fn-1)): no order
    shapes["f"] = (0, n, [{"rank": k, "flags": [k], "unless": [], "after": []}
                          for k in range(n)])
    # one guard over every flag, the last negated
    shapes["guard"] = (0, n, [{"rank": 0, "flags": list(range(n - 1)) if n > 1 else [0],
                               "unless": [n - 1] if n > 1 else [], "after": []}])
    # P(t0, P(t1, ...)): the priority chain over tokens
    shapes["tokens"] = (n, 0, [{"token": k, "flags": [], "unless": [],
                                "after": list(range(k))} for k in range(n)])
    # a token, then guards over two flags in turn P and F
    flags = n - 1
    cands = [{"token": 0, "flags": [], "unless": [], "after": []}]
    done = [0]
    f, rank = 0, 0
    while f < flags:
        group = []
        for _ in range(2):  # an F of two guards, after everything before
            if f >= flags:
                break
            unless = [f + 1] if f + 1 < flags else []
            group.append({"rank": rank, "flags": [f], "unless": unless,
                          "after": list(done)})
            rank += 1
            f += 2 if unless else 1
        cands.extend(group)
        done += list(range(len(cands) - len(group), len(cands)))
    if flags > 0:
        shapes["mixed"] = (1, flags, cands)
    return shapes


def race_encoding(cands, width):
    """CANDIDATES (RaceOp::getCandidatesEncoding) of a shape at `width`: a
    flag candidate's payload one-hot where the width holds one bit each, its
    rank + 1 otherwise; None when the width cannot tell the candidates
    apart."""
    ranks = [c["rank"] for c in cands if "rank" in c]
    if ranks and len(ranks) > 2 ** width - 1:
        return None
    onehot = len(ranks) <= width
    parts = []
    for c in cands:
        if "token" in c:
            field = f"t{c['token']}"
        else:
            field = f"p{(1 << c['rank']) if onehot else c['rank'] + 1}"
        for letter, key in (("f", "flags"), ("u", "unless"), ("a", "after")):
            if c[key]:
                field += f":{letter}" + ",".join(map(str, c[key]))
        parts.append(field)
    return "/".join(parts)


def race_points(entries, widths, sizes):
    """Every race the sweep characterizes: (entry, variables, width) per
    shape, size and width, `SIZE` its inputs (which keys its entry), `SHAPE`
    the nest's name (which the command does not read). A form the
    configuration pins with `eq` is written at each point when VARIANT_KEYS
    sends it to an entry of its own, and skipped otherwise: its points would
    be reduced into the plain race's entry, moving it by synthesis noise.
    REOPEN_AFTER_TAKEN, a race whose inputs reopen only after its answer was
    taken, is such a form -- it is timed by the plain race's entry
    (TimingDatabase::getModel) -- so only the plain race is characterized."""
    result = []
    for entry in entries:
        fixed = {param["name"]: param["eq"]
                 for param in entry.get("parameters", []) if "eq" in param}
        if any(name not in VARIANT_KEYS for name in fixed):
            continue
        for size in sizes:
            point_widths = widths if size == sizes[0] else SIZED_WIDTHS
            for name, (nt, nf, cands) in race_shapes(size).items():
                for width in point_widths:
                    encoding = race_encoding(cands, width)
                    if encoding is None:
                        continue
                    variables = dict(fixed)
                    variables.update({"SIZE": size, "SHAPE": name,
                                      "SIZE_TOKENS": nt, "SIZE_FLAGS": nf,
                                      "CANDIDATES": encoding,
                                      "BITWIDTH": width,
                                      "EXTRA_SIGNALS": NO_EXTRA_SIGNALS})
                    missing = command_variables(entry["generator"]) - set(variables)
                    assert not missing, f"{RACE_UNIT}: nothing fills {sorted(missing)}"
                    result.append((entry, variables, width))
    return result


def size_key(unit_name, size):
    """The model key of a unit's entry at one size."""
    return f"{unit_name}.size.{size}"


def base_size(entries):
    """
    The size a sized unit's base entry is characterized at, with every width:
    parameters_ranges' (2), or the smallest the unit has when its entry says
    a smaller one is legal (`lb`): a stand-in takes one kill or more, and one
    is what most have.
    """
    size = ATTRIBUTE_VALUES["SIZE"][0]
    for entry in entries:
        for param in entry.get("parameters", []):
            if param["name"] == "SIZE" and "lb" in param:
                size = min(size, int(param["lb"]))
    return size


def sizes_of(entries):
    """The sizes a sized unit is characterized at: its base size, then every
    larger one of SIZES."""
    base = base_size(entries)
    return [base] + [size for size in SIZES if size > base]


def base_unit(key):
    """The unit a model key is an entry of: `handshake.fork.size.8` is
    `handshake.fork`'s."""
    return re.sub(r"\.size\.\d+$", "", key)


# A buffer's six types are one unit, `handshake.buffer`, whose base entry
# reduces over them; each type has an entry of its own too,
# `handshake.buffer.ONE_SLOT_BREAK_R`, since the types share no path: an
# opaque slot registers its data and valid, a transparent one passes them
# through a multiplexer its register selects.
def type_key(unit_name, buffer_type):
    """The model key of a buffer type's entry."""
    return f"{unit_name}.{buffer_type}"


def type_base(key):
    """The unit a buffer type's entry is an entry of: `handshake.buffer.
    ONE_SLOT_BREAK_R` is `handshake.buffer`'s."""
    return re.sub(r"\.(ONE_SLOT|FIFO|SHIFT_REG)_[A-Z_]+$", "", key)


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
    # A unit with no data takes its size alone (`kill_or`): its generator
    # writes it at that size all the same.
    return bool(command_variables(entry["generator"]) & (TYPE_VARIABLES | {"SIZE"}))


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
            the base size alone when None. Past the base size (base_size),
            the widths are SIZED_WIDTHS.

    Returns:
        list: (entry, variables, width) per instance; `variables` fills the
            entry's command.
    """
    unit_name = entries[0]["name"]
    if unit_name == RACE_UNIT:
        return race_points(entries, widths, sizes or RACE_SIZES[:1])
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
        elif name == "SIZE":
            values = [base_size(entries)]
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
        size = int(attributes.get("SIZE", base_size(entries)))
        point_widths = widths if size == base_size(entries) else SIZED_WIDTHS
        if unit_name in dataless_units:
            # no data: one width at every size
            point_widths = widths
        for width in point_widths:
            variables = dict(attributes)
            variables.update(type_variables(
                unit_name, width, int(attributes.get("SIZE", 1))))
            variables["EXTRA_SIGNALS"] = NO_EXTRA_SIGNALS
            missing = command_variables(entry["generator"]) - set(variables)
            assert not missing, f"{unit_name}: nothing fills {sorted(missing)}"
            result.append((entry, variables, width))
    return result
