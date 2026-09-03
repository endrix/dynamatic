#!/usr/bin/env bash
# check-logic-loops.sh <hdl-dir> <top-module> [log-file]
#
# Flattens an exported design under its top module and asks yosys whether any
# combinational loop remains. Simulators settle such loops and report nothing,
# and buffer placement has no timing model for every unit that can close one
# (join, lazy fork, blocker), so the flattened check is the one place a ring
# shows up before synthesis.
#
# A Verilog export (*.v) is read as is; a module the Verilog flow emits as VHDL
# (the LSQ) is left as a black box, and a loop through its internals is not
# this check's business. A VHDL export (*.vhd) is read through the GHDL plugin
# for yosys, the way the VHDL flow's designs are simulated.
#
# Exit status: 0 no loop; 1 a loop, or yosys failed (the log says which);
# 2 the tools are not installed, nothing was checked.
set -uo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: $0 <hdl-dir> <top-module> [log-file]" >&2
  exit 1
fi
HDL_DIR="$1"
TOP="$2"
LOG="${3:-$HDL_DIR/logic-loops.log}"

if ! command -v yosys >/dev/null 2>&1; then
  echo "check-logic-loops: yosys is not installed; nothing checked" >&2
  exit 2
fi

# One line each: yosys reads a newline in its script as a command separator.
VERILOG=$(ls "$HDL_DIR"/*.v 2>/dev/null | tr '\n' ' ')
VHDL=$(ls "$HDL_DIR"/*.vhd 2>/dev/null | tr '\n' ' ')
if [[ -n "$VERILOG" ]]; then
  # The netlist itself: the flattened check does not care about a wrapper's
  # ports, and the top module is the wrapper or the kernel, whichever exists.
  SCRIPT="read_verilog -sv -noassert $VERILOG; hierarchy -top $TOP; flatten; check"
  YOSYS=(yosys -q -p "$SCRIPT")
elif [[ -n "$VHDL" ]]; then
  if ! yosys -q -m ghdl -p "" >/dev/null 2>&1; then
    echo "check-logic-loops: the GHDL plugin for yosys is not installed; VHDL not checked" >&2
    exit 2
  fi
  # Package and entity files first, the top last, the way the VHDL flow reads
  # them; the elaborated design is then flattened and checked like Verilog.
  FILES="$(ls "$HDL_DIR"/types.vhd 2>/dev/null || true)"
  for f in $VHDL; do
    case "$(basename "$f")" in
      types.vhd|"$TOP.vhd") continue ;;
    esac
    FILES="$FILES $f"
  done
  FILES="$FILES $HDL_DIR/$TOP.vhd"
  SCRIPT="ghdl --std=08 -fsynopsys $FILES -e $TOP; prep -top $TOP; flatten; check"
  YOSYS=(yosys -q -m ghdl -p "$SCRIPT")
else
  echo "check-logic-loops: no Verilog or VHDL file in $HDL_DIR" >&2
  exit 1
fi

# `check` also reports undriven wires, which a black box leaves behind by
# design, so it runs without -assert and only a loop fails the check.
if ! "${YOSYS[@]}" > "$LOG" 2>&1; then
  echo "check-logic-loops: yosys failed on $TOP (see $LOG)" >&2
  tail -5 "$LOG" >&2
  exit 1
fi
if grep -qi "logic loop" "$LOG"; then
  echo "check-logic-loops: combinational loop in $TOP (see $LOG)" >&2
  grep -i -A3 "logic loop" "$LOG" | head -12 >&2
  exit 1
fi
echo "check-logic-loops: $TOP is free of combinational loops"
exit 0
