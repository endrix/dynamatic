#!/usr/bin/env bash
# report-lut6.sh <hdl-dir> <top-module> [out-dir]
#
# Maps an exported design to 6-input lookup tables with yosys and reports how
# many it took, how many flip-flops, and the longest combinational path in
# LUTs: the FPGA-side proxy for the design report-timing.sh times on ASAP7.
# No device library and no placement: `abc -lut 6` maps the logic to 6-input
# functions of no particular family, so the LUT count is a count of those
# functions and the depth a count of them in a row. Two versions of one
# design compare on these; a vendor's report does not.
#
# The export is read the way report-timing.sh reads it (tools/backend/
# hdl-read.sh, shared): Verilog as is, VHDL through the GHDL plugin.
# Memories become flip-flops, as there.
#
# yosys prints a `stat` table more than once in a run (synth's own, then the
# one asked for here); the counts are from the last one only, after the
# mapping. The depth is `ltp -noff`'s longest topological path with the
# flip-flops cut, in LUTs.
#
# Exit status: 0 with a report; 1 when a tool failed; 2 when a tool is not
# installed, nothing was mapped.
set -uo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: $0 <hdl-dir> <top-module> [out-dir]" >&2
  exit 1
fi
HDL_DIR="$1"
TOP="$2"
LOG_DIR="${3:-$HDL_DIR/lut6}"
mkdir -p "$LOG_DIR"

source "$(dirname "${BASH_SOURCE[0]}")/hdl-read.sh"

if ! command -v yosys >/dev/null 2>&1; then
  echo "report-lut6: yosys is not installed; nothing mapped" >&2
  exit 2
fi
hdl_read_design report-lut6 "$HDL_DIR" "$TOP" || exit $?

SYNTH_LOG="$LOG_DIR/$TOP.lut6.log"
if ! "${YOSYS[@]}" -p "$READ; synth -top $TOP -flatten; abc -lut 6; opt_clean; ltp -noff; stat" > "$SYNTH_LOG" 2>&1; then
  echo "report-lut6: yosys failed on $TOP (see $SYNTH_LOG)" >&2
  tail -5 "$SYNTH_LOG" >&2
  exit 1
fi

# The last `stat` table: "   N cells", then "   N   CELLNAME" per type. Every
# table resets the sums, so the last one is what remains.
LUTS=$(awk '/^ +[0-9]+ cells$/ {s = 0} /^ +[0-9]+ +\$lut$/ {s += $1} END {print s + 0}' "$SYNTH_LOG")
FLOPS=$(awk '/^ +[0-9]+ cells$/ {s = 0} /^ +[0-9]+ +\$_[A-Z]*DFF[A-Z0-9_]*_$/ {s += $1} END {print s + 0}' "$SYNTH_LOG")
CELLS=$(grep -E "^\s+[0-9]+ cells$" "$SYNTH_LOG" | tail -1 | awk '{print $1}')
LEVELS=$(grep -oE "Longest topological path in .* \(length=[0-9]+\)" "$SYNTH_LOG" | tail -1 | grep -oE "[0-9]+\)$" | tr -dc 0-9)
if [[ -z "$CELLS" || -z "$LEVELS" ]]; then
  echo "report-lut6: no stat table or no path in $SYNTH_LOG" >&2
  exit 1
fi

echo "report-lut6: $TOP mapped to 6-input LUTs, no device, no placement"
echo "  LUTs $LUTS, flip-flops $FLOPS, cells $CELLS"
echo "  longest path $LEVELS LUTs"
echo "  log: $SYNTH_LOG"
exit 0
