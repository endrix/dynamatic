#!/usr/bin/env bash
# report-timing.sh <hdl-dir> <top-module> [clock-ps] [out-dir]
#
# Maps an exported design to a cell library with yosys and reports its worst
# paths with OpenSTA: the critical path in picoseconds, the clock it allows,
# and the top paths in full, so that what limits the clock has a name.
#
# Post-synthesis only: no placement, so no wire delays. The absolute numbers
# are optimistic; the ranking of paths is what this is for. Two things keep
# the report about paths rather than about fan-out: ABC buffers every net
# above MAX_FANOUT loads while it maps, register outputs included, and
# sizes gates toward the clock (a net driving thousands of flip-flops is
# otherwise one inverter with a 20 ns delay, which is what placement's
# repair would fix), and the reset, a quasi-static input that reaches every
# flip-flop, is a false path.
#
# PLACE=1 goes one step further than synthesis: OpenROAD floorplans the
# mapped netlist (UTILIZATION percent, 50 by default), places it, estimates
# the wires' parasitics, buffers every net above MAX_FANOUT loads and every
# slew or capacitance violation (its resizer's repair_design), and times the
# result with the wires in. A post-synthesis report has no wires and no
# buffer trees, so it overstates a high-fan-out net (a clock enable over a
# 32-stage divider reads as 86 ns on sky130, 6 ns placed and repaired) and
# understates every long wire; the placed report is the honest one, at the
# price of a placement. The macros' LEFs come from MACRO_LEFS.
#
# ASAP7 (RVT, typical corner) as streamblocks' install_synthesis_tools.sh lays
# it out: ASAP7_DIR holds the five RVT TT liberty files, unpacked; PDK=sky130
# maps to the SkyWater high-density library instead (SKY130_DIR, see
# sky130-lib.sh). Yosys' abc takes one -liberty per file and maps across
# them, the way OpenROAD's flow scripts hand them over, and the cells those scripts keep out of
# ASAP7 designs are kept out here. Another library works through LIBERTIES
# (the files, space-separated) and SEQ_LIBERTY (the one with the flip-flops).
#
# A Verilog export (*.v) is read as is; a VHDL export (*.vhd) through the GHDL
# plugin for yosys, the way the VHDL flow's designs are simulated (the reading
# is tools/backend/hdl-read.sh, shared with report-lut6.sh). Memories become
# flip-flops, which is what a 64-entry block buffer is anyway.
#
# Exit status: 0 with a report; 1 when a tool failed; 2 when a tool or the
# library is not installed, nothing was timed.
set -uo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: $0 <hdl-dir> <top-module> [clock-ps] [out-dir]" >&2
  exit 1
fi
HDL_DIR="$1"
TOP="$2"
PERIOD="${3:-1000}"
# Outputs go in a directory of their own: the mapped netlist is Verilog, and
# next to the export it would be read back as part of the design.
LOG_DIR="${4:-$HDL_DIR/timing}"
mkdir -p "$LOG_DIR"

# The library (PDK=asap7, the default, or sky130), the cells kept out of it,
# the ABC script, the boundary conditions and the reset port:
# tools/backend/pdk-lib.sh, shared with the standard-cell backend of the
# dataflow-unit characterization.
source "$(dirname "${BASH_SOURCE[0]}")/pdk-lib.sh" || exit $?
# How the export is read into yosys: tools/backend/hdl-read.sh, shared with
# report-lut6.sh, so that the timing and the LUT count are of one design.
source "$(dirname "${BASH_SOURCE[0]}")/hdl-read.sh"

for tool in yosys; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "report-timing: $tool is not installed; nothing timed" >&2
    exit 2
  fi
done
if [[ -z "$STA" || ! -x "$STA" ]]; then
  echo "report-timing: OpenSTA (sta) is not installed; nothing timed" >&2
  exit 2
fi
if [[ -z "$LIBERTIES" || -z "$SEQ_LIBERTY" || ! -f "$SEQ_LIBERTY" ]]; then
  echo "report-timing: no cell library; set $PDK_DIR_VAR (or LIBERTIES and SEQ_LIBERTY)" >&2
  exit 2
fi

hdl_read_design report-timing "$HDL_DIR" "$TOP" || exit $?

MAPPED="$LOG_DIR/$TOP.mapped.v"
CONSTR="$LOG_DIR/$TOP.abc.constr"
pdk_write_abc_constr "$CONSTR"
# ABC maps toward picoseconds whatever the liberty's unit; OpenSTA speaks the
# liberty's unit, so its clock and its slacks are scaled.
PERIOD_STA=$(awk -v p="$PERIOD" -v s="$TIME_SCALE" 'BEGIN { if (s == 1) print p; else printf "%.4f", p / s }')
DIGITS=$([[ "$TIME_SCALE" == "1" ]] && echo 1 || echo 4)
SYNTH_LOG="$LOG_DIR/$TOP.synth.log"
STA_LOG="$LOG_DIR/$TOP.timing.rpt"

# The adder. Yosys maps every carry chain to a Brent-Kung lookahead unit and
# ABC then rebuilds it as a ripple-carry chain of majority gates, about 28 ps
# a bit on ASAP7: a 64-bit accumulate was 1.9 ns, the Mul body's whole clock.
# On an FPGA the carry chain is dedicated silicon and the question never
# comes up; on a cell library the script has to ask for a parallel-prefix
# adder, and Sklansky is the one that measured best (Mul body 1,930 to
# 1,434 ps for 3% more cells; Kogge-Stone 1,452 for 10% more; Han-Carlson
# 1,488). ADDER=sklansky|kogge-stone|han-carlson picks one, ADDER=yosys
# keeps yosys' own. The characterization (pdk_backend.py) reads the same
# variable, so the timing models are of the same adders as the reports.
ADDER="${ADDER:-sklansky}"
SYNTH_ADDER=""
[[ "$ADDER" != "yosys" ]] && SYNTH_ADDER=" -extra-map +/choices/$ADDER.v"
# Generic synthesis, then the flip-flops from the sequential liberty and the
# logic from the others. `-noexpr` keeps the netlist a plain instance list for
# OpenSTA to link; `-norename` keeps yosys' own names on the nets and cells
# it made, which carry the instance path the flattening prefixed them with,
# so that a path in the report can be placed in the design. The whole yosys
# log goes to the file: `stat` at the end is where the cell counts come from.
# The commands go through a script file, not `-p`: the read command names
# every file of the design, and a network of a few hundred units (the
# decoder's parser, 1,390 files) is longer than one argument may be.
YS_SCRIPT="$LOG_DIR/$TOP.synth.ys"
{
  printf '%s\n' "$READ" | sed 's/; */\n/g'
  echo "synth -top $TOP -flatten$SYNTH_ADDER"
  echo "dfflibmap -liberty $SEQ_LIBERTY"
  echo "abc $LIB_ARGS -constr $CONSTR -D $PERIOD -script $ABC_SCRIPT"
  echo "opt_clean"
  # stat with every liberty, the macros' included (MACRO_LIBS): the cell
  # count and the cell area, a macro one cell at the liberty's area.
  echo "stat$(for lib in $LIBERTIES ${MACRO_LIBS:-}; do printf ' -liberty %s' "$lib"; done)"
  echo "write_verilog -noattr -noexpr -norename $MAPPED"
} > "$YS_SCRIPT"
if ! "${YOSYS[@]}" -s "$YS_SCRIPT" > "$SYNTH_LOG" 2>&1; then
  echo "report-timing: yosys failed on $TOP (see $SYNTH_LOG)" >&2
  tail -5 "$SYNTH_LOG" >&2
  exit 1
fi
# yosys writes `wire signed [31:0] x;` for a design's signed locals (picorv32.v
# has two) and OpenSTA's Verilog reader rejects the keyword. Nothing in a
# netlist's timing depends on a declaration's signedness.
sed -i 's/^\(\s*\(wire\|reg\|input\|output\)\) signed /\1 /' "$MAPPED"

if [[ "${PLACE:-0}" == "1" ]]; then
  # OpenROAD: floorplan, place, parasitics, repair, time. Its STA is OpenSTA,
  # so the constraints and the report are the ones below, with the wires in.
  if [[ -z "$OPENROAD" || ! -x "$OPENROAD" ]]; then
    echo "report-timing: PLACE=1 needs OpenROAD (openroad on the path, or OPENROAD)" >&2
    exit 2
  fi
  if [[ ! -f "$PDK_TECH_LEF" ]]; then
    echo "report-timing: PLACE=1 needs the technology LEF ($PDK_TECH_LEF)" >&2
    exit 2
  fi
  OR_SCRIPT="$LOG_DIR/$TOP.place.tcl"
  OR_LOG="$LOG_DIR/$TOP.place.log"
  REPAIRED="$LOG_DIR/$TOP.placed.v"
  {
    echo "read_lef $PDK_TECH_LEF"
    for lef in $PDK_CELL_LEFS ${MACRO_LEFS:-}; do echo "read_lef $lef"; done
    for lib in $LIBERTIES ${MACRO_LIBS:-}; do echo "read_liberty $lib"; done
    cat <<EOF
read_verilog $MAPPED
link_design $TOP
create_clock -name clk -period $PERIOD_STA [get_ports clk]
set_input_delay 0 -clock clk [delete_from_list [all_inputs] [get_ports clk]]
set_output_delay 0 -clock clk [all_outputs]
set_false_path -from [get_ports $RESET_PORT]
puts "SYNTH_WNS [format %.${DIGITS}f [sta::worst_slack -max]]"
initialize_floorplan -utilization ${UTILIZATION:-50} -aspect_ratio 1 -core_space 2 -site $PDK_SITE
EOF
    if [[ -n "$PDK_TRACKS" ]]; then echo "source $PDK_TRACKS"; else echo "make_tracks"; fi
    cat <<EOF
place_pins -hor_layers $PDK_PINS_H -ver_layers $PDK_PINS_V
global_placement -density ${PLACE_DENSITY:-0.6}
source $PDK_SET_RC
estimate_parasitics -placement
puts "PLACED_WNS [format %.${DIGITS}f [sta::worst_slack -max]]"
set_max_fanout $MAX_FANOUT [current_design]
repair_design
estimate_parasitics -placement
report_checks -path_delay max -group_count 5 -format full_clock_expanded -digits $DIGITS
puts "WNS [format %.${DIGITS}f [sta::worst_slack -max]]"
puts "TNS [format %.${DIGITS}f [sta::total_negative_slack -max]]"
write_verilog $REPAIRED
exit
EOF
  } > "$OR_SCRIPT"
  if ! "$OPENROAD" -no_init -no_splash -exit "$OR_SCRIPT" > "$OR_LOG" 2>&1; then
    echo "report-timing: openroad failed on $TOP (see $OR_LOG)" >&2
    grep -m3 "ERROR" "$OR_LOG" >&2
    exit 1
  fi
  STA_LOG="$OR_LOG"
  INSERTED=$(grep -o "Inserted [0-9]* buffers" "$OR_LOG" | awk '{s += $2} END {print s + 0}')
  RESIZED=$(grep -o "Resized [0-9]* instances" "$OR_LOG" | awk '{s += $2} END {print s + 0}')
  SYNTH_WNS=$(grep -m1 "^SYNTH_WNS" "$OR_LOG" | awk '{print $2}')
  PLACED_WNS=$(grep -m1 "^PLACED_WNS" "$OR_LOG" | awk '{print $2}')
else
STA_SCRIPT="$LOG_DIR/$TOP.sta.tcl"
{
  for lib in $LIBERTIES ${MACRO_LIBS:-}; do
    echo "read_liberty $lib"
  done
  cat <<EOF
read_verilog $MAPPED
link_design $TOP
create_clock -name clk -period $PERIOD_STA [get_ports clk]
set_input_delay 0 -clock clk [delete_from_list [all_inputs] [get_ports clk]]
set_output_delay 0 -clock clk [all_outputs]
set_false_path -from [get_ports $RESET_PORT]
report_checks -path_delay max -group_path_count 5 -format full_clock_expanded -digits $DIGITS
puts "WNS [format %.${DIGITS}f [sta::worst_slack -max]]"
puts "TNS [format %.${DIGITS}f [sta::total_negative_slack -max]]"
exit
EOF
} > "$STA_SCRIPT"
if ! "$STA" -no_init -no_splash -exit "$STA_SCRIPT" > "$STA_LOG" 2>&1; then
  echo "report-timing: sta failed on $TOP (see $STA_LOG)" >&2
  tail -5 "$STA_LOG" >&2
  exit 1
fi
fi

WNS=$(grep -m1 "^WNS" "$STA_LOG" | awk '{print $2}')
if [[ -z "$WNS" ]]; then
  echo "report-timing: no slack in $STA_LOG" >&2
  exit 1
fi
CRITICAL=$(awk -v p="$PERIOD" -v w="$WNS" -v s="$TIME_SCALE" 'BEGIN { printf "%.1f", p - w * s }')
GHZ=$(awk -v c="$CRITICAL" 'BEGIN { if (c > 0) printf "%.2f", 1000 / c; else print "-" }')
# The last `stat` table, with -liberty: "   N   AREA cells", then
# "   N   AREA   CELLNAME" per type ("-" for an area the libraries lack;
# the area may be printed as 1.57E+03). A cell type's line has three spaces
# before its name, the summary lines above it one. The library's own cells
# match CELL_RE; what is neither those nor yosys' own ($scopeinfo) is a
# macro, counted with the liberty's area.
NUM='[0-9.Ee+-]+'
CELLS=$(grep -E "^\s+[0-9]+ +$NUM cells$" "$SYNTH_LOG" | tail -1 | awk '{print $1}')
AREA=$(grep -E "^\s+[0-9]+ +$NUM cells$" "$SYNTH_LOG" | tail -1 | awk '{printf "%.1f", $2}')
FLOPS=$(awk -v n="$NUM" -v re="$FLOP_RE" '$0 ~ "^ +[0-9]+ +" n " cells$" {s = 0} $0 ~ "^ +[0-9]+ +" n " +" re {s += $1} END {print s + 0}' "$SYNTH_LOG")
BUFS=$(awk -v n="$NUM" -v re="$BUF_RE" '$0 ~ "^ +[0-9]+ +" n " cells$" {s = 0} $0 ~ "^ +[0-9]+ +" n " +" re {s += $1} END {print s + 0}' "$SYNTH_LOG")
MACROS=$(awk -v n="$NUM" -v re="$CELL_RE" '$0 ~ "^ +[0-9]+ +" n " cells$" {s = ""} $0 ~ "^ +[0-9]+ +" n "   [A-Za-z_]" && $3 !~ re {s = s sprintf("%s%d x %s (%.3f um2 each)", (s == "" ? "" : ", "), $1, $3, $2 / $1)} END {print s}' "$SYNTH_LOG")
if [[ "${PLACE:-0}" == "1" ]]; then
  echo "report-timing: $TOP on $PDK_LABEL, placed and repaired (${UTILIZATION:-50}% utilization)"
  echo "  cells $CELLS, flip-flops $FLOPS, fan-out buffers $BUFS, cell area $AREA um2 (after synthesis)"
  echo "  repair: $INSERTED buffers inserted, $RESIZED instances resized"
  echo "  slack before placement $SYNTH_WNS, placed $PLACED_WNS, repaired $WNS (${TIME_SCALE}x ps)"
else
  echo "report-timing: $TOP on $PDK_LABEL, post-synthesis"
  echo "  cells $CELLS, flip-flops $FLOPS, fan-out buffers $BUFS, cell area $AREA um2"
fi
[[ -n "$MACROS" ]] && echo "  macros: $MACROS"
echo "  critical path $CRITICAL ps at a $PERIOD ps clock (slack $WNS): up to $GHZ GHz"
echo "  paths: $STA_LOG"
exit 0
