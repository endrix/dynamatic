# asap7-lib.sh -- the ASAP7 mapping recipe. Sourced through pdk-lib.sh
# (PDK=asap7, the default), never run.
#
# report-timing.sh times a whole exported design against it; the
# standard-cell backend of tools/backend/synth-characterization times one
# dataflow unit at a time against it. Both read the same libraries, keep the
# same cells out, hand ABC the same script and the same driver and load, and
# call the same input a reset. A unit delay and a design's critical path are
# then two measurements from one flow, and comparing them means something.
# The names every recipe defines are listed in pdk-lib.sh.
#
# Every setting below is overridable from the environment; the defaults are
# ASAP7 (SLVT by default, typical corner) as streamblocks' install_synthesis_tools.sh lays
# it out, with the cells OpenROAD's flow scripts keep out of ASAP7 designs.

# WHICH THRESHOLD FLAVOUR. ASAP7 ships the same cells at three thresholds,
# and the choice is worth as much as a prefix adder: on a 32-bit adder in a
# top of its own, SLVT is 496 ps where RVT is 761, for the same 130 cells and
# the same area. The cells differ only in leakage, which this flow does not
# report, so SLVT is the default; ASAP7_VT=lvt or rvt picks another, and
# LIBERTIES and SEQ_LIBERTY still override the lot.
#
# A flavour is a suffix on every cell name (_L, _R, _SL) and a cell LEF of
# its own, so the driver cell and the LEF follow the choice.
ASAP7_DIR="${ASAP7_DIR:-}"
ASAP7_VT="${ASAP7_VT:-slvt}"
# Sourced twice in one shell -- a sweep over the flavours -- the names below
# would keep the first flavour's values, since each takes an override through
# `${VAR:-...}`, while the label would follow the new one: a report that says
# SLVT over RVT cells. What the flavour derives is cleared first, so a second
# source is a second choice. LIBERTIES and SEQ_LIBERTY still override, from
# the environment of the command that sets them.
if [[ -n "${_asap7_sourced:-}" ]]; then
  unset LIBERTIES SEQ_LIBERTY DRIVER_CELL PDK_CELL_LEFS
fi
_asap7_sourced=1
case "$ASAP7_VT" in
  lvt)  _asap7_vt=LVT;  _asap7_sfx=L  ;;
  rvt)  _asap7_vt=RVT;  _asap7_sfx=R  ;;
  slvt) _asap7_vt=SLVT; _asap7_sfx=SL ;;
  *) echo "asap7-lib: ASAP7_VT is lvt, rvt or slvt (not '$ASAP7_VT')" >&2
     return 2 2>/dev/null || exit 2 ;;
esac
LIBERTIES="${LIBERTIES:-$(ls "${ASAP7_DIR:-/nonexistent}"/asap7sc7p5t_*_${_asap7_vt}_TT_nldm_*.lib 2>/dev/null | tr '\n' ' ')}"
SEQ_LIBERTY="${SEQ_LIBERTY:-$(ls "${ASAP7_DIR:-/nonexistent}"/asap7sc7p5t_SEQ_${_asap7_vt}_TT_nldm_*.lib 2>/dev/null | head -1)}"
DONT_USE="${DONT_USE:-*x1p*_ASAP7* *xp*_ASAP7* SDF* ICG*}"
# ABC buffers every net above this many loads while it maps, so that a report
# is about paths rather than about fan-out.
MAX_FANOUT="${MAX_FANOUT:-12}"
# A quasi-static input that reaches every flip-flop: a false path.
RESET_PORT="${RESET_PORT:-rst}"
# What drives the inputs and loads the outputs during mapping: the flow
# scripts' figures for ASAP7.
DRIVER_CELL="${DRIVER_CELL:-BUFx2_ASAP7_75t_${_asap7_sfx}}"
LOAD_FF="${LOAD_FF:-3.898}"
STA="${STA:-$(command -v sta || true)}"
PDK_LABEL="ASAP7 ${_asap7_vt} TT"
PDK_DIR_VAR="ASAP7_DIR"
# The liberty files are in picoseconds.
TIME_SCALE=1
FLOP_RE='DFF[A-Za-z0-9]*_ASAP7'
BUF_RE='BUF[a-z0-9]*_ASAP7'
CELL_RE='_ASAP7_'
# What a placement needs (report-timing.sh's PLACE=1): the technology and
# cell LEFs from the platform directory the install links beside the
# libraries, the platform's tracks script, the wire RC script, the site and
# the pin layers, as OpenROAD's flow scripts set them.
PDK_TECH_LEF="${PDK_TECH_LEF:-$ASAP7_DIR/platform/lef/asap7_tech_1x_201209.lef}"
PDK_CELL_LEFS="${PDK_CELL_LEFS:-$ASAP7_DIR/platform/lef/asap7sc7p5t_28_${_asap7_sfx}_1x_220121a.lef}"
PDK_TRACKS="${PDK_TRACKS:-$ASAP7_DIR/platform/openRoad/make_tracks.tcl}"
PDK_SET_RC="${PDK_SET_RC:-$ASAP7_DIR/platform/setRC.tcl}"
PDK_SITE="${PDK_SITE:-asap7sc7p5t}"
PDK_PINS_H="${PDK_PINS_H:-M4}"
PDK_PINS_V="${PDK_PINS_V:-M5}"
OPENROAD="${OPENROAD:-$(command -v openroad || true)}"

# Yosys' abc takes one -liberty per file and maps across them, the way
# OpenROAD's flow scripts hand them over.
LIB_ARGS=""
for _asap7_lib in $LIBERTIES; do
  LIB_ARGS="$LIB_ARGS -liberty $_asap7_lib"
done
for _asap7_pattern in $DONT_USE; do
  LIB_ARGS="$LIB_ARGS -dont_use $_asap7_pattern"
done
unset _asap7_lib _asap7_pattern _asap7_vt _asap7_sfx

# Yosys' own constrained liberty script for ABC, with the buffering told to
# cover primary inputs (register outputs, after dfflibmap) and to stop at
# MAX_FANOUT loads, and with sizing toward the clock. Commas stand for spaces
# in a +script; {D} is the clock.
ABC_SCRIPT="+strash;&get,-n;&fraig,-x;&put;scorr;dc2;dretime;strash;&get,-n;&dch,-f;&nf,{D};&put;buffer,-p,-N,$MAX_FANOUT;upsize,{D};dnsize,{D};stime,-p"

# asap7_write_abc_constr <file>: pdk_write_abc_constr under its old name.
asap7_write_abc_constr() {
  printf 'set_driving_cell %s\nset_load %s\n' "$DRIVER_CELL" "$LOAD_FF" > "$1"
}
