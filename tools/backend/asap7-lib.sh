# asap7-lib.sh -- the ASAP7 mapping recipe, shared. Sourced, never run.
#
# report-timing.sh times a whole exported design against it; the ASAP7 backend
# of tools/backend/synth-characterization times one dataflow unit at a time
# against it. Both read the same libraries, keep the same cells out, hand ABC
# the same script and the same driver and load, and call the same input a
# reset. A unit delay and a design's critical path are then two measurements
# from one flow, and comparing them means something.
#
# Every setting below is overridable from the environment; the defaults are
# ASAP7 (RVT, typical corner) as streamblocks' install_synthesis_tools.sh lays
# it out, with the cells OpenROAD's flow scripts keep out of ASAP7 designs.

# The five RVT TT liberty files, and the one that holds the flip-flops.
ASAP7_DIR="${ASAP7_DIR:-}"
LIBERTIES="${LIBERTIES:-$(ls "${ASAP7_DIR:-/nonexistent}"/asap7sc7p5t_*_RVT_TT_nldm_*.lib 2>/dev/null | tr '\n' ' ')}"
SEQ_LIBERTY="${SEQ_LIBERTY:-$(ls "${ASAP7_DIR:-/nonexistent}"/asap7sc7p5t_SEQ_RVT_TT_nldm_*.lib 2>/dev/null | head -1)}"
DONT_USE="${DONT_USE:-*x1p*_ASAP7* *xp*_ASAP7* SDF* ICG*}"
# ABC buffers every net above this many loads while it maps, so that a report
# is about paths rather than about fan-out.
MAX_FANOUT="${MAX_FANOUT:-12}"
# A quasi-static input that reaches every flip-flop: a false path.
RESET_PORT="${RESET_PORT:-rst}"
# What drives the inputs and loads the outputs during mapping: the flow
# scripts' figures for ASAP7.
DRIVER_CELL="${DRIVER_CELL:-BUFx2_ASAP7_75t_R}"
LOAD_FF="${LOAD_FF:-3.898}"
STA="${STA:-$(command -v sta || true)}"

# Yosys' abc takes one -liberty per file and maps across them, the way
# OpenROAD's flow scripts hand them over.
LIB_ARGS=""
for _asap7_lib in $LIBERTIES; do
  LIB_ARGS="$LIB_ARGS -liberty $_asap7_lib"
done
for _asap7_pattern in $DONT_USE; do
  LIB_ARGS="$LIB_ARGS -dont_use $_asap7_pattern"
done
unset _asap7_lib _asap7_pattern

# Yosys' own constrained liberty script for ABC, with the buffering told to
# cover primary inputs (register outputs, after dfflibmap) and to stop at
# MAX_FANOUT loads, and with sizing toward the clock. Commas stand for spaces
# in a +script; {D} is the clock.
ABC_SCRIPT="+strash;&get,-n;&fraig,-x;&put;scorr;dc2;dretime;strash;&get,-n;&dch,-f;&nf,{D};&put;buffer,-p,-N,$MAX_FANOUT;upsize,{D};dnsize,{D};stime,-p"

# asap7_write_abc_constr <file>: what ABC assumes at the design's boundary.
asap7_write_abc_constr() {
  printf 'set_driving_cell %s\nset_load %s\n' "$DRIVER_CELL" "$LOAD_FF" > "$1"
}
