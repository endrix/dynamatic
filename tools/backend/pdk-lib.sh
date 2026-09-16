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
#   MAX_FANOUT    loads above which ABC buffers a net while it maps
#   RESET_PORT    the quasi-static input that is a false path
#   DRIVER_CELL   what drives every input during mapping, LOAD_FF the load
#                 on every output (femtofarads, as OpenROAD's flow scripts
#                 hand them to ABC)
#   ABC_SCRIPT    yosys' constrained-liberty script for ABC
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
#
# Every setting is overridable from the environment before this is sourced.
PDK="${PDK:-asap7}"
_pdk_dir="$(dirname "${BASH_SOURCE[0]}")"
if [[ ! -f "$_pdk_dir/$PDK-lib.sh" ]]; then
  echo "pdk-lib: no recipe for PDK=$PDK (no tools/backend/$PDK-lib.sh)" >&2
  unset _pdk_dir
  return 2 2>/dev/null || exit 2
fi
source "$_pdk_dir/$PDK-lib.sh"
unset _pdk_dir

# pdk_write_abc_constr <file>: what ABC assumes at the design's boundary.
pdk_write_abc_constr() {
  printf 'set_driving_cell %s\nset_load %s\n' "$DRIVER_CELL" "$LOAD_FF" > "$1"
}
