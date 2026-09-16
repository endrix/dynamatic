# sky130-lib.sh -- the SkyWater sky130 mapping recipe. Sourced through
# pdk-lib.sh (PDK=sky130), never run. The names it defines are listed there.
#
# The defaults are the high-density library (sky130_fd_sc_hd) at the typical
# corner, 25C and 1.8V, as OpenROAD's flow scripts ship it under
# flow/platforms/sky130hd, with the cells those scripts keep out of sky130
# designs: SKY130_DIR holds `sky130hd/lib/` (the liberty file) and, for the
# SRAM macros, `sky130ram/<macro>/` (OpenRAM's liberty, LEF and model per
# macro), the way streamblocks' synthesis install lays them out beside asap7.
#
# One liberty file holds the flip-flops and the logic, so SEQ_LIBERTY is
# LIBERTIES. The file is in nanoseconds (TIME_SCALE 1000); a sky130 design
# clocks an order of magnitude slower than an ASAP7 one, so ask
# report-timing.sh for a period in the thousands of picoseconds.
SKY130_DIR="${SKY130_DIR:-}"
LIBERTIES="${LIBERTIES:-$(ls "${SKY130_DIR:-/nonexistent}"/sky130hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib 2>/dev/null | tr '\n' ' ')}"
SEQ_LIBERTY="${SEQ_LIBERTY:-${LIBERTIES% }}"
# OpenROAD's flow scripts' list for sky130hd: probe points and the
# multi-power-domain cells.
DONT_USE="${DONT_USE:-sky130_fd_sc_hd__probe_p_8 sky130_fd_sc_hd__probec_p_8 sky130_fd_sc_hd__lpflow_*}"
MAX_FANOUT="${MAX_FANOUT:-12}"
RESET_PORT="${RESET_PORT:-rst}"
# The flow scripts' ABC driver and load for sky130hd.
DRIVER_CELL="${DRIVER_CELL:-sky130_fd_sc_hd__buf_1}"
LOAD_FF="${LOAD_FF:-5}"
STA="${STA:-$(command -v sta || true)}"
PDK_LABEL="sky130 HD TT 25C 1.8V"
PDK_DIR_VAR="SKY130_DIR"
TIME_SCALE=1000
FLOP_RE='sky130_fd_sc_hd__[a-z]*df'
BUF_RE='sky130_fd_sc_hd__(clk)?buf'
CELL_RE='sky130_fd_sc_hd__'
# The OpenRAM macros' liberty files, for a caller that sets MACRO_LIBS to
# them (report-timing.sh reads MACRO_LIBS as blackbox cells).
SKY130_SRAM_LIBS="$(ls "${SKY130_DIR:-/nonexistent}"/sky130ram/*/*_TT_1p8V_25C.lib 2>/dev/null | tr '\n' ' ')"

LIB_ARGS=""
for _sky130_lib in $LIBERTIES; do
  LIB_ARGS="$LIB_ARGS -liberty $_sky130_lib"
done
for _sky130_pattern in $DONT_USE; do
  LIB_ARGS="$LIB_ARGS -dont_use $_sky130_pattern"
done
unset _sky130_lib _sky130_pattern

# The same ABC script as ASAP7's: yosys' constrained liberty flow with the
# buffering covering primary inputs and stopping at MAX_FANOUT loads, and
# sizing toward the clock; {D} is the clock, commas stand for spaces.
ABC_SCRIPT="+strash;&get,-n;&fraig,-x;&put;scorr;dc2;dretime;strash;&get,-n;&dch,-f;&nf,{D};&put;buffer,-p,-N,$MAX_FANOUT;upsize,{D};dnsize,{D};stime,-p"
