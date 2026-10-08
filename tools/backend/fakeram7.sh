#!/usr/bin/env bash
# fakeram7.sh <hdl-dir> [out-dir] -- the ASAP7 SRAM macros an export's SRAM
# views instantiate, generated with FakeRAM2.0, one per size.
#
# A handshake.ram above the generator's sram_threshold gets a synthesis view
# under <hdl-dir>/sram/ that wraps a macro named after its own size:
# fakeram7_dp_<words>x<bits>, a dual-port RAM (the store on one port, the
# load on the other), or fakeram7_<words>x<bits>, a one-port RAM where the
# memory needs one port (its PORTS parameter, from the front end).
# ASAP7 ships no memory compiler, so the macros are FakeRAM2.0's: a liberty,
# a LEF and a Verilog model per macro, the area from the ASAP7 bitcell and
# track pitches. Every macro a view names is generated once into
# <out-dir>/<name>/ (reused when it is there), and the two lines printed are
# what report-timing.sh reads, for the caller to eval:
#
#   eval "$(tools/backend/fakeram7.sh <hdl-dir> <out-dir>)"
#   HDL_SRAM=1 PDK=asap7 tools/backend/report-timing.sh <hdl-dir> <top> ...
#
# A report then counts each macro as one cell at its liberty's area, and
# names them on its "macros:" line. FakeRAM2.0's area depends on the size
# and not on the ports: a dual-port macro has the one-port macro's area,
# where a real two-port bitcell is larger, so a dual-port area is a lower
# bound. Its timing and power do not depend on the size either (every macro
# has the same access time and leakage, constants in its model), so the area
# is the only figure of a macro this measures.
#
# The Verilog models are corrected for simulation, the liberty and the LEF
# left as they are:
#   - the dual-port model registers the address and then reads the
#     registered address (`addr_a_reg <= addr_a; dout_a <= mem[addr_a_reg]`),
#     a read two cycles after its address where the liberty has one clock to
#     dout arc and the flop model reads in one: it is rewritten to read the
#     address it samples (`dout_a <= mem[addr_a]`), on both ports. Both ports
#     are clocked by clk_a in the model; the views tie clk_a and clk_b to
#     the one design clock, so that is the same thing.
#   - the one-port model of FakeRAM2.0 before it moved into OpenROAD's flow
#     scripts ORs a store into the word already there
#     (`mem[addr_in] <= (wd_in) | (mem[addr_in])`, a write mask's expression
#     left behind); a model that has it is rewritten to overwrite.
# A model that has neither the line to correct nor the corrected one is an
# error, not a silent pass: a FakeRAM2.0 that changed it needs reading again.
#
# FAKERAM_DIR is a FakeRAM2.0 checkout: OpenROAD-flow-scripts'
# tools/FakeRAM2.0, which install_synthesis_tools.sh copies into the
# synthesis prefix (the standalone repository has no dual-port RAM); PYTHON
# runs it (python3 by default; it needs nothing outside the standard library).
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

# The macros the views declare, "<name> <words> <bits> <SP|DP>" each, once.
mapfile -t MACROS < <(grep -hoE "component fakeram7_(dp_)?[0-9]+x[0-9]+" "$HDL_DIR"/sram/*.vhd 2>/dev/null \
  | awk '{print $2}' | sort -u \
  | sed -E 's/^(fakeram7_dp_([0-9]+)x([0-9]+))$/\1 \2 \3 DP/; s/^(fakeram7_([0-9]+)x([0-9]+))$/\1 \2 \3 SP/')
if [[ ${#MACROS[@]} -eq 0 ]]; then
  echo "MACRO_LIBS=''"
  echo "MACRO_LEFS=''"
  exit 0
fi

# The ones not generated yet, one configuration per port count: ASAP7's
# pitches (M4 pins, 48 nm tracks, 54 nm poly, 27 nm fins), as FakeRAM2.0's
# own example sets them, one bank, no column mux.
for ports in SP DP; do
  TODO=()
  for m in "${MACROS[@]}"; do
    read -r name words bits kind <<<"$m"
    [[ "$kind" == "$ports" ]] || continue
    [[ -s "$OUT_DIR/$name/$name.lib" && -s "$OUT_DIR/$name/$name.lef" ]] || TODO+=("$name $words $bits")
  done
  [[ ${#TODO[@]} -gt 0 ]] || continue
  if [[ -z "${FAKERAM_DIR:-}" || ! -f "$FAKERAM_DIR/run.py" ]]; then
    echo "fakeram7: no FakeRAM2.0 (set FAKERAM_DIR to a checkout); no macros generated" >&2
    exit 2
  fi
  CFG="$OUT_DIR/fakeram7-$ports.cfg"
  {
    cat <<EOF
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
  "memory_type": "RAM",
  "port_configuration": "$ports",
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
  if ! "$PYTHON" "$FAKERAM_DIR/run.py" "$CFG" --output_dir "$OUT_DIR" > "$OUT_DIR/fakeram7-$ports.log" 2>&1; then
    echo "fakeram7: FakeRAM2.0 failed (see $OUT_DIR/fakeram7-$ports.log)" >&2
    tail -5 "$OUT_DIR/fakeram7-$ports.log" >&2
    exit 1
  fi
done

# The models, corrected (above), every one, a reused one too; a corrected
# one is left as it is.
for m in "${MACROS[@]}"; do
  read -r name _ _ kind <<<"$m"
  v="$OUT_DIR/$name/$name.v"
  if [[ "$kind" == DP ]]; then
    sed -i -E '/^\s*addr_[ab]_reg <= addr_[ab];\s*$/d; /^\s*reg .* addr_[ab]_reg;\s*$/d; s/(dout_([ab]) <= mem\[)addr_[ab]_reg\]/\1addr_\2]/' "$v" 2>/dev/null
    if grep -q 'mem\[addr_[ab]_reg\]' "$v" 2>/dev/null \
       || [[ "$(grep -cE 'dout_([ab]) <= mem\[addr_\1\];' "$v" 2>/dev/null)" != 2 ]]; then
      echo "fakeram7: $v reads neither through addr_a_reg/addr_b_reg nor the address it samples; not corrected" >&2
      exit 1
    fi
  else
    sed -i 's/mem\[addr_in\] <= (wd_in) | (mem\[addr_in\]);/mem[addr_in] <= wd_in;/' "$v" 2>/dev/null
    if ! grep -q 'mem\[addr_in\] <= wd_in;' "$v" 2>/dev/null; then
      echo "fakeram7: $v has neither the OR-ing store nor the overwriting one; not corrected" >&2
      exit 1
    fi
  fi
done

LIBS="" LEFS=""
for m in "${MACROS[@]}"; do
  read -r name _ <<<"$m"
  if [[ ! -s "$OUT_DIR/$name/$name.lib" ]]; then
    echo "fakeram7: FakeRAM2.0 wrote no $name.lib (see $OUT_DIR/fakeram7-*.log)" >&2
    exit 1
  fi
  LIBS="$LIBS${LIBS:+ }$OUT_DIR/$name/$name.lib"
  LEFS="$LEFS${LEFS:+ }$OUT_DIR/$name/$name.lef"
done
echo "MACRO_LIBS='$LIBS'"
echo "MACRO_LEFS='$LEFS'"
