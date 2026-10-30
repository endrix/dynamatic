# This script is used to extract timing data from synthesis reports and save it in a JSON format.
import os
import re
import json

from generated_units import base_unit, type_base, VARIANT_KEYS
from pdk_backend import is_pdk, units_per_ns
from utils import WIDE_WIDTHS, UnitCharacterization

# Constants for parsing the report that specify which line
# contains the delay information.
# This pattern is specific to the Vivado synthesis report format.
# If a different synthesis tool is used, you might have to define a new pattern.
PATTERN_DELAY_INFO = "Data Path Delay:"

# The same line for OpenSTA: the arrival time at the end of a reported path.
# The path's start point is an input port with a zero input delay on an ideal
# clock, so the arrival time at an output port is the combinational delay
# between the two. The report prints the number a second time, negated, in the
# slack arithmetic underneath; anchoring on a digit leaves that copy out.
PATTERN_DELAY_INFO_OPENSTA = "data arrival time"
RE_DELAY_OPENSTA = re.compile(r'^\s+([\d.]+)\s+data arrival time\s*$')

# ASAP7's liberty files declare their time unit as picoseconds, so that is what
# OpenSTA prints; the timing model is in nanoseconds.
# OpenSTA prints in the liberty's time unit; the PDK says how many make a
# nanosecond (pdk_backend.units_per_ns).

# A unit whose latency this run cannot know, and which the reference model does
# not list either: a combinational unit, one implementation, no internal delay.
DEFAULT_LATENCY = {"0": {"64": {"0.0": 0.0}}}

# The port models of a unit with no registers: nothing between a port and a
# register. The timing model's deserializer expects both keys to be there (see
# lib/Support/TimingModels.cpp). The Vivado backend measures no port model, and
# writes this for every unit.
ZERO_PORT_MODEL = {"delay": {"data": {"64": 0},
                             "valid": {"1": 0},
                             "ready": {"1": 0},
                             "VR": 0, "CV": 0, "CR": 0, "VC": 0, "VD": 0}}

# A standard-cell backend's port models (utils.UnitCharacterization's
# register_delay_types): `inport`, from an input port into a register, its
# setup included; `outport`, from a register to an output port, its clock to
# output included. The buffer placer reads them as a registered unit's
# (BufferPlacementMILP's path_inDelay and path_outDelay) and as a slot's own
# (path_bufferedChannelIn and Out). Each signal is keyed by the unit's data
# width -- a register's enable or a select fans out over the data, so the
# valid and ready delays grow with it too -- and the deserializer reads the
# valid and ready ones at "1", which is always written. A condition port (a
# select, an index) is a data channel and goes to the data delays.
PORT_SIGNALS = {"data": "data", "condition": "data", "valid": "valid", "ready": "ready",
                "kill": "kill"}

# A commit's kill out (`handshake.commit`): the transfer, the AND of its valid
# in and its ready out, from each of them. Written only for a unit that has
# a kill out, under keys of their own beside VR..VD; the deserializer reads
# none of them (no Dynamatic consumer times a kill), a consumer that times the
# kill arc reads them by name.
KILL_DELAYS = {("valid", "kill"): "VK", ("ready", "kill"): "RK"}
RE_SLACK_OPENSTA = re.compile(r'^\s+(-?[\d.]+)\s+slack \((MET|VIOLATED)\)\s*$')

# This function extracts the delay from a line in the report file.
# It uses a regular expression to find the delay value in nanoseconds.
# It is specific to the Vivado synthesis report format.
# If a different synthesis tool is used, this function may need to be modified.


def extract_delay(line):
    """
    Extract the delay from a line in the report.

    Args:
        line (str): A line from the report file.

    Returns:
        float: The extracted delay in nanoseconds.
    """
    match = re.search(r'Data Path Delay:\s+([\d.]+)ns', line)
    assert match, f"Could not find data path delay in line: {line}"
    return float(match.group(1))


def extract_delay_opensta(line, per_ns=1000.0):
    """
    Extract the delay from a line in an OpenSTA path report.

    Args:
        line (str): A line from the report file.
        per_ns (float): OpenSTA time units in a nanosecond (the liberty's).

    Returns:
        float: The extracted delay in nanoseconds, or None if the line is the
            negated copy the slack arithmetic prints.
    """
    match = RE_DELAY_OPENSTA.match(line)
    if not match:
        return None
    return float(match.group(1)) / per_ns


def extract_single_rpt(rpt_file, synth_tool="vivado"):
    """
    Extract data from the report file.

    Args:
        rpt_file (str): Path to the report file.
        synth_tool (str): Value of --synth-tool, which decides the format.

    Returns:
        delay (float): The extracted delay in nanoseconds.
    """
    max_delay = 0.0
    asap7 = is_pdk(synth_tool)
    # Read the report file and extract the required data
    with open(rpt_file, 'r') as f:
        for line in f:
            # Extract delay of the data path
            if asap7:
                if PATTERN_DELAY_INFO_OPENSTA in line:
                    delay = extract_delay_opensta(line, units_per_ns(synth_tool))
                    if delay is not None:
                        max_delay = max(max_delay, delay)
            elif PATTERN_DELAY_INFO in line:
                delay = extract_delay(line)
                max_delay = max(max_delay, delay)

    return max_delay  # Return 0.0 if no delay is found


def extract_capture_rpt(rpt_file, synth_tool, period_ns):
    """
    The largest delay from an input port into a register, its setup included,
    in an OpenSTA report of such paths: the period less each path's slack
    (the path starts at a zero input delay on an ideal clock, so its required
    time is the period less the register's setup).

    Args:
        rpt_file (str): Path to the report file.
        synth_tool (str): Value of --synth-tool, a PDK.
        period_ns (float): The clock period the report was timed at, in ns.

    Returns:
        float: The delay in nanoseconds, 0.0 if the report has no path.
    """
    per_ns = units_per_ns(synth_tool)
    worst = 0.0
    with open(rpt_file, 'r') as f:
        for line in f:
            match = RE_SLACK_OPENSTA.match(line)
            if match:
                worst = max(worst, period_ns - float(match.group(1)) / per_ns)
    return worst


def port_model(by_signal):
    """
    A port model from its measured delays.

    Args:
        by_signal (dict): "data", "valid", "ready" -> {bitwidth (str): ns}.

    Returns:
        dict: the model's `inport` or `outport` entry; ZERO_PORT_MODEL when
            nothing was measured, which is every unit with no register.
    """
    if not any(v > 0.0 for widths in by_signal.values() for v in widths.values()):
        return ZERO_PORT_MODEL
    delay = {"VR": 0, "CV": 0, "CR": 0, "VC": 0, "VD": 0}
    # the kills into the registers (a stand-in's, a drop-counting load's)
    # only where the unit takes kills: no other entry changes
    signals = ("data", "valid", "ready") + (("kill",) if "kill" in by_signal else ())
    for signal in signals:
        widths = dict(sorted(by_signal.get(signal, {}).items(), key=lambda kv: int(kv[0])))
        if signal != "data" and widths and "1" not in widths:
            # the deserializer reads valid and ready at "1": the narrowest
            # width's delay stands for it
            widths = {"1": next(iter(widths.values())), **widths}
        delay[signal] = widths or ({"64": 0} if signal == "data" else {"1": 0})
    return {"delay": delay}


def read_reference_latencies(reference_json):
    """
    Read the latency table of every unit in a reference timing model.

    Latency is a property of the RTL -- muli's VHDL pipelines its multiplier
    over four cycles whatever it is mapped onto -- and this characterization
    measures delays only. Carrying the table over from a model that has one
    keeps a pipelined unit from being modelled as combinational.

    Args:
        reference_json (str): Path to a timing model in components.json format,
            or None.

    Returns:
        dict: Unit name to its latency table; empty if there is no reference.
    """
    if not reference_json or not os.path.exists(reference_json):
        return {}
    with open(reference_json, 'r') as f:
        reference = json.load(f)
    return {name: info["latency"] for name, info in reference.items()
            if "latency" in info}


def extract_rpt_data(map_unit_to_list_unit_chars, json_output,
                     synth_tool="vivado", reference_json=None, update=False):
    """
    Extract the data from the map_unit_to_list_unit_chars dictionary and save it to a JSON file.
    IMPORTANT: For now we assume that only DATA_TYPE is the only parameter that can be used to characterize the unit.

    Args:
        map_unit_to_list_unit_chars (dict): Dictionary mapping unit names to a list of UnitCharacterization objects.
        json_output (str): Path to the output JSON file.
        synth_tool (str): Value of --synth-tool, which decides the report format.
        reference_json (str): Timing model to take latency tables from, or None.
        update (bool): Write the entries into the model already at
            json_output (update_model), not a model of their own.
    """
    latencies = read_reference_latencies(reference_json)
    # Create the output data structure
    output_data = {}
    # A standard-cell backend's register-to-register delays: unit -> bitwidth
    # -> ns, the floor the unit's own stages put under the clock. Written
    # beside the model (see write_stages), not into it: the placer cannot
    # pipeline a unit, so its model has no field for this.
    stages = {}
    # The latency table of a unit the reference model does not list and whose
    # latency the caller knows (the sequential divider and multiplier, whose
    # latency is a formula of the width and the step): unit -> bitwidth ->
    # cycles. The model writes the latency under the unit's internal
    # combinational delay, which for these units is the delay of one
    # iteration, so the two are assembled together below.
    measured_latency = {}
    for unit_name, list_unit_chars in map_unit_to_list_unit_chars.items():
        dataDict = {}
        validDict = {"1": 0.0}
        readyDict = {"1": 0.0}
        VRDelayFinal = 0.0
        CVDelayFinal = 0.0
        CRDelayFinal = 0.0
        VCDelayFinal = 0.0
        VDDelayFinal = 0.0
        # a kill out's (KILL_DELAYS), only for a unit that has one
        killDelays = {}
        # the port models: "in"/"out" -> signal -> bitwidth -> ns
        ports = {"in": {}, "out": {}}
        traversedUnitOnce = False
        for unit_char in list_unit_chars:
            traversedParamOnce = False
            # A point at one of utils.WIDE_WIDTHS gives the data delay at its
            # width and nothing else of the delays: the others are one number
            # for every width, the maximum over the widths up to 64 bits (see
            # WIDE_WIDTHS for why).
            wide = int(unit_char.params.get("DATA_TYPE", 0)) in WIDE_WIDTHS
            stage_rpt = unit_char.get_stage_rpt()
            if stage_rpt and os.path.exists(stage_rpt):
                bitwidth = str(unit_char.get_parameter_value("DATA_TYPE"))
                stage = extract_single_rpt(stage_rpt, synth_tool)
                stages.setdefault(unit_name, {})[bitwidth] = max(stages.get(unit_name, {}).get(bitwidth, 0.0), stage)
                cycles = getattr(unit_char, "latency_cycles", None)
                if cycles is not None:
                    measured_latency.setdefault(unit_name, {})[bitwidth] = cycles
            for delay_type, rpt_filename in unit_char.get_signals_type_to_rpt().items():
                # Check if the report file exists
                if not os.path.exists(rpt_filename):
                    continue
                traversedParamOnce = True
                traversedUnitOnce = True
                if UnitCharacterization.REGISTER in delay_type:
                    # A port model, at every width the unit was written at:
                    # nothing older holds these entries to 64 bits.
                    bitwidth = str(unit_char.get_parameter_value("DATA_TYPE"))
                    if delay_type[0] == UnitCharacterization.REGISTER:
                        side, signal = "out", PORT_SIGNALS[delay_type[1]]
                        delay = extract_single_rpt(rpt_filename, synth_tool)
                    else:
                        side, signal = "in", PORT_SIGNALS[delay_type[0]]
                        delay = extract_capture_rpt(rpt_filename, synth_tool,
                                                    unit_char.clock_period)
                    by_width = ports[side].setdefault(signal, {})
                    by_width[bitwidth] = max(by_width.get(bitwidth, 0.0), delay)
                    continue
                if wide and delay_type != ("data", "data"):
                    continue
                # Extract delay from the report file
                delay = extract_single_rpt(rpt_filename, synth_tool)
                if delay_type == ("data", "data"):
                    # A unit name can cover several implementations that reach
                    # this bitwidth (six of them are `handshake.buffer`), and
                    # the model has one entry per name. Reduce with the max, as
                    # the other delay classes below do: the model then never
                    # says a path is shorter than some implementation makes it.
                    bitwidth = str(unit_char.get_parameter_value("DATA_TYPE"))
                    dataDict[bitwidth] = max(dataDict.get(bitwidth, 0.0), delay)
                elif delay_type == ("valid", "valid"):
                    validDict["1"] = max(validDict["1"], delay)
                elif delay_type == ("ready", "ready"):
                    readyDict["1"] = max(readyDict["1"], delay)
                elif delay_type == ("valid", "ready"):
                    VRDelayFinal = max(VRDelayFinal, delay)
                # The delay classes are named after the port class the
                # interface parser assigns, which is "condition" (see
                # VhdlInterfaceInfo.categorize_ports); the model's keys for
                # them are CV, CR and VC.
                elif delay_type == ("condition", "valid"):
                    CVDelayFinal = max(CVDelayFinal, delay)
                elif delay_type == ("condition", "ready"):
                    CRDelayFinal = max(CRDelayFinal, delay)
                elif delay_type == ("valid", "condition"):
                    VCDelayFinal = max(VCDelayFinal, delay)
                elif delay_type == ("valid", "data"):
                    VDDelayFinal = max(VDDelayFinal, delay)
                # The payload's zero-detect (utils.payload_condition_units):
                # the payload is the unit's condition, so the path from it is
                # the condition's.
                elif delay_type == ("data", "valid"):
                    CVDelayFinal = max(CVDelayFinal, delay)
                elif delay_type == ("data", "ready"):
                    CRDelayFinal = max(CRDelayFinal, delay)
                elif delay_type in KILL_DELAYS:
                    name = KILL_DELAYS[delay_type]
                    killDelays[name] = max(killDelays.get(name, 0.0), delay)
                else:
                    print("\033[91m" + f"[ERROR] Unknown delay type {delay_type} in report file {rpt_filename} for unit {unit_name}. Skipping." + "\033[0m")
                    continue
            if traversedParamOnce == False:
                param_value = unit_char.get_parameter_value("DATA_TYPE")
                print("\033[93m" + f"[WARNING] Report file for unit {unit_name} for bitwidth {param_value} does not exist({rpt_filename}). Skipping." + "\033[0m")

        if traversedUnitOnce == False:
            print("\033[91m" + f"[ERROR] No reports found for unit {unit_name}." + "\033[0m")
            continue

        # The latency table: the reference model's, or -- for a unit it does
        # not list and whose latency the caller gave -- the measured
        # iteration delay and the cycles that many iterations take.
        if unit_name in measured_latency:
            latency_table = {"0": {
                bitwidth: {f"{stages[unit_name][bitwidth]:.6f}": cycles}
                for bitwidth, cycles in measured_latency[unit_name].items()}}
        else:
            # An entry at one size of a unit (`handshake.fork.size.8`) or a
            # variant of it (`handshake.load.kill_drop`) has the unit's
            # latency: a size adds channels, not stages, and the dropping
            # load is the load's two slots with a counter beside them.
            latency_table = latencies.get(
                unit_name, latencies.get(unit_of_key(unit_name), DEFAULT_LATENCY))

        output_data[unit_name] = {"latency": latency_table,
                                  "delay": {"data": dataDict,
                                            "valid": validDict,
                                            "ready": readyDict,
                                            "VR": VRDelayFinal,
                                            "CV": CVDelayFinal,
                                            "CR": CRDelayFinal,
                                            "VC": VCDelayFinal,
                                            "VD": VDDelayFinal,
                                            **killDelays},
                                  "inport": port_model(ports["in"]),
                                  "outport": port_model(ports["out"])}

    bound_sizes(output_data)

    if update:
        update_model(output_data, stages, json_output)
        return

    # A unit this run did not characterize -- one on the skipping list (a
    # unit with no data path, one another script measures, the dividers
    # under Vivado) or one that left no report -- is carried from the reference
    # model as it is, so that the model stays complete for the buffer placer:
    # a latency is structural (the divider's 35 stages are 35 on any library)
    # and such a unit's delays are not port-to-port. A carried entry keeps the
    # reference's numbers, and the note below says which.
    if reference_json and os.path.exists(reference_json):
        with open(reference_json, 'r') as f:
            reference = json.load(f)
        carried = [unit for unit in reference if unit not in output_data]
        for unit in carried:
            output_data[unit] = reference[unit]
        if carried:
            print(f"Carried {len(carried)} unit(s) from the reference model, not characterized here: "
                  + ", ".join(carried))

    # Save the output data to the JSON file
    with open(json_output, 'w') as f:
        json.dump(output_data, f, indent=2)
    if stages:
        write_stages(stages, json_output)


def bound_sizes(output_data):
    """
    Make every delay of a unit's sized entries grow with the size.

    TimingDatabase::getModel times an op by the entry at the smallest size at
    or above its own, which bounds the op's delays only if no larger size has
    a shorter path. A measurement can: ABC maps each size afresh, and a merge
    at 256 inputs came out 0.19 ns faster than at 128 on ASAP7. Each entry
    takes, per delay, the largest at its size or any smaller one.

    Args:
        output_data (dict): the model being written, key -> entry; changed in
            place.
    """
    sized = {}
    for key in output_data:
        if key != base_unit(key):
            sized.setdefault(base_unit(key), []).append(key)
    for keys in sized.values():
        keys.sort(key=lambda key: int(key.rsplit(".", 1)[1]))
        bound = None
        for key in keys:
            delay = output_data[key]["delay"]
            if bound is not None:
                for width, d in delay["data"].items():
                    delay["data"][width] = max(d, bound["data"].get(width, d))
                for signal in ("valid", "ready"):
                    delay[signal]["1"] = max(delay[signal]["1"],
                                             bound[signal]["1"])
                for name in ("VR", "CV", "CR", "VC", "VD") + tuple(KILL_DELAYS.values()):
                    if name in delay and name in bound:
                        delay[name] = max(delay[name], bound[name])
                # the port models, per signal and width
                for port in ("inport", "outport"):
                    mine = output_data[key][port]
                    theirs = bound_ports[port]
                    if theirs is ZERO_PORT_MODEL:
                        continue
                    if mine is ZERO_PORT_MODEL:
                        mine = output_data[key][port] = json.loads(json.dumps(theirs))
                        continue
                    for signal in ("data", "valid", "ready", "kill"):
                        if signal not in theirs["delay"] or signal not in mine["delay"]:
                            continue
                        for width, d in theirs["delay"][signal].items():
                            mine["delay"][signal][width] = max(
                                mine["delay"][signal].get(width, d), d)
            bound = delay
            bound_ports = {port: output_data[key][port]
                           for port in ("inport", "outport")}


def unit_of_key(key):
    """The unit a model key is an entry of: `handshake.fork.size.8`'s,
    `handshake.buffer.ONE_SLOT_BREAK_R`'s and `handshake.load.kill_drop`'s are
    `handshake.fork`, `handshake.buffer` and `handshake.load`."""
    key = base_unit(type_base(key))
    for suffix in VARIANT_KEYS.values():
        if key.endswith("." + suffix):
            return key[:-len(suffix) - 1]
    return key


def merge_entries(old, new):
    """
    The model `old` with the units of `new` measured again: an entry of
    `new` replaces the one of the same key where it is, and one `old` has
    not comes after the last entry of its unit (at the end for a unit `old`
    has not). Every other entry is `old`'s, where it was: an entry of a unit
    `new` measures that `new` has not (a size whose run left no report) is
    kept, not dropped, since a lookup that misses a size falls to the one
    below it, and reported, so that the run is seen to be partial.

    Returns:
        (dict, list): the model, and the keys of the measured units kept
        from `old` because `new` has not measured them.
    """
    units = {unit_of_key(key) for key in new}
    stale = [key for key in old if unit_of_key(key) in units and key not in new]
    last = {}
    for key in old:
        last[unit_of_key(key)] = key
    added = {}
    for key in new:
        if key not in old:
            added.setdefault(last.get(unit_of_key(key)), []).append(key)
    merged = {}
    for key, entry in old.items():
        merged[key] = new.get(key, entry)
        if last.get(unit_of_key(key)) == key:
            for extra in added.pop(key, []):
                merged[extra] = new[extra]
    for extra in added.pop(None, []):
        merged[extra] = new[extra]
    return merged, stale


def update_model(output_data, stages, json_output):
    """
    Write a run's entries into the model at json_output and their stages
    into its .stages.json (merge_entries), every other entry and stage as it
    is there: a run of some units moves no other row.

    Args:
        output_data (dict): the run's entries, key -> entry.
        stages (dict): the run's stages, key -> bitwidth -> ns.
        json_output (str): the model to update.
    """
    with open(json_output, 'r') as f:
        old = json.load(f)
    merged, stale = merge_entries(old, output_data)
    with open(json_output, 'w') as f:
        json.dump(merged, f, indent=2)
    print(f"Updated {json_output}: {len(output_data)} entries written, "
          f"{sum(1 for key in output_data if key not in old)} of them new")
    if stale:
        print("\033[93m" + f"[WARNING] Kept as they were, not measured by this run: {', '.join(stale)}" + "\033[0m")
    path = os.path.splitext(json_output)[0] + ".stages.json"
    old_stages = {}
    if os.path.exists(path):
        with open(path, 'r') as f:
            old_stages = json.load(f)
    units = {unit_of_key(key) for key in output_data}
    kept = {key: widths for key, widths in old_stages.items()
            if unit_of_key(key) not in units}
    if stages or len(kept) != len(old_stages):
        write_stages({**kept, **stages}, json_output)


def write_stages(stages, json_output):
    """
    Write the register-to-register delays beside the model and print them.

    Args:
        stages (dict): unit -> bitwidth -> the longest register-to-register
            path in nanoseconds (0.0 for a unit with no such path).
        json_output (str): the model's path; the stages go to
            `<model without .json>.stages.json`.
    """
    path = os.path.splitext(json_output)[0] + ".stages.json"
    with open(path, 'w') as f:
        json.dump(stages, f, indent=2, sort_keys=True)
    rows = sorted(((max(widths.values()), unit) for unit, widths in stages.items()), reverse=True)
    print(f"Register-to-register delay per unit (the floor under the clock), in {path}:")
    for delay, unit in rows:
        if delay > 0.0:
            widths = ", ".join(f"{w}: {d:.3f}" for w, d in sorted(stages[unit].items(), key=lambda x: int(x[0])))
            print(f"  {unit:<28} {delay:7.3f} ns   ({widths})")
