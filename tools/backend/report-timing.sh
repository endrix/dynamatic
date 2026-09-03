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
# flip-flop, is a false path. The library is
# ASAP7 (RVT, typical corner) as streamblocks' install_synthesis_tools.sh lays
# it out: ASAP7_DIR holds the five RVT TT liberty files, unpacked. Yosys'
# abc takes one -liberty per file and maps across them, the way OpenROAD's
# flow scripts hand them over, and the cells those scripts keep out of
# ASAP7 designs are kept out here. Another library works through LIBERTIES
# (the files, space-separated) and SEQ_LIBERTY (the one with the flip-flops).
#
# A Verilog export (*.v) is read as is; a VHDL export (*.vhd) through the GHDL
# plugin for yosys, the way the VHDL flow's designs are simulated. Memories
# become flip-flops, which is what a 64-entry block buffer is anyway.
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

ASAP7_DIR="${ASAP7_DIR:-}"
LIBERTIES="${LIBERTIES:-$(ls "${ASAP7_DIR:-/nonexistent}"/asap7sc7p5t_*_RVT_TT_nldm_*.lib 2>/dev/null | tr '\n' ' ')}"
SEQ_LIBERTY="${SEQ_LIBERTY:-$(ls "${ASAP7_DIR:-/nonexistent}"/asap7sc7p5t_SEQ_RVT_TT_nldm_*.lib 2>/dev/null | head -1)}"
DONT_USE="${DONT_USE:-*x1p*_ASAP7* *xp*_ASAP7* SDF* ICG*}"
MAX_FANOUT="${MAX_FANOUT:-12}"
RESET_PORT="${RESET_PORT:-rst}"
# What drives the inputs and loads the outputs during mapping: the flow
# scripts' figures for ASAP7.
DRIVER_CELL="${DRIVER_CELL:-BUFx2_ASAP7_75t_R}"
LOAD_FF="${LOAD_FF:-3.898}"
STA="${STA:-$(command -v sta || true)}"

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
  echo "report-timing: no cell library; set ASAP7_DIR (or LIBERTIES and SEQ_LIBERTY)" >&2
  exit 2
fi
LIB_ARGS=""
for lib in $LIBERTIES; do
  LIB_ARGS="$LIB_ARGS -liberty $lib"
done
for pattern in $DONT_USE; do
  LIB_ARGS="$LIB_ARGS -dont_use $pattern"
done
# Yosys' own constrained liberty script for ABC, with the buffering told
# to cover primary inputs (register outputs, after dfflibmap) and to stop at
# MAX_FANOUT loads. Commas stand for spaces in a +script; {D} is the clock.
ABC_SCRIPT="+strash;&get,-n;&fraig,-x;&put;scorr;dc2;dretime;strash;&get,-n;&dch,-f;&nf,{D};&put;buffer,-p,-N,$MAX_FANOUT;upsize,{D};dnsize,{D};stime,-p"

VERILOG=$(ls "$HDL_DIR"/*.v 2>/dev/null | tr '\n' ' ')
VHDL=$(ls "$HDL_DIR"/*.vhd 2>/dev/null | tr '\n' ' ')
if [[ -n "$VERILOG" ]]; then
  READ="read_verilog -sv -noassert $VERILOG; hierarchy -top $TOP"
  YOSYS=(yosys)
elif [[ -n "$VHDL" ]]; then
  if ! yosys -q -m ghdl -p "" >/dev/null 2>&1; then
    echo "report-timing: the GHDL plugin for yosys is not installed; VHDL not timed" >&2
    exit 2
  fi
  FILES="$(ls "$HDL_DIR"/types.vhd 2>/dev/null || true)"
  for f in $VHDL; do
    case "$(basename "$f")" in
      types.vhd|"$TOP.vhd") continue ;;
    esac
    FILES="$FILES $f"
  done
  FILES="$FILES $HDL_DIR/$TOP.vhd"
  READ="ghdl --std=08 -fsynopsys $FILES -e $TOP; hierarchy -top $TOP"
  YOSYS=(yosys -m ghdl)
else
  echo "report-timing: no Verilog or VHDL file in $HDL_DIR" >&2
  exit 1
fi

MAPPED="$LOG_DIR/$TOP.mapped.v"
CONSTR="$LOG_DIR/$TOP.abc.constr"
printf 'set_driving_cell %s\nset_load %s\n' "$DRIVER_CELL" "$LOAD_FF" > "$CONSTR"
SYNTH_LOG="$LOG_DIR/$TOP.synth.log"
STA_LOG="$LOG_DIR/$TOP.timing.rpt"

# Generic synthesis, then the flip-flops from the sequential liberty and the
# logic from the others. `-noexpr` keeps the netlist a plain instance list for
# OpenSTA to link. The whole yosys log goes to the file: `stat` at the end is
# where the cell counts come from.
if ! "${YOSYS[@]}" -p "$READ; synth -top $TOP -flatten; dfflibmap -liberty $SEQ_LIBERTY; abc $LIB_ARGS -constr $CONSTR -D $PERIOD -script $ABC_SCRIPT; opt_clean; stat; write_verilog -noattr -noexpr $MAPPED" > "$SYNTH_LOG" 2>&1; then
  echo "report-timing: yosys failed on $TOP (see $SYNTH_LOG)" >&2
  tail -5 "$SYNTH_LOG" >&2
  exit 1
fi

STA_SCRIPT="$LOG_DIR/$TOP.sta.tcl"
{
  for lib in $LIBERTIES; do
    echo "read_liberty $lib"
  done
  cat <<EOF
read_verilog $MAPPED
link_design $TOP
create_clock -name clk -period $PERIOD [get_ports clk]
set_input_delay 0 -clock clk [delete_from_list [all_inputs] [get_ports clk]]
set_output_delay 0 -clock clk [all_outputs]
set_false_path -from [get_ports $RESET_PORT]
report_checks -path_delay max -group_path_count 5 -format full_clock_expanded -digits 1
puts "WNS [format %.1f [sta::worst_slack -max]]"
puts "TNS [format %.1f [sta::total_negative_slack -max]]"
exit
EOF
} > "$STA_SCRIPT"
if ! "$STA" -no_init -no_splash -exit "$STA_SCRIPT" > "$STA_LOG" 2>&1; then
  echo "report-timing: sta failed on $TOP (see $STA_LOG)" >&2
  tail -5 "$STA_LOG" >&2
  exit 1
fi

WNS=$(grep -m1 "^WNS" "$STA_LOG" | awk '{print $2}')
if [[ -z "$WNS" ]]; then
  echo "report-timing: no slack in $STA_LOG" >&2
  exit 1
fi
CRITICAL=$(awk -v p="$PERIOD" -v w="$WNS" 'BEGIN { printf "%.1f", p - w }')
GHZ=$(awk -v c="$CRITICAL" 'BEGIN { if (c > 0) printf "%.2f", 1000 / c; else print "-" }')
# The last `stat` table: "   N cells", then "   N   CELLNAME" per type.
CELLS=$(grep -E "^\s+[0-9]+ cells$" "$SYNTH_LOG" | tail -1 | awk '{print $1}')
FLOPS=$(awk '/^ +[0-9]+ cells$/ {n = 0; s = 0} /^ +[0-9]+ +DFF[A-Za-z0-9]*_ASAP7/ {s += $1} END {print s + 0}' "$SYNTH_LOG")
BUFS=$(awk '/^ +[0-9]+ cells$/ {s = 0} /^ +[0-9]+ +BUF[a-z0-9]*_ASAP7/ {s += $1} END {print s + 0}' "$SYNTH_LOG")
echo "report-timing: $TOP on ASAP7 RVT TT, post-synthesis"
echo "  cells $CELLS, flip-flops $FLOPS, fan-out buffers $BUFS"
echo "  critical path $CRITICAL ps at a $PERIOD ps clock (slack $WNS): up to $GHZ GHz"
echo "  paths: $STA_LOG"
exit 0
