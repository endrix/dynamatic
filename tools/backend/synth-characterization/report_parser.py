# This script is used to extract timing data from synthesis reports and save it in a JSON format.
import os
import re
import json

from asap7_backend import is_asap7

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
OPENSTA_TIME_UNIT_NS = 0.001

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

def extract_delay_opensta(line):
    """
    Extract the delay from a line in an OpenSTA path report.

    Args:
        line (str): A line from the report file.

    Returns:
        float: The extracted delay in nanoseconds, or None if the line is the
            negated copy the slack arithmetic prints.
    """
    match = RE_DELAY_OPENSTA.match(line)
    if not match:
        return None
    return float(match.group(1)) * OPENSTA_TIME_UNIT_NS

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
    asap7 = is_asap7(synth_tool)
    # Read the report file and extract the required data
    with open(rpt_file, 'r') as f:
        for line in f:
            # Extract delay of the data path
            if asap7:
                if PATTERN_DELAY_INFO_OPENSTA in line:
                    delay = extract_delay_opensta(line)
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
            for delay_type, rpt_filename in unit_char.get_signals_type_to_rpt().items():
                # Check if the report file exists
                if not os.path.exists(rpt_filename):
                    continue
                traversedParamOnce = True
                traversedUnitOnce = True
                # Extract delay from the report file
                delay = extract_single_rpt(rpt_filename, synth_tool)
                if delay_type == ("data", "data"):
                    dataDict[str(unit_char.get_parameter_value("DATA_TYPE"))] = delay
                elif delay_type == ("valid", "valid"):
                    validDict["1"] = max(validDict["1"], delay)
                elif delay_type == ("ready", "ready"):
                    readyDict["1"] = max(readyDict["1"], delay)
                elif delay_type == ("valid", "ready"):
                    VRDelayFinal = max(VRDelayFinal, delay)
                elif delay_type == ("control", "valid"):
                    CVDelayFinal = max(CVDelayFinal, delay)
                elif delay_type == ("control", "ready"):
                    CRDelayFinal = max(CRDelayFinal, delay)
                elif delay_type == ("valid", "control"):
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
                                  "delay":{"data": dataDict,
                                       "valid": validDict,
                                       "ready": readyDict,
                                       "VR": VRDelayFinal,
                                       "CV": CVDelayFinal,
                                       "CR": CRDelayFinal,
                                       "VC": VCDelayFinal,
                                       "VD": VDDelayFinal},
                                  "inport": ZERO_PORT_MODEL,
                                  "outport": ZERO_PORT_MODEL}


    # Save the output data to the JSON file
    with open(json_output, 'w') as f:
        json.dump(output_data, f, indent=2)
