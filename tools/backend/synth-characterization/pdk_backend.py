# Standard-cell backend for the dataflow-unit characterization: ASAP7 or
# sky130.
#
# Selected with `--synth-tool asap7` or `--synth-tool sky130`. Where the
# Vivado backend writes a Tcl script that Vivado runs, this one writes a shell
# script that maps the unit's top with yosys (VHDL through the GHDL plugin)
# onto the library's typical corner and then asks OpenSTA, for every (input
# port, output port) pair the Vivado backend would have asked Vivado about,
# for the largest combinational delay between them.
#
# The mapping recipe -- the liberty files, the cells kept out of them, the
# ABC script, the driving cell and load at the boundary, the reset false path
# -- is tools/backend/<pdk>-lib.sh through tools/backend/pdk-lib.sh, the same
# files tools/backend/report-timing.sh sources to time a whole design. A unit
# delay and a design's critical path are then two measurements from one flow.
#
# What the numbers are: post-synthesis, so no placement and no wire delay, at
# the typical corner. OpenSTA reports in the liberty file's time unit,
# picoseconds for ASAP7 and nanoseconds for sky130; the model wants
# nanoseconds, so the parser divides by the PDK's scale (see PDKS and
# report_parser.py).
#
# A pair with no combinational path between its ports -- a pipelined unit's
# data path, say, where the only route from input to output runs through a
# register -- gets no report at all from OpenSTA ("No paths found."), and the
# parser then reads 0.0, which is what the Vivado backend records for the same
# case.

import os
import re

# The names that select this backend on the command line, each with the
# environment variable that locates its library and the number of OpenSTA
# time units in a nanosecond (the liberty's unit).
PDKS = {
    "asap7": {"dir_var": "ASAP7_DIR", "units_per_ns": 1000.0},
    "sky130": {"dir_var": "SKY130_DIR", "units_per_ns": 1.0},
}

# tools/backend/pdk-lib.sh, next to this package's parent directory.
PDK_LIB_SH = os.path.normpath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "pdk-lib.sh"))

# Ports that are never a path's start point.
CONTROL_PORT_NAMES = ("clk", "clock", "rst", "reset")

_INDEXED_PORT = re.compile(r"^(.*)\[\d+\]$")


def is_pdk(synth_tool):
    """
    Whether the given --synth-tool selects this backend (a PDK name).

    Args:
        synth_tool (str): value of the --synth-tool argument.

    Returns:
        bool: True for a PDK in PDKS, False for Vivado.
    """
    return synth_tool.strip() in PDKS


def is_asap7(synth_tool):
    """is_pdk under its old name."""
    return is_pdk(synth_tool)


def units_per_ns(synth_tool):
    """
    How many of OpenSTA's time units make a nanosecond for the PDK.

    Args:
        synth_tool (str): value of the --synth-tool argument.

    Returns:
        float: 1000.0 for ASAP7 (picoseconds), 1.0 for sky130.
    """
    return PDKS[synth_tool.strip()]["units_per_ns"]


def netlist_port_name(port):
    """
    Map a port name from the VHDL interface onto its name in the mapped netlist.

    A VHDL 2-D `data_array(SIZE - 1 downto 0)(DATA_TYPE - 1 downto 0)` port
    arrives in the netlist as one flat bus, so the interface's `ins[0]` and
    `ins[1]` are two slices of the single port `ins`. Asking OpenSTA about the
    whole bus covers every element, and the largest delay over the bus is the
    largest delay over the elements.

    Args:
        port (str): port name as the VHDL interface lists it.

    Returns:
        str: the name to hand to OpenSTA's get_ports.
    """
    match = _INDEXED_PORT.match(port)
    return match.group(1) if match else port


def port_query_names(ports, skip_control):
    """
    The distinct netlist port names to query for a list of interface ports.

    Args:
        ports (list): port names from the VHDL interface.
        skip_control (bool): drop clock and reset (they are never start points).

    Returns:
        list: netlist port names, without duplicates, in the original order.
    """
    names = []
    for port in ports:
        if skip_control and any(name in port for name in CONTROL_PORT_NAMES):
            continue
        name = netlist_port_name(port)
        if name not in names:
            names.append(name)
    return names


def order_hdl_files(hdl_files, top_file):
    """
    Order the HDL files for GHDL: packages first, the top last.

    Args:
        hdl_files (list): all the unit's HDL files, the top among them.
        top_file (str): the generated top file.

    Returns:
        list: the same files, in analysis order.
    """
    packages = [f for f in hdl_files
                if os.path.basename(f) == "types.vhd"]
    rest = [f for f in hdl_files
            if f not in packages and f != top_file]
    return packages + rest + [top_file]


def synth_adder():
    """The parallel-prefix adder yosys maps carry chains to, as in
    report-timing.sh: ADDER=sklansky (the default; kogge-stone and
    han-carlson are the others) or ADDER=yosys for yosys' own Brent-Kung
    unit, which ABC rebuilds as a ripple-carry chain. The same choice as the
    reports, so the models are of the same adders."""
    adder = os.environ.get("ADDER", "sklansky").strip()
    return "" if adder == "yosys" else f" -extra-map +/choices/{adder}.v"


def write_pdk_script(synth_tool, top_entity_name, hdl_files, script_file,
                     period_ns, map_rpt_to_ports, stage_rpt=None):
    """
    Write the shell script that maps one unit top and times it with OpenSTA.

    The script is what run_synthesis runs, one per parameter set. It leaves the
    mapped netlist, the generated OpenSTA script and the tool logs in a work
    directory next to itself, and appends one OpenSTA path report per queried
    port pair to the report file its delay class was given.

    Args:
        synth_tool (str): the PDK, a key of PDKS.
        top_entity_name (str): name of the unit's entity (the top is `tb`).
        hdl_files (list): HDL files for the unit, the generated top first.
        script_file (str): path of the shell script to write.
        period_ns (float): clock period in nanoseconds.
        map_rpt_to_ports (dict): {report file: {"input_ports": [...],
            "output_ports": [...]}}, one entry per delay class.
        stage_rpt (str): report file for the unit's longest register-to-
            register path, the floor its own stages put under the clock on
            this library; None asks for no such report.
    """
    work_dir = f"{os.path.splitext(script_file)[0]}.work"
    os.makedirs(work_dir, exist_ok=True)
    pdk = synth_tool.strip()
    # ABC's -D is picoseconds whatever the liberty's unit; OpenSTA's clock is
    # in the liberty's unit (picoseconds for ASAP7, nanoseconds for sky130).
    period_ps = int(round(period_ns * 1000))
    scale = PDKS[pdk]["units_per_ns"]
    period_sta = period_ps if scale == 1000.0 else f"{period_ns:.4f}"

    top_file = hdl_files[0]
    ordered_files = " ".join(order_hdl_files(hdl_files, top_file))

    # The OpenSTA queries: one per (input port, output port) pair, appended to
    # the report file of the delay class the pair belongs to. The preamble in
    # front of them is written by the shell script, which is where the library
    # file names and the reset port's name are known.
    checks_file = f"{work_dir}/checks.tcl"
    with open(checks_file, 'w') as f:
        f.write("# Largest combinational delay from one input port to one\n"
                "# output port. A pair OpenSTA finds no path for is left out\n"
                "# of the report, and read back as a delay of zero.\n")
        f.write("proc unit_delay {rpt from to} {\n"
                "  set fp [get_ports -quiet $from]\n"
                "  set tp [get_ports -quiet $to]\n"
                "  if {[llength $fp] == 0 || [llength $tp] == 0} {\n"
                "    return\n"
                "  }\n"
                "  report_checks -from $fp -to $tp -path_delay max"
                " -format full_clock_expanded -digits 3 >> $rpt\n"
                "}\n")
        for rpt_timing, ports_info in map_rpt_to_ports.items():
            for iport in port_query_names(ports_info["input_ports"], True):
                for oport in port_query_names(ports_info["output_ports"], False):
                    f.write(f"unit_delay {{{rpt_timing}}} {{{iport}}} {{{oport}}}\n")
        if stage_rpt:
            f.write("# The longest path from one register to another inside the\n"
                    "# unit: the smallest clock its stages allow. Not in the\n"
                    "# placer's model (it cannot pipeline a unit); a report. A\n"
                    "# combinational unit has no registers and no such report.\n"
                    "if {[llength [all_registers]] > 0} {\n"
                    f"  report_checks -from [all_registers] -to [all_registers]"
                    f" -path_delay max -format full_clock_expanded -digits 3 >> {{{stage_rpt}}}\n"
                    "}\n")
        f.write("exit\n")

    yosys_cmd = (
        f"ghdl --std=08 -fsynopsys {ordered_files} -e tb; "
        f"hierarchy -top tb; "
        f"synth -top tb -flatten{synth_adder()}; "
        f"dfflibmap -liberty $SEQ_LIBERTY; "
        f"abc $LIB_ARGS -constr {work_dir}/abc.constr -D {period_ps}"
        f" -script $ABC_SCRIPT; "
        f"opt_clean; stat; "
        f"write_verilog -noattr -noexpr -norename {work_dir}/mapped.v")

    with open(script_file, 'w') as f:
        f.write("#!/usr/bin/env bash\n")
        f.write(f"# {pdk} characterization of {top_entity_name}"
                f" at a {period_ns} ns clock.\n")
        f.write("set -uo pipefail\n")
        f.write(f'PDK={pdk} source "{PDK_LIB_SH}" || exit $?\n')
        f.write('if [[ -z "$LIBERTIES" || -z "$SEQ_LIBERTY" '
                '|| ! -f "$SEQ_LIBERTY" ]]; then\n'
                f'  echo "{pdk}: no cell library; set {PDKS[pdk]["dir_var"]}'
                ' (or LIBERTIES and SEQ_LIBERTY)" >&2\n'
                '  exit 2\n'
                'fi\n')
        f.write('if ! command -v yosys >/dev/null 2>&1; then\n'
                f'  echo "{pdk}: yosys is not installed" >&2\n'
                '  exit 2\n'
                'fi\n')
        f.write('if [[ -z "$STA" || ! -x "$STA" ]]; then\n'
                f'  echo "{pdk}: OpenSTA (sta) is not installed" >&2\n'
                '  exit 2\n'
                'fi\n')
        # OpenSTA creates each report as it writes the first path into it, so
        # a run that gets that far leaves reports behind and a run that fails
        # leaves none -- which is how the parser tells a measured zero from a
        # unit that never elaborated. Clearing them first keeps an earlier
        # run's reports from being read as this one's.
        for rpt_timing in list(map_rpt_to_ports) + ([stage_rpt] if stage_rpt else []):
            f.write(f'rm -f "{rpt_timing}"\n')
        f.write(f'pdk_write_abc_constr "{work_dir}/abc.constr"\n')
        f.write(f'if ! yosys -m ghdl -p "{yosys_cmd}"'
                f' > "{work_dir}/yosys.log" 2>&1; then\n'
                f'  echo "{pdk}: yosys failed on {top_entity_name}'
                f' (see {work_dir}/yosys.log)" >&2\n'
                f'  exit 1\n'
                f'fi\n')
        f.write('{\n'
                '  for lib in $LIBERTIES; do echo "read_liberty $lib"; done\n'
                f'  echo "read_verilog {work_dir}/mapped.v"\n'
                '  echo "link_design tb"\n'
                f'  echo "create_clock -name clk -period {period_sta}'
                ' [get_ports clk]"\n'
                '  echo "set_input_delay 0 -clock clk'
                ' [delete_from_list [all_inputs] [get_ports clk]]"\n'
                '  echo "set_output_delay 0 -clock clk [all_outputs]"\n'
                '  echo "set_false_path -from [get_ports $RESET_PORT]"\n'
                f'  cat "{checks_file}"\n'
                f'}} > "{work_dir}/sta.tcl"\n')
        f.write(f'if ! "$STA" -no_init -no_splash -exit "{work_dir}/sta.tcl"'
                f' > "{work_dir}/sta.log" 2>&1; then\n'
                f'  echo "{pdk}: sta failed on {top_entity_name}'
                f' (see {work_dir}/sta.log)" >&2\n'
                f'  exit 1\n'
                f'fi\n')
        f.write("exit 0\n")
    os.chmod(script_file, 0o755)
