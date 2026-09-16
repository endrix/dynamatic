# This script is used to extract timing data from synthesis reports and save it in a JSON format.
import os
import re
import json

from pdk_backend import is_pdk, units_per_ns

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

# Port-to-register delays. The characterization does not measure them and the
# buffer placer does not read them, but the timing model's deserializer expects
# both keys to be there (see lib/Support/TimingModels.cpp).
ZERO_PORT_MODEL = {"delay": {"data": {"64": 0},
                             "valid": {"1": 0},
                             "ready": {"1": 0},
                             "VR": 0, "CV": 0, "CR": 0, "VC": 0, "VD": 0}}

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
                     synth_tool="vivado", reference_json=None):
    """
    Extract the data from the map_unit_to_list_unit_chars dictionary and save it to a JSON file.
    IMPORTANT: For now we assume that only DATA_TYPE is the only parameter that can be used to characterize the unit.

    Args:
        map_unit_to_list_unit_chars (dict): Dictionary mapping unit names to a list of UnitCharacterization objects.
        json_output (str): Path to the output JSON file.
        synth_tool (str): Value of --synth-tool, which decides the report format.
        reference_json (str): Timing model to take latency tables from, or None.
    """
    latencies = read_reference_latencies(reference_json)
    # Create the output data structure
    output_data = {}
    # A standard-cell backend's register-to-register delays: unit -> bitwidth
    # -> ns, the floor the unit's own stages put under the clock. Written
    # beside the model (see write_stages), not into it: the placer cannot
    # pipeline a unit, so its model has no field for this.
    stages = {}
    for unit_name, list_unit_chars in map_unit_to_list_unit_chars.items():
        dataDict = {}
        validDict = {"1": 0.0}
        readyDict = {"1": 0.0}
        VRDelayFinal = 0.0
        CVDelayFinal = 0.0
        CRDelayFinal = 0.0
        VCDelayFinal = 0.0
        VDDelayFinal = 0.0
        traversedUnitOnce = False
        for unit_char in list_unit_chars:
            traversedParamOnce = False
            stage_rpt = unit_char.get_stage_rpt()
            if stage_rpt and os.path.exists(stage_rpt):
                bitwidth = str(unit_char.get_parameter_value("DATA_TYPE"))
                stage = extract_single_rpt(stage_rpt, synth_tool)
                stages.setdefault(unit_name, {})[bitwidth] = max(stages.get(unit_name, {}).get(bitwidth, 0.0), stage)
            for delay_type, rpt_filename in unit_char.get_signals_type_to_rpt().items():
                # Check if the report file exists
                if not os.path.exists(rpt_filename):
                    continue
                traversedParamOnce = True
                traversedUnitOnce = True
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
                else:
                    print("\033[91m" + f"[ERROR] Unknown delay type {delay_type} in report file {rpt_filename} for unit {unit_name}. Skipping." + "\033[0m")
                    continue
            if traversedParamOnce == False:
                param_value = unit_char.get_parameter_value("DATA_TYPE")
                print("\033[93m" + f"[WARNING] Report file for unit {unit_name} for bitwidth {param_value} does not exist({rpt_filename}). Skipping." + "\033[0m")

        if traversedUnitOnce == False:
            print("\033[91m" + f"[ERROR] No reports found for unit {unit_name}." + "\033[0m")
            continue

        output_data[unit_name] = {"latency": latencies.get(unit_name,
                                                           DEFAULT_LATENCY),
                                  "delay": {"data": dataDict,
                                            "valid": validDict,
                                            "ready": readyDict,
                                            "VR": VRDelayFinal,
                                            "CV": CVDelayFinal,
                                            "CR": CRDelayFinal,
                                            "VC": VCDelayFinal,
                                            "VD": VDDelayFinal},
                                  "inport": ZERO_PORT_MODEL,
                                  "outport": ZERO_PORT_MODEL}

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
