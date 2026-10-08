#!/usr/bin/env bash
# fakeram7.sh <hdl-dir> [out-dir] -- the ASAP7 SRAM macros an export's SRAM
# views instantiate, generated with FakeRAM2.0, one per size.
#
# A handshake.ram above the generator's sram_threshold gets a synthesis view
# under <hdl-dir>/sram/ that wraps a macro named after its own size
# (rtl-config's sram_name, fakeram7_<words>x<bits>). ASAP7 ships no memory
# compiler, so the macros are FakeRAM2.0's: a liberty, a LEF and a Verilog
# model per macro, the area from the ASAP7 bitcell and track pitches. Every
# macro a view names is generated once into <out-dir>/<name>/ (reused when
# it is there), and the two lines printed are what report-timing.sh reads,
# for the caller to eval:
#
#   eval "$(tools/backend/fakeram7.sh <hdl-dir> <out-dir>)"
#   HDL_SRAM=1 PDK=asap7 tools/backend/report-timing.sh <hdl-dir> <top> ...
#
# A report then counts each macro as one cell at its liberty's area, and
# names them on its "macros:" line. FakeRAM2.0's area depends on the size;
# its timing and power do not (every macro has the same 218 ps access time
# and the same 129 uW leakage, constants in its class_memory.py), so the
# area is the only figure of a macro this measures.
#
# The Verilog model FakeRAM2.0 writes beside each macro ORs a store into the
# word already there (`mem[addr_in] <= (wd_in) | (mem[addr_in])`: its write
# mask was taken out and the masking expression left behind, upstream as of
# b6b1c83), so a simulation of it reads wrong data after the first store to
# an address. The model is rewritten here to overwrite the word, the way the
# liberty's one read-write port and the flop model behave; the liberty and
# the LEF are untouched. A model that does not have the line is an error,
# not a silent pass: a FakeRAM2.0 that changed it needs this read again.
#
# FAKERAM_DIR is a FakeRAM2.0 checkout (install_synthesis_tools.sh puts one
# in the synthesis prefix); PYTHON runs it (python3 by default; it needs
# nothing outside the standard library).
#
# Exit status: 0 with the two lines (empty values when the export has no
# SRAM view); 1 when FakeRAM2.0 failed; 2 when it is not installed.
set -uo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <hdl-dir> [out-dir]" >&2
  exit 1
fi
HDL_DIR="$1"
OUT_DIR="$(mkdir -p "${2:-$HDL_DIR/sram/macros}" && cd "${2:-$HDL_DIR/sram/macros}" && pwd)"
PYTHON="${PYTHON:-python3}"

# The macros the views declare, "<name> <words> <bits>" each, once.
mapfile -t MACROS < <(grep -ho "component fakeram7_[0-9]*x[0-9]*" "$HDL_DIR"/sram/*.vhd 2>/dev/null \
  | awk '{print $2}' | sort -u | sed 's/^fakeram7_\([0-9]*\)x\([0-9]*\)$/fakeram7_\1x\2 \1 \2/')
if [[ ${#MACROS[@]} -eq 0 ]]; then
  echo "MACRO_LIBS=''"
  echo "MACRO_LEFS=''"
  exit 0
fi

# The ones not generated yet, in one configuration: ASAP7's pitches (M4 pins,
# 48 nm tracks, 54 nm poly, 27 nm fins), as FakeRAM2.0's own example sets
# them, one bank, no column mux.
TODO=()
for m in "${MACROS[@]}"; do
  read -r name words bits <<<"$m"
  [[ -s "$OUT_DIR/$name/$name.lib" && -s "$OUT_DIR/$name/$name.lef" ]] || TODO+=("$name $words $bits")
done
if [[ ${#TODO[@]} -gt 0 ]]; then
  if [[ -z "${FAKERAM_DIR:-}" || ! -f "$FAKERAM_DIR/run.py" ]]; then
    echo "fakeram7: no FakeRAM2.0 (set FAKERAM_DIR to a checkout); no macros generated" >&2
    exit 2
  fi
  CFG="$OUT_DIR/fakeram7.cfg"
  {
    cat <<'EOF'
{
  "tech_nm": 7,
  "voltage": 0.7,
  "metal_prefix": "M",
  "metal_layer": "M4",
  "pin_width_nm": 24,
  "pin_pitch_nm": 48,
  "metal_track_pitch_nm": 48,
  "manufacturing_grid_nm": 1,
  "contacted_poly_pitch_nm": 54,
  "column_mux_factor": 1,
  "fin_pitch_nm": 27,
  "snap_width_nm": 190,
  "snap_height_nm": 1400,
  "srams": [
EOF
    sep=""
    for m in "${TODO[@]}"; do
      read -r name words bits <<<"$m"
      printf '%s    {"name": "%s", "width": %d, "depth": %d, "banks": 1}' "$sep" "$name" "$bits" "$words"
      sep=$',\n'
    done
    printf '\n  ]\n}\n'
  } > "$CFG"
  # run.py imports its utils/ relative to itself, from any directory.
  if ! "$PYTHON" "$FAKERAM_DIR/run.py" "$CFG" --output_dir "$OUT_DIR" > "$OUT_DIR/fakeram7.log" 2>&1; then
    echo "fakeram7: FakeRAM2.0 failed (see $OUT_DIR/fakeram7.log)" >&2
    tail -5 "$OUT_DIR/fakeram7.log" >&2
    exit 1
  fi
fi

# The store: overwrite, not OR (above), in every model, a reused one too
# (one generated before this correction existed); a corrected one is left.
for m in "${MACROS[@]}"; do
  read -r name _ <<<"$m"
  v="$OUT_DIR/$name/$name.v"
  sed -i 's/mem\[addr_in\] <= (wd_in) | (mem\[addr_in\]);/mem[addr_in] <= wd_in;/' "$v" 2>/dev/null
  if ! grep -q 'mem\[addr_in\] <= wd_in;' "$v" 2>/dev/null; then
    echo "fakeram7: $v has neither FakeRAM2.0's OR-ing store nor the corrected one; not corrected" >&2
    exit 1
  fi
done

LIBS="" LEFS=""
for m in "${MACROS[@]}"; do
  read -r name _ <<<"$m"
  if [[ ! -s "$OUT_DIR/$name/$name.lib" ]]; then
    echo "fakeram7: FakeRAM2.0 wrote no $name.lib (see $OUT_DIR/fakeram7.log)" >&2
    exit 1
  fi
  LIBS="$LIBS${LIBS:+ }$OUT_DIR/$name/$name.lib"
  LEFS="$LEFS${LEFS:+ }$OUT_DIR/$name/$name.lef"
done
echo "MACRO_LIBS='$LIBS'"
echo "MACRO_LEFS='$LEFS'"
