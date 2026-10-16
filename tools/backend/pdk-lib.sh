# pdk-lib.sh -- the cell library a design or a unit is mapped to. Sourced,
# never run.
#
# PDK names the recipe: `asap7` (the default) or `sky130`, each a file
# <pdk>-lib.sh beside this one. report-timing.sh times a whole exported
# design against it; the standard-cell backend of
# tools/backend/synth-characterization times one dataflow unit at a time
# against it. Every recipe defines the same names, so that the two are one
# flow on any library:
#
#   LIBERTIES     the liberty files, space-separated; SEQ_LIBERTY the one
#                 that holds the flip-flops (dfflibmap takes one file)
#   LIB_ARGS      `-liberty` per file and `-dont_use` per excluded cell,
#                 the way yosys' abc takes them
#   DFF_ARGS      dfflibmap's `-dont_use` per flip-flop kept out of the
#                 mapping (empty, or starting with a space)
#   MAX_FANOUT    loads above which ABC buffers a net while it maps
#   RESET_PORT    the quasi-static input that is a false path
#   DRIVER_CELL   what drives every input during mapping, LOAD_FF the load
#                 on every output (femtofarads, as OpenROAD's flow scripts
#                 hand them to ABC)
#   ABC_SCRIPT    yosys' constrained-liberty script for ABC, without the
#                 rewriting (dc2, dretime) that would undo a prefix adder
#   STA           the OpenSTA binary
#   PDK_LABEL     the library and corner, for a report's first line
#   PDK_DIR_VAR   the environment variable that locates the library
#   TIME_SCALE    picoseconds per liberty time unit: 1 for a library in
#                 picoseconds (ASAP7), 1000 for one in nanoseconds (sky130).
#                 ABC's -D is always picoseconds; OpenSTA speaks the
#                 liberty's unit, and a report is converted back to ps.
#   FLOP_RE, BUF_RE, CELL_RE
#                 awk regular expressions naming the library's flip-flops,
#                 its buffers, and any of its cells (what is neither a cell
#                 nor yosys' own is a macro)
#   PDK_TECH_LEF, PDK_CELL_LEFS, PDK_TRACKS, PDK_SET_RC, PDK_SITE,
#   PDK_PINS_H, PDK_PINS_V, OPENROAD
#                 what report-timing.sh's PLACE=1 needs to floorplan, place
#                 and repair a design with OpenROAD before timing it: the
#                 technology and cell LEFs, the tracks script (empty: the
#                 technology LEF's), the wire RC script, the placement site,
#                 the pin layers, and the OpenROAD binary
#
# Every setting is overridable from the environment before this is sourced.
PDK="${PDK:-asap7}"
_pdk_dir="$(dirname "${BASH_SOURCE[0]}")"
if [[ ! -f "$_pdk_dir/$PDK-lib.sh" ]]; then
  echo "pdk-lib: no recipe for PDK=$PDK (no tools/backend/$PDK-lib.sh)" >&2
  unset _pdk_dir
  return 2 2>/dev/null || exit 2
fi
# A recipe that refuses its own settings (an unknown ASAP7_VT, say) returns
# non-zero, and the caller has to hear about it rather than run on with the
# names unset.
source "$_pdk_dir/$PDK-lib.sh" || return $?
unset _pdk_dir

# pdk_write_abc_constr <file>: what ABC assumes at the design's boundary.
pdk_write_abc_constr() {
  printf 'set_driving_cell %s\nset_load %s\n' "$DRIVER_CELL" "$LOAD_FF" > "$1"
}

# pdk_synth_commands <top>: yosys' generic synthesis of <top>, flattened, one
# command a line, before the flip-flops and the logic are mapped to the
# library. report-timing.sh and the characterization's backend both run it,
# so that a unit's delay and a design's path come from one flow.
#
# The adder. Yosys maps every carry chain (an add, a subtract, a compare: an
# `$alu` cell) to a Brent-Kung lookahead unit, and ABC rebuilds that as a
# ripple-carry chain of majority gates, about 28 ps a bit on ASAP7. On an
# FPGA the carry chain is dedicated silicon; on a cell library the flow has
# to ask for a parallel-prefix adder: ADDER=sklansky (the default),
# kogge-stone or han-carlson, or ADDER=yosys for yosys' own.
#
# And the prefix adder has to survive the mapping. `synth` ends with a
# generic `abc` over all of its gates, and that pass, like a `dc2` in the
# mapping script, folds a prefix tree back into a chain: a 64-bit Sklansky
# add measured 964 ps on ASAP7 SLVT through `synth` at a 1 ns target, and
# 955 ps at 0.2 ns. So `synth` stops before its gate mapping; every other
# cell is mapped and cleaned by `abc` and `opt` as `synth` would do it (not
# running that pass at all costs registers: the constant and equivalent ones
# it exposes stay, 727 to 1,129 flip-flops on one actor); and the `$alu`
# cells are mapped last. The same add is then 217 ps at 1 ns, 192 ps at
# 0.2 ns.
#
# A sum of more than two terms. `alumacc` makes a multiply, or an add of
# several operands, a `$macc` cell, and the techmap that maps it (through
# `maccmap`: a carry-save tree and one final adder) maps that final adder
# too, in the same pass, as yosys' own adder, which `abc` then folds into a
# chain. Running `maccmap` first leaves the final adder an `$alu` like any
# other. Without it the prefix adder made a 64-bit multiply slower, 1,121 to
# 1,409 ps on ASAP7 SLVT and 10.2 to 17.7 ns on sky130; with it, 758 ps and
# 7.3 ns. Not `synth -booth`: a Booth multiplier is smaller and a little
# faster alone (688 ps, 8,126 cells rather than 12,769), but it takes the
# multiply out of the sum it belongs to, so a sequential multiplier's step,
# an accumulator plus a partial product, pays two adders: 402 to 600 ps at
# 32 bits.
pdk_synth_commands() {
  local adder map=""
  adder="$(echo "${ADDER:-}" | tr -d '[:space:]')"
  adder="${adder:-sklansky}"
  [[ "$adder" != "yosys" ]] && map=" -map +/choices/$adder.v"
  printf '%s\n' \
    "synth -top $1 -flatten -run begin:fine" \
    "opt -fast -full" \
    "memory_map" \
    "opt -full" \
    "maccmap" \
    'techmap t:$alu %n' \
    "opt -fast" \
    "abc" \
    "opt -fast" \
    "techmap -map +/techmap.v$map" \
    "opt -fast" \
    "hierarchy -check" \
    "check"
}
