# Script to run characterization of dataflow units
import argparse
import json
import os
import shutil
import generated_units
from report_parser import extract_rpt_data, read_reference_latencies
from hdl_manager import get_hdl_files
from pdk_backend import is_pdk
from run_synthesis import run_synthesis
from utils import VhdlInterfaceInfo, skipping_units, skipping_units_vivado, skipping_units_generated, impl_variants, unit_widths, lowering_units
from unit_characterization import run_unit_characterization


def extract_rtl_info(unit_info):
    """
    Extract RTL information from the unit_info dictionary.

    Args:
        unit_info (dict): Dictionary containing unit information.

    Returns:
        tuple: A tuple containing the unit name, list of parameters, generic,
            generator, dependencies, and the name of the VHDL entity when the
            entry gives one (a unit name is not always its entity's name:
            `handshake.fork` is the entity `handshake_fork`).
    """
    unit_name = unit_info.get("name")
    list_params = unit_info.get("parameters", [])
    generic = unit_info.get("generic", None)
    generator = unit_info.get("generator", None)
    dependencies = unit_info.get("dependencies", [])
    module_name = unit_info.get("module-name", None)

    return unit_name, list_params, generic, generator, dependencies, module_name

# Extract dependencies from the dataflow units
# This function is essential to move the right RTL files
# Example of a dependency dictionary:
# {
#     "unit_name": {"RTL": "path/to/rtl_file.vhd", "dependencies": ["dep1", "dep2"]},
#     "dep1": {"RTL": "path/to/dep1.vhd", "dependencies": []},
#     "dep2": {"RTL": "path/to/dep2.vhd", "dependencies": []},
#     ...
# }
# The dependencies are used to copy the necessary RTL files to the output directory


def get_dependency_dict(dataflow_units):
    """
    Extract the RTLs of all possible dependencies from the dataflow units.
    Args:
        dataflow_units (list): List of dataflow unit dictionaries.
    Returns:
        list: A list of unique dependencies.
    """
    dependency_dict = {}
    for unit_info in dataflow_units:
        if not "name" in unit_info:
            rtl_file = unit_info.get("generic")
            assert rtl_file, "Unit info must contain a 'generic' field for RTL file."
            unit_name = rtl_file.split("/")[-1].split(".")[0]
            if "dependencies" in unit_info:
                dependencies = unit_info["dependencies"]
            else:
                dependencies = []
            dependency_dict[unit_name] = {"RTL": rtl_file, "dependencies": dependencies}
        elif "module-name" in unit_info:
            unit_name = unit_info["module-name"]
            rtl_file = unit_info["generic"]
            if "dependencies" in unit_info:
                dependencies = unit_info["dependencies"]
            else:
                dependencies = []
            dependency_dict[unit_name] = {"RTL": rtl_file, "dependencies": dependencies}
        else:
            rtl_file = unit_info.get("generic")
            if not rtl_file:
                rtl_file = unit_info.get("generator")
            dependencies = unit_info.get("dependencies", [])
            unit_name = unit_info["name"]
            dependency_dict[unit_name] = {"RTL": rtl_file, "dependencies": dependencies}
            # Several entries can share a `name` and no `module-name`; a
            # dependency on one of them is written with the RTL file's stem
            # (`mem_controller` depends on `mem_controller_loadless`), so
            # register that name too.
            if rtl_file:
                stem = rtl_file.split("/")[-1].split(".")[0]
                dependency_dict.setdefault(
                    stem, {"RTL": rtl_file, "dependencies": dependencies})
    return dependency_dict


def characterize_generated(unit_name, entries, dirs, dynamatic_dir,
                           dependency_dict, synth_tool, clock_period,
                           latency_table):
    """
    Characterize a unit a generator writes at its port types
    (generated_units), at the widths utils.unit_widths gives it: every point
    of its sweep generated into a directory of its own, then all of them
    synthesized in one parallel batch.

    Args:
        unit_name (str): the operation, `handshake.fork`.
        entries (list): the config's entries under that name, in order.
        dirs (dict): the "hdl", "tcl", "rpt" and "log" directories.
        dynamatic_dir (str): the Dynamatic root the commands name.
        dependency_dict (dict): get_dependency_dict of the config.
        synth_tool (str): the --synth-tool.
        clock_period (float): the period to map toward, in ns.
        latency_table (dict): the unit's latency in the reference model.

    Returns:
        dict: model key -> List[UnitCharacterization]. A unit with a SIZE
            attribute has an entry per size (generated_units.sizes_of), and
            its base entry is the base size's; any other unit has its base
            entry. A point generated_units.VARIANT_KEYS names (a load that
            drops on a kill) goes to its own entry instead.
    """
    os.system(f"rm -rf {dirs['hdl']}/*")
    os.system(f"rm -rf {dirs['tcl']}/*")
    # The entity, named the way export-rtl names it (`handshake_buffer_0`):
    # the unit name's last part alone can be a VHDL keyword (`buffer`).
    module_name = unit_name.replace(".", "_")
    sized = any(param["name"] == "SIZE"
                for entry in entries for param in entry.get("parameters", []))
    # a race is sized by its inputs, at the nests of generated_units.race_shapes
    raced = unit_name == generated_units.RACE_UNIT
    base = generated_units.base_size(entries)
    keyed, scripts = {}, []
    for i, (entry, variables, width) in enumerate(generated_units.points(
            entries, unit_widths(unit_name), latency_table,
            generated_units.RACE_SIZES if raced
            else generated_units.sizes_of(entries) if sized else None)):
        point_dir = f"{dirs['hdl']}/{i}"
        os.makedirs(point_dir, exist_ok=True)
        top_def_file = get_hdl_files(
            unit_name, None, generated_units.substitute(entry["generator"], variables),
            entry.get("dependencies", []), point_dir, dynamatic_dir,
            dependency_dict, module_name)
        point_chars, point_scripts = run_unit_characterization(
            unit_name, [], point_dir, synth_tool, top_def_file, dirs["tcl"],
            dirs["rpt"], dirs["log"], clock_period, module_name,
            baked_params=dict(variables, DATA_TYPE=width), id_offset=i,
            defer=True)
        keys = [unit_name]
        if sized or raced:
            size = int(variables["SIZE"])
            keys = [generated_units.size_key(unit_name, size)]
            if size == base:
                keys.append(unit_name)
        variant = generated_units.variant_key(unit_name, variables)
        if variant and (sized or raced):
            # another circuit of a sized unit: its own entries at its sizes
            size = int(variables["SIZE"])
            keys = [generated_units.size_key(variant, size)]
            if size == base:
                keys.append(variant)
        elif variant:
            keys = [variant]
        if "BUFFER_TYPE" in variables:
            # a slot type's own entry beside the base one, which reduces over
            # all six
            keys.append(generated_units.type_key(unit_name, variables["BUFFER_TYPE"]))
        for key in keys:
            keyed.setdefault(key, []).extend(point_chars)
        scripts.extend(point_scripts)
    run_synthesis(scripts, synth_tool, f"{dirs['log']}/synth_{unit_name}_log.txt")
    return keyed


def run_characterization(json_input, json_output, dynamatic_dir, synth_tool, clock_period, reference_json, units=None, update=False):
    """
    Run characterization of dataflow units based on the provided JSON input.

    Args:
        json_input (str): Path to the input JSON file containing dataflow unit RTL information.
        json_output (str): Path to the output JSON file where characterization results will be saved.
        dynamatic_dir (str): Path to the DYNAMATIC home directory.
        synth_tool (str): Synthesis tool to use for characterization ('vivado' or 'asap7').
        clock_period (float): Clock period in nanoseconds to synthesize against.
        reference_json (str): Timing model to take latency tables from, or None.
        units (set): The units to characterize, by the config's names; all
            of them when None.
        update (bool): Write the units' entries into the model at
            json_output (and its stages beside it), every other entry as it
            is there, instead of writing a model of its own.
    """
    # Load the input JSON file
    with open(json_input, 'r') as f:
        dataflow_units = json.load(f)

    tmp_dir = f"{dynamatic_dir}/tools/backend/synth-characterization/tmp"
    # Generate the temporary directory if it does not exist
    if not os.path.exists(tmp_dir):
        os.makedirs(tmp_dir)
    # Generate hdl directory
    hdl_dir = f"{tmp_dir}/hdl"
    if not os.path.exists(hdl_dir):
        os.makedirs(hdl_dir)
    # Generate tcl directory
    tcl_dir = f"{tmp_dir}/tcl"
    if not os.path.exists(tcl_dir):
        os.makedirs(tcl_dir)
    # Generate report directory. OpenSTA appends to a report file, so one a
    # previous run left would be read with this run's, as the larger of the
    # two: a run reads its own reports only.
    rpt_dir = f"{tmp_dir}/reports"
    if os.path.exists(rpt_dir):
        shutil.rmtree(rpt_dir)
    os.makedirs(rpt_dir)
    # Generate logs directory
    log_dir = f"{tmp_dir}/logs"
    if not os.path.exists(log_dir):
        os.makedirs(log_dir)

    all_dependencies_dict = get_dependency_dict(dataflow_units)
    reference_latencies = read_reference_latencies(reference_json)
    dirs = {"hdl": hdl_dir, "tcl": tcl_dir, "rpt": rpt_dir, "log": log_dir}
    generated_done = set()

    map_unit_to_list_unit_chars = {}

    # The units the config lists, then the implementations it selects with a
    # parameter rather than with a file of its own (utils.impl_variants: the
    # sequential divider and multiplier, each under its own model key).
    for unit_info in list(dataflow_units) + impl_variants:
        # Extract the unit name and its RTL information
        unit_name, list_params, generic, generator, dependencies, module_name = extract_rtl_info(unit_info)
        if unit_name == None:
            print("Skipping unit with no name.")
            continue
        if units is not None and unit_name not in units:
            continue
        if unit_name in skipping_units or (unit_name in skipping_units_vivado and not is_pdk(synth_tool)):
            print(f"Skipping unit {unit_name} as it is in the skipping list.")
            continue
        if unit_name in skipping_units_generated or not (
                unit_name.startswith("handshake.") or unit_name in lowering_units):
            print(f"Skipping unit {unit_name}: no model entry for it yet.")
            continue
        # A unit a generator writes at its port types: all the config's
        # entries under its name at once, since export-rtl picks among them
        # by the operation's attributes (the pipelined or the sequential
        # divider).
        if generated_units.bakes_types(unit_info):
            if unit_name in generated_done:
                continue
            generated_done.add(unit_name)
            print(f"Processing unit: {unit_name}")
            entries = [u for u in dataflow_units if u.get("name") == unit_name]
            keyed = characterize_generated(unit_name, entries, dirs, dynamatic_dir,
                                           all_dependencies_dict, synth_tool,
                                           clock_period,
                                           reference_latencies.get(unit_name))
            for key, chars in keyed.items():
                map_unit_to_list_unit_chars.setdefault(key, []).extend(chars)
            continue
        # We assume that units with no unit_name are just for dependencies
        if unit_name == None:
            continue
        # If the unit has a "DATA_TYPE" parameter with data = 0, skip since it's a dataless unit
        if len(list_params) > 0:
            skip_unit = False
            for param in list_params:
                if param["name"] == "DATA_TYPE" and "data-eq" in param and param["data-eq"] == 0:
                    skip_unit = True
                    break
            if skip_unit:
                continue
        print(f"Processing unit: {unit_name}")
        # A unit whose generator bakes its width into the RTL is generated and
        # characterized once per width ($BITWIDTH in its command); a unit with
        # a DATA_TYPE generic is generated once and the width swept in the
        # wrapper.
        bitwidths = unit_info.get("bitwidths")
        latency_of = unit_info.get("latency")
        if bitwidths:
            list_unit_chars = []
            for bitwidth in bitwidths:
                # Clean previous RTL files and tcl files
                os.system(f"rm -rf {hdl_dir}/*")
                os.system(f"rm -rf {tcl_dir}/*")
                top_def_file = get_hdl_files(
                    unit_name, generic,
                    generator.replace("$BITWIDTH", str(bitwidth)),
                    dependencies, hdl_dir, dynamatic_dir,
                    all_dependencies_dict, module_name)
                list_unit_chars.extend(run_unit_characterization(
                    unit_name, list_params, hdl_dir, synth_tool, top_def_file,
                    tcl_dir, rpt_dir, log_dir, clock_period, module_name,
                    baked_params={"DATA_TYPE": bitwidth},
                    id_offset=len(list_unit_chars),
                    latency_cycles=latency_of(bitwidth) if latency_of else None))
        else:
            # Clean previous RTL files and tcl files
            os.system(f"rm -rf {hdl_dir}/*")
            os.system(f"rm -rf {tcl_dir}/*")
            # Copy the RTL files or generate them if necessary
            top_def_file = get_hdl_files(unit_name, generic, generator, dependencies, hdl_dir, dynamatic_dir, all_dependencies_dict, module_name)
            # After generating the HDL files, we can proceed with characterization
            list_unit_chars = run_unit_characterization(unit_name, list_params, hdl_dir, synth_tool, top_def_file, tcl_dir, rpt_dir, log_dir, clock_period, module_name)
        # Store the results in the map_unit_to_list_unit_chars dictionary.
        # A unit name can name several implementations -- six of them are
        # `handshake.buffer`, and the model has one entry per name -- so the
        # characterizations accumulate and the assembly reduces over them.
        map_unit_to_list_unit_chars.setdefault(unit_name, []).extend(list_unit_chars)

    # Save the results to the output JSON file
    extract_rpt_data(map_unit_to_list_unit_chars, json_output, synth_tool, reference_json,
                     update=update)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Run characterization of dataflow units")
    parser.add_argument(
        "--json-input",
        type=str,
        default=None,
        help="Path to the JSON file containing the dataflow unit RTL information (if unspecified: for a PDK, $DYNAMATIC_DIR/data/rtl-config-vhdl.json, the generators export-rtl writes a design with; for Vivado, $DYNAMATIC_DIR/data/rtl-config-vhdl-vivado.json)",
    )
    parser.add_argument(
        "--json-output",
        type=str,
        required=True,
        help="Path to the output JSON file where the characterization results will be saved",
    )
    parser.add_argument(
        "--dynamatic-dir",
        type=str,
        required=True,
        help="Path to the DYNAMATIC home directory",
    )
    parser.add_argument(
        "--synth-tool",
        type=str,
        default="vivado",
        help="Synthesis tool to use for characterization: the command that runs Vivado, or 'asap7' for the yosys + OpenSTA flow on the ASAP7 standard-cell library (default: vivado)",
    )
    parser.add_argument(
        "--reference-json",
        type=str,
        default=None,
        help="Timing model to carry latency tables over from, since this script measures delays only (if unspecified, $DYNAMATIC_DIR/data/components.json)",
    )
    parser.add_argument(
        "--units",
        type=str,
        default=None,
        help="Comma-separated units to characterize, by the names the RTL config gives them (handshake.first,kill_or); every unit when unspecified",
    )
    parser.add_argument(
        "--update",
        action="store_true",
        help="Write the characterized units' entries into the model --json-output names (and its .stages.json), keeping every other entry as it is there, instead of writing a whole model (with --units: a run of some units that moves no other row)",
    )
    parser.add_argument(
        "--clock-period",
        type=float,
        default=4.0,
        help="Clock period in nanoseconds to use for synthesis (default: 4.0 ns)",
    )
    args = parser.parse_args()
    json_input = args.json_input
    json_output = args.json_output
    dynamatic_dir = args.dynamatic_dir
    synth_tool = args.synth_tool
    clock_period = args.clock_period
    reference_json = args.reference_json
    if not json_input:
        # A standard-cell model is for the designs export-rtl writes, so it is
        # measured on the same generators' RTL; Vivado's keeps the files it
        # was always measured on.
        config = "rtl-config-vhdl.json" if is_pdk(synth_tool) else "rtl-config-vhdl-vivado.json"
        json_input = f"{dynamatic_dir}/data/{config}"
    if not reference_json:
        reference_json = f"{dynamatic_dir}/data/components.json"
    units = set(args.units.split(",")) if args.units else None
    if units is not None:
        if not args.update:
            parser.error("--units measures some units only, so it needs --update: without it the "
                         "other entries would be the reference model's, not this PDK's")
        with open(json_input, 'r') as f:
            known = ({unit.get("name") for unit in json.load(f)} | set(lowering_units)
                     | {variant["name"] for variant in impl_variants})
        unknown = sorted(units - known)
        if unknown:
            parser.error(f"--units names no unit of {json_input}: {', '.join(unknown)}")
    run_characterization(json_input, json_output, dynamatic_dir, synth_tool, clock_period, reference_json,
                         units=units, update=args.update)
