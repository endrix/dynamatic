# Timing Information and its handling in Dynamatic
This document explains how Dynamatic stores and uses timing information for hardware operators, providing both conceptual understanding and implementation guidance.

## What is Timing Information?
Each operator in a hardware circuit is characterized by two fundamental timing properties:

- **Latency**: The number of clock cycles an operator requires to produce a valid output after receiving valid input, assuming the output is ready to accept the result. This latency is always an integer and corresponds to the number of pipeline stages (i.e., registers) the data passes through.

- **Delay**: The combinational delay along a path — i.e., the time it takes for a signal to propagate through combinational logic, without being interrupted by clocked elements (registers). Delay is measured in physical time units (e.g., nanoseconds).


We classify combinational delays into two categories:

- **Intra-port delays**: Combinational delays from an input port to an output port with no intervening registers. These represent purely combinational paths through an operator. 

- **Port2Reg delays**: Combinational delays either from an input port to the first register stage, or from the last register stage to an output port. These capture the logic surrounding the sequential boundaries of an operator.

- **Reg2Reg delay** :Combinational delays from one register stage to the next register stage within a single pipelined operation, representing the longest logic path between these sequential elements.

This difference is a key distinction between **pipelined** and **non-pipelined** operations. Consider the following graph :

![image](https://github.com/user-attachments/assets/c6d2961c-f4ba-47ed-a7a0-6201314f9530)



In the pipelined case (i.e., when latency > 0), registers are placed along the paths between input and output ports. As a result, these paths no longer have any intra-port delays, since there are no purely combinational routes connecting inputs directly to outputs. However, port2reg delays still exist on these paths — capturing the combinational delays between an input port and the first register stage, and between the last register stage and an output port. In the figure, the inport and outport delays illustrate these port2reg delays.


In the non-pipelined case, there are no registers on the path connecting the input to output port. For this reason, there are no port2reg delays and the only delay present is the intra-port delay (comb logic delay).


In the previous example, we assumed there is only one input and one output port. However, there can be multiple ones and of different types. We can differentiate input and output port into 4 types:
- **DATA (D)** representing the data signal.
- **CONDITION (C)** representing the condition signal.
- **VALID (V)** representing the valid signal of the handshake communication.
- **READY (R)** representing the ready signal of the handshake communication.


The combinational delays can connect ports of the same or different types. The ones of different types supported for now are the following ones: VR (valid to ready), CV (control to valid), CR (control to ready), VC (valid to control), and VD (valid to data).


**Note**: the buffer placer reads the inport and outport delays of a unit
with a latency (its `path_inDelay` and `path_outDelay` constraints), and a
placed buffer's when the buffering group is given a buffer model (the MILPs
give a null one). The FPGA model's port delays are all zero. The cell-library
models measure them for every unit with registers -- see "A unit's
registers" below.



## Where Timing Data is Stored

All timing information lives in the [components JSON file](https://github.com/EPFL-LAP/dynamatic/blob/main/data/components.json). Here's what a typical entry looks like:

```json
{
  "handshake.addi": {
    "latency": {
      "64":{
        "2.3": 8,
        "4.2": 4
    },
    "delay": {
      "data": {
        "32": 2.287,
        "64": 2.767
      },
      "valid": {
        "1": 1.397
      },
      "ready": {
        "1": 1.4
      },
      "VR": 1.409,
      "CV": 0,
      "CR": 0,
      "VC": 0,
      "VD": 0
    },
    "inport": { /* port-specific delays, structured like the delay set above */ },
    "outport": { /* port-specific delays, structured like the delay set above  */ }
  }
}
```

The JSON object encodes the following timing information:
- `latency`: A dictionary mapping bitwidths to timing features of multiple implementation of the component available for that bitwidth. This is done as a map listing all existing implementations, providing their internal combinational delay as key and their latency as value.
- `delays`: A dictionary describing intra-port delays — i.e., combinational delays between input and output ports with no intervening registers (in nanoseconds).
- `inport`: A dictionary specifying port2reg delays from an input port to the first register stage (in nanoseconds).
- `outport`: A dictionary specifying port2reg delays from the last register stage to an output port (in nanoseconds).


The delays dictionary is structured as follows:

- It includes three special keys: "data", "valid", and "ready". Each of these maps to a nested dictionary that captures intra-port delays between ports of the same type. In these nested dictionaries, the keys are bitwidths and the values are the corresponding delay values.

- Additional keys in the delays dictionary represent intra-port delays between different port types (e.g., from "valid" to "data"), and their values are the corresponding delay amounts.

The inport and outport dictionaries follow the same structure as the delays dictionary, capturing combinational delays between ports and registers instead of port-to-port paths.

The delay information can be computed using a [characterization script](https://github.com/EPFL-LAP/dynamatic/tree/main/tools/backend/synth-characterization/run-characterization.py). More information about the script are present in [this doc](../Specs/TimingCharacterization.md).

The latest version of these delays has been computed using Vivado 2019.1.

## Characterizing for ASAP7

`data/components.json` is a Kintex-7 model: Vivado numbers, out-of-context
place and route. `data/components-asap7.json` is the same units measured on the
ASAP7 standard-cell library, so that the buffer placer can be run against a
standard-cell target instead of an FPGA. The characterization script takes a
second backend for it:

```sh
export PATH="$YOSYS/bin:$GHDL/bin:$OPENSTA/bin:$PATH"
export GHDL_PREFIX="$GHDL/lib/ghdl"     # the GHDL plugin for yosys needs it
export ASAP7_DIR=/path/to/asap7         # the TT liberty files, all three flavours
export ASAP7_VT=slvt                    # the flavour the output file is named for

cd "$DYNAMATIC/tools/backend/synth-characterization"
python3 main.py --synth-tool asap7 \
  --dynamatic-dir "$DYNAMATIC" \
  --json-input "$DYNAMATIC/data/rtl-config-vhdl.json" \
  --json-output "$DYNAMATIC/data/components-asap7.json" \
  --clock-period 1.0
```

### Which RTL is measured

A standard-cell model is for the designs `export-rtl` writes, and
`export-rtl` builds a design from the generators that `data/rtl-config-vhdl.json`
names. A fork in an exported design is `vhdl-unit-generator.py -t fork`,
written at its size and width, not `data/vhdl/handshake/fork.vhd`, the file
`rtl-config-vhdl-vivado.json` lists. So the PDK backends read the generator
config, and that is their default when `--json-input` is left out. Vivado
keeps the hand-written files its model was always measured on.

A generator entry has no generics. `export-rtl` fills its command's
variables and the generator bakes them into the RTL. Some variables come
from the operation's attributes, which are the entry's `parameters` (`SIZE`,
`PREDICATE`, `BUFFER_TYPE`, ...). Others come from its port types:
`BITWIDTH`, `DATA_BITWIDTH`, ..., and `EXTRA_SIGNALS`, which no entry
declares. The characterization fills them the same way
(`synth-characterization/generated_units.py`), so each point of a unit's
sweep is generated and synthesized on its own, at the one width it was
written at. A name has one entry in the model, so each delay class is
reduced over the points with the maximum, as over the six hand-written
buffers. The sweep:

| attribute | values |
| --- | --- |
| the data width | 1 to 64 bits (`parameters_ranges["DATA_TYPE"]`), and 128, 256 and 512 for most units (see "The widths past 64 bits"); an address is `ADDR_TYPE` |
| `SIZE` | 2 for the base entry; 2 to 256 for the size entries (see "The units keyed by size") |
| `PREDICATE` (`cmpi`) | all ten: an equality is a tree of XORs, an order a carry chain |
| `TEHB` (`mux`, `merge`) | with and without the output buffer |
| `BUFFER_TYPE` | the six types the hand-written files covered, each with the slots and data-to-valid latency the buffer's verifier requires (one slot, or two for a FIFO or a shift register) |
| `LATENCY`, `IMPL` | the pipelined unit, at the reference model's latency, which is where the compiler takes the attribute from; the sequential units are entries of their own (below) |
| `EXTRA_SIGNALS` | none |

`export-rtl` takes the first entry under a name whose constrained
parameters (`eq`) match, and so does the characterization. That is how
`IMPL` picks the pipelined or the sequential divider. The units only the
generator config has (`blocker`, `init`, `queue`, `bundle`, ...) and the
`arith.` wires of a function body are skipped (`skipping_units_generated`).
An entry for one of them is a change of its own.

For most units the generators write the circuit the hand-written files did,
and the model's numbers are the same to the picosecond (`addi`, `fork`,
`buffer`, `select`, the shifts, ...). What moved, on ASAP7 SLVT:

- `cmpi` is now every comparison, not only `ne`: 94, 132 and 183 ps at 8,
  32 and 64 bits, where it was 41, 86 and 109.
- `mux` and `merge` are written differently. Some of their paths are
  shorter, others longer (`merge` valid to ready: 65 to 115 ps).
- `control_merge`, `remsi`, `remui` and `uitofp` are measured. They carried
  the FPGA model's numbers (about 1.1 ns on every path); `control_merge` is
  now 77 ps on its valid path.
- The pipelined dividers and the conversions are measured at every width,
  not only at 32 bits (see "What the model does not contain").

### The adders

Yosys maps every carry chain (an add, a subtract, a compare: an `$alu`
cell) to a lookahead unit, which ABC turns back into a ripple of majority
gates, about 28 ps a bit on ASAP7. An FPGA has a dedicated carry chain; on a
cell library the flow has to ask for a parallel-prefix adder. `ADDER` picks
one of yosys' `techmap` choices, `sklansky` (the default), `kogge-stone` or
`han-carlson`, and `ADDER=yosys` keeps yosys' own.

Asking is not enough, because the adder also has to survive the mapping.
`synth` ends with a generic `abc` over all of its gates, and that pass, like
the `dc2` and `dretime` in yosys' constrained-liberty ABC script, rewrites a
prefix tree back into a chain. Through `synth`, a 64-bit Sklansky add
measured 964 ps on SLVT at a 1 ns target, and 955 ps at 0.2 ns. So
`pdk-lib.sh`'s `pdk_synth_commands`, which both the characterization and
`report-timing.sh` run, makes four changes:

- it stops `synth` before its gate mapping;
- it runs `maccmap` as a pass of its own (below);
- it maps and cleans every other cell with `abc` and `opt`, as `synth` would;
- it maps the `$alu` cells last.

The ABC script also leaves out `dc2` and `dretime`. The same add is then
217 ps at 1 ns, and 192 ps at 0.2 ns. Dropping the generic `abc` altogether
is not the answer: the constant and equivalent registers that pass exposes
then stay, and one actor went from 727 to 1,129 flip-flops.

A sum of more than two terms needs the `maccmap` step. `alumacc` makes a
multiply, or an add of several operands, a `$macc` cell. The techmap that
maps it (through `maccmap`: a carry-save tree and one final adder) maps that
final adder in the same pass, as yosys' own adder, and `abc` then folds it
into a chain. Run first as a pass of its own, `maccmap` leaves the final
adder an `$alu` like any other. The pipelined multiplier's stage, 64 bits:

| `muli` stage | before | prefix adders alone | with `maccmap` |
| --- | --- | --- | --- |
| ASAP7 SLVT, 1 ns | 1,121 ps | 1,409 ps | 758 ps |
| sky130, 10 ns | 10.2 ns | 17.7 ns | 7.3 ns |

`synth -booth` is not used. A radix-4 Booth multiplier is smaller and a
little faster on its own (688 ps in 8,126 cells, where `maccmap` gives
758 ps in 12,769). But Booth takes the multiply out of the sum it belongs
to, so a sequential multiplier's step (an accumulator plus a partial
product) pays two adders in a row: 402 to 600 ps at 32 bits, four bits a
step. On two whole designs, it also added about 500 fan-out buffers each
and did not shorten the critical path.

On whole designs (four actors exported by StreamBlocks, `report-timing.sh`
on SLVT at 1 ns, post-synthesis):

| design | critical path, before | after | cells, before | after |
| --- | --- | --- | --- | --- |
| a row of multiply-accumulates | 1,394 ps | 1,193 ps | 127,538 | 139,514 |
| a convolution's input stage | 1,414 ps | 1,273 ps | 47,148 | 46,259 |
| a row maximum and store | 1,617 ps | 1,561 ps | 78,235 | 77,010 |
| a transposer | 800 ps | 732 ps | 4,965 | 4,981 |

The flip-flop counts are the same before and after. The prefix adders cost
cells where there are many of them: the row of multiply-accumulates is 9%
more cells and 5% more area. What is left on those paths is handshake
logic, which is the buffer placer's to cut.

### The threshold flavour

ASAP7 ships every cell at three thresholds, and the choice costs nothing in
cells: a 32-bit adder's characterization top is 167 cells with Sklansky and
282 with Kogge-Stone on every flavour, with a different leakage that this
flow does not report. What the choice buys is speed. Here is that adder's
data delay as the characterization measures it at a 1 ns target. Each
column is one prefix adder (`ADDER`, `sklansky` by default):

| flavour | Sklansky | Kogge-Stone |
| --- | --- | --- |
| RVT | 270 ps | 213 ps |
| LVT | 213 ps | 168 ps |
| SLVT | 181 ps | 143 ps |

`ASAP7_VT` picks one, `slvt` by default, and every script that maps cells
reads it: the timing reports, the characterization and `PLACE=1`'s
placement. No pass inside Dynamatic reads it; a buffer placer is handed a
model by name, and the only place that maps the flavour to a model file is
streamblocks' `run2.sh`. There
is a model per flavour, because a model made of one flavour's cells describes
no other: `data/components-asap7.json` is the default's, and
`data/components-asap7-lvt.json` and `data/components-asap7-rvt.json` are
the other two. There is no `-slvt` file: the default's model is the one
under the plain name, and it is renamed when the default moves. A flavour's delays differ from RVT's by more than a quarter on
the arithmetic and by more than half on a fork's ready path, so placing with
the wrong one is not a rounding error.

SLVT is the default because this flow is used to make circuits faster at a
given cell count, and it is the fastest at the same cell count. It also
leaks the most, and this flow measures delay and area and says nothing about
power, so a design that cares about leakage should say `ASAP7_VT=lvt` or
`rvt` rather than trust a default chosen on delay alone.


Some generator entries run through `$DYNAMATIC/bin/generators/`, symlinks
that `build.sh` makes and a checkout configured by hand with cmake does not
have; make them as `build.sh` does (its `create_symlink` calls) before
characterizing such a checkout.

`--synth-tool asap7` swaps the Vivado backend for one that, per unit and per
bitwidth, maps the generated top with yosys (VHDL read through the GHDL plugin)
and then asks OpenSTA for the largest combinational delay between each
(input port, output port) pair the Vivado backend would have asked Vivado
about. `--clock-period` is what ABC maps toward and what OpenSTA's clock is set
to; the whole set, on the generator config with its sizes and wide widths, is
43 to 48 minutes per model on ten cores (`NUM_CORES`).

### Characterizing for sky130

The same backend maps to the SkyWater sky130 high-density library with
`--synth-tool sky130`: `data/components-sky130.json` is the units measured on
`sky130_fd_sc_hd` at the typical corner (25C, 1.8V), the way
`components-asap7.json` is on ASAP7. The recipe is `tools/backend/sky130-lib.sh`,
selected through `tools/backend/pdk-lib.sh` by `PDK=sky130`, and the library is
located by `SKY130_DIR`, a directory holding `sky130hd/lib/` (the liberty
file) and `sky130ram/<macro>/` (OpenRAM's SRAM macros), as OpenROAD's flow
scripts ship them under `flow/platforms`:

```sh
export SKY130_DIR=/path/to/sky130       # sky130hd/lib/*.lib, sky130ram/*/
python3 main.py --synth-tool sky130 \
  --dynamatic-dir "$DYNAMATIC" \
  --json-input "$DYNAMATIC/data/rtl-config-vhdl.json" \
  --json-output "$DYNAMATIC/data/components-sky130.json" \
  --clock-period 10.0
```

A unit the characterization does not measure, one on its skipping list (the
units with no data path, those another script measures; the dividers are
skipped on Vivado only and measured on the PDK backends) or one that leaves
no report, is carried from the reference
model as it is, so that the model stays complete for the buffer placer: a
latency is structural, the divider's 35 stages are 35 on any library, and
such a unit's delays are not port to port. The script prints which units it
carried; their numbers are the reference's, not the library's.

sky130's liberty is in nanoseconds where ASAP7's is in picoseconds; the
backend hands ABC picoseconds either way and scales OpenSTA's clock and its
reports by the PDK (`PDKS` in `pdk_backend.py`). A sky130 design clocks an
order of magnitude slower than an ASAP7 one, so the period to map toward is
in the nanoseconds, and `report-timing.sh` is asked for thousands of
picoseconds.

sky130 has flip-flops with an enable (`edfxtp`); ASAP7 has none. Mapped to
one, a flip-flop's enable is a pin after ABC: the net that drives it is one
output of the logic ABC maps, however many flip-flops it reaches, and ABC
never buffers it. A pipelined divider's stall enable reaches 3,170 of them
at 32 bits through one `clkbuf_1`. So `sky130-lib.sh` keeps them out of
`dfflibmap` (`DFF_DONT_USE`, handed over as `DFF_ARGS`): the enable is a
mux in front of a plain flip-flop, as on ASAP7, and ABC buffers it to
`MAX_FANOUT` like any other net. Nine entries move: the three sequential
units' latency tables by their new stage (their ready paths by 0.02 ns at
most), and these, where the stall enable reaches every stage:

| sky130, 10 ns | ready, enable flip-flops | kept out | 64-bit stage, enable flip-flops | kept out |
| --- | --- | --- | --- | --- |
| `divsi` (pipelined) | 351.3 ns | 1.37 ns | 335.6 ns | 4.49 ns |
| `divui` (pipelined) | 349.5 ns | 1.23 ns | 333.8 ns | 4.14 ns |
| `remsi`, `remui` | 292.9 ns | 1.09 ns | 279.8 ns | 4.65 ns |
| `muli` (pipelined) | 9.59 ns | 0.80 ns | 10.06 ns | 7.12 ns |
| `buffer` | 3.13 ns | 0.91 ns | 3.49 ns | 1.79 ns |

Below 8 bits a stage grows a little instead (the divider's 1-bit stage
from 0.56 to 0.86 ns): with a few loads, a mux and a plain flip-flop are
slower than the flip-flop with the mux inside it.

### Placed and repaired: `PLACE=1`

`report-timing.sh` stops at synthesis: no wires, and no buffer trees but
ABC's. That understates every long wire. With `PLACE=1` and
OpenROAD on the path (or `OPENROAD`), the script floorplans the mapped
netlist (`UTILIZATION` percent, 50 by default), places it, estimates the
wires' parasitics from the placement, buffers every net above `MAX_FANOUT`
loads and every slew or capacitance violation (the resizer's
`repair_design`), and times the result with the wires in; the report says
how many buffers went in and how many cells were resized, and gives the
slack before placement, placed, and repaired. Each recipe names what the
placement needs (`PDK_TECH_LEF`, `PDK_CELL_LEFS`, `PDK_TRACKS`,
`PDK_SET_RC`, `PDK_SITE`, `PDK_PINS_H`, `PDK_PINS_V`); macros' LEFs come
from `MACRO_LEFS`. On the transposer, measured before the recipe kept the
prefix adders (see "The adders"): sky130 10,817 ps at synthesis,
14,409 ps placed and repaired (831 buffers in, 4,913 cells resized); ASAP7
1,737 ps and 2,037 ps (no buffer needed, 9,334 resized). The 32-bit
divider's stage was 86 ns at synthesis and 6.2 ns placed and repaired while
sky130's enable flip-flops kept its enable away from ABC; with them kept out
(see "Characterizing for sky130"), it is 3.7 ns at synthesis. The characterization's stage
report stays post-synthesis: a placement per unit and width would take
hours, and the whole-design report is where the placed number matters.

### What the numbers mean

The mapping recipe lives in `tools/backend/asap7-lib.sh` (sky130's in
`sky130-lib.sh`; `pdk-lib.sh` selects one by `PDK`) and is the same one
`tools/backend/report-timing.sh` uses to time a whole exported design: the five
ASAP7 typical-corner liberty files of the chosen threshold flavour
(`ASAP7_VT`), the cells OpenROAD's flow scripts keep out of ASAP7 designs,
the generic synthesis of `pdk-lib.sh`'s `pdk_synth_commands`, which keeps
the adders away from ABC until they are prefix adders (see "The adders"),
yosys' constrained-liberty ABC script with fan-out buffering and gate sizing
but without its `dc2` and `dretime`,
a `BUFx2` of that flavour driving every input and a
3.898 fF load on every output, and reset as a false path. A unit's delay and a
design's critical path therefore come out of one flow and can be compared.

They are **post-synthesis** numbers. There is no placement, so there are no
wire delays, and they are optimistic in the same way `report-timing.sh`'s are.
The corner is typical. The Vivado numbers they sit next to are the opposite
kind of measurement -- post-route, out of context -- and carry about 1.1 ns of
routing and boundary delay in every unit, which is why even a 1-bit `andi`
costs 1.117 ns there and 0.015 ns here. Do not read the ratio as a technology
speedup.

ASAP7's liberty files declare their time unit as picoseconds, so OpenSTA
reports picoseconds; the model is in nanoseconds, and the report parser divides
by 1000.

A pair with no combinational path between its ports -- a pipelined unit's data
path, where the only route from input to output runs through a register --
gets `No paths found.` from OpenSTA and is recorded as 0.0, which is what the
Vivado backend records for the same case. A unit that does not elaborate at all
leaves no report behind and is left out of the model entirely, rather than
being recorded as a zero.

### Sanity figures

Measured at `--clock-period 1.0`, on RVT, which was the flavour the flow
mapped to when these were taken: they check `components-asap7-rvt.json`, not
the default's file, and every row would be about a third lower on SLVT.

| unit | ASAP7 (ns) | for comparison |
| --- | --- | --- |
| `addi`, 32-bit, data | 0.270 | 0.754 before `pdk_synth_commands` kept the prefix adder (see "The adders") |
| `addi`, 64-bit, data | 0.321 | 1.463 before |
| `mux`, valid | 0.105 | the generator's mux; the hand-written one was 0.157 |
| `mux`, 32-bit, data | 0.057 | |
| `cmpi`, 32-bit, data | 0.204 | the slowest of the ten comparisons, an order; `ne` alone was 0.140 (0.178 before the prefix adder) |
| `andi`, any bitwidth, data | 0.015 | one two-input gate |
| `fork`, ready | 0.042 | `outs_ready[1]` to `ins_ready`, the eager fork's AND tree |
| `fork`, data | 0.000 | `outs(i) <= ins` is a wire, and OpenSTA reports the path at 0.000 |
| `buffer`, ready | 0.084 | the largest of the six implementations |

### The three units a name covers several of

`fork`, `lazy_fork` and `buffer` were added to the model in the same change
that made `CV`/`CR` real. `handshake.buffer` is six VHDL entities -- `oehb`,
`tehb`, `tfifo`, `elastic_fifo_inner`, `one_slot_break_dvr`,
`shift_reg_break_dv` -- and the model has one entry per operation name, so the
script characterizes all six and reduces each delay class with the maximum.
The per-implementation numbers at 64 bits, which are what the buffer types
mean, read straight off the reports:

| implementation | `BUFFER_TYPE` | data | valid | ready |
| --- | --- | --- | --- | --- |
| `oehb` | `ONE_SLOT_BREAK_DV` | registered | registered | 39.0 ps |
| `tehb` | `ONE_SLOT_BREAK_R` | 15.2 ps | 51.5 ps | registered |
| `tfifo` | `FIFO_BREAK_NONE` | 19.1 ps | 17.9 ps | 17.9 ps |
| `elastic_fifo_inner` | `FIFO_BREAK_DV` | registered | registered | 17.9 ps |
| `one_slot_break_dvr` | `ONE_SLOT_BREAK_DVR` | registered | registered | registered |
| `shift_reg_break_dv` | `SHIFT_REG_BREAK_DV` | registered | registered | 69.5 ps |

"registered" is `No paths found.`, read back as 0.0. The maximum is the
conservative reduction: the model then never says a path is shorter than some
implementation makes it. It is also the only reduction available, since the
placer looks a unit up by its operation name and `handshake.buffer` is the
name of all six.

A buffer type also has an entry of its own,
`handshake.buffer.<BUFFER_TYPE>`, which `TimingDatabase::getModel` times a
buffer of that type by; the base entry stays the reduction, for a lookup by
the name alone.

The buffer placer accepts the model: on `fir`, `--handshake-place-buffers`
with `algorithm=fpga20 solver=cbc` places buffers at a 1.0 ns target period
against `components-asap7.json` and reports the MILP infeasible at 0.5 ns,
where against `components.json` it is already infeasible at 1.0 ns and needs
2.0 ns.

### A unit's registers

A port-to-port delay leaves a unit's registers out: a path that starts at one
or ends in one has no input port at one end or no output port at the other.
On a cell library they are not small. A transparent slot's
(`ONE_SLOT_BREAK_R`) data out is its multiplexer, which its full register
selects over every data bit, so its data leaves the slot about 0.11 ns after
the clock at 32 bits on ASAP7 SLVT, where its data passes through in 0.01; an
opaque slot's valid in drives its data registers' enable, 0.08 ns into them
with the setup. Every unit with registers has paths like these: the
multiplexer and the merge behind their output slot (`TEHB`), the control
merge, an eager fork's flags for the outputs that have taken their copy.

So a standard-cell characterization measures them, as the entry's port
models: `outport`, from every register to each class of output port (the
clock to output and the logic after it), and `inport`, from each class of
input port into every register (the logic before it and the setup). The
queries are OpenSTA's `report_checks -from [all_registers] -to <port>` and
`-from <port> -to [all_registers]`, the second read back as the period less
the path's slack. Each signal is keyed by the data width, valid and ready
too: the enable and the select fan out over the data (a transparent slot's
valid into its registers is 0.06 ns at 1 bit and 0.12 at 32). The
deserializer reads the valid and ready delays at `"1"`, which is always
written, and keeps them at every width too
(`TimingModel::PortModel::validDelayAt`); a data width past the widest entry
takes the widest, which understates what the width adds but does not leave
the register out. A unit with no register keeps zero port models.

ASAP7 SLVT, 32 bits, ns:

| slot | through: data, valid, ready | register to outputs | inputs to register |
| --- | --- | --- | --- |
| `ONE_SLOT_BREAK_DV` | -, -, 0.026 | 0.035, 0.040, 0.066 | 0.035, 0.078, 0.095 |
| `ONE_SLOT_BREAK_R` | 0.010, 0.037, - | 0.109, 0.060, 0.090 | 0.040, 0.123, 0.090 |
| `ONE_SLOT_BREAK_DVR` | -, -, - | 0.035, 0.035, 0.061 | 0.045, 0.090, 0.033 |

("-": registered, no path through.) A design's critical paths agree: in an
ifld body cut to 540 ps, the worst path starts at a transparent slot's full
register and spends 0.13 ns in its clock to output and the fan-out tree after
it, a path no port-to-port delay has.

### The units keyed by implementation

A unit whose implementation is chosen before buffer placement gets an entry of
its own, keyed by the operation's name and the implementation, the way the
floating-point units are (`handshake.addf.flopoco`, `handshake.cmpf.vivado`).
Two units are keyed this way today, the ones the backend generates on a
parameter (`data/rtl-config-vhdl.json`, `IMPL` and `STEP` in an operation's
`hw.parameters`):

| key | what it is |
| --- | --- |
| `handshake.divui` | the pipelined Vitis long division, a stage a quotient bit |
| `handshake.divui.sequential` | one division at a time, a quotient bit a cycle on one register set |
| `handshake.muli` | the whole product in one cycle behind delay registers |
| `handshake.muli.sequential.<STEP>` | one multiply at a time, `STEP` multiplier bits a cycle |

The step is in the key and not in the entry because an entry nests by
retiming path, bitwidth and clock period, and an implementation is none of
those; `STEP` rows of adders a cycle are a different unit, not a different
width of one. `TimingDatabase::getModel` reads the operation's `hw.parameters`
and looks for `<name>.<IMPL>.<STEP>`, then `<name>.<IMPL>`, then `<name>`, and
says once per key when it has to fall back:

```
remark: TimingDatabase::getModel: no timing model for
"handshake.muli.sequential.2"; the entry for "handshake.muli" is used instead
```

The characterization writes these entries itself. The input RTL config lists
the pipelined units under `handshake.divui` and `handshake.muli`, so the
sequential ones are characterized as units of their own, from
`tools/backend/synth-characterization/utils.py`'s `impl_variants`: an RTL
entry each, with the model key as its name, the VHDL entity as its
`module-name`, and a `bitwidths` list saying that the generator bakes the
width into the RTL (`$BITWIDTH` in the generator command) and is therefore
run once per width, where a unit with a `DATA_TYPE` generic is generated once
and the width swept in the wrapper. `latency` is the unit's latency in cycles
at a width, the generator's own formula (`BITWIDTH + 1` for the divider,
`ceil(BITWIDTH / STEP) + 1` for the multiplier); the reference model cannot
supply it, since it does not list these units. The divider is characterized
at 1 to 64 bits and the multiplier at steps 4 and 8, from the step up to 512
bits (see "The widths past 64 bits"). A step the model does not hold is
timed by the nearest larger one it does: `esa-unit-impl` clamps the step to
the width, so a 5-bit multiplier under step 8 asks for
`handshake.muli.sequential.5` and is timed by the step-8 entry, the same
unit at that width; a step above every characterized one falls to the base
entry, with a remark. An op that names `pipelined` is timed by the base
entry with no remark.

An entry of theirs says what a sequential unit is. Its data and valid paths
are registered, so they are 0.0 like a pipelined unit's; its ready path is
short, because the operands are taken through a join gated by one idle
signal. The latency table carries the measured delay of one iteration -- the
floor the unit puts under the clock -- against the cycles that many
iterations take, which is what `getInternalCombinationalDelay` and
`getLatency` read.

One iteration, measured (`components-asap7.stages.json`, SLVT at 1.0 ns, and
`components-sky130.stages.json` at 10.0 ns, in nanoseconds), beside the
pipelined multiplier's own stage:

| unit | 8 | 16 | 32 | 64 |
| --- | --- | --- | --- | --- |
| ASAP7 `divui.sequential` | 0.184 | 0.244 | 0.277 | 0.342 |
| ASAP7 `muli.sequential.4` | 0.300 | 0.360 | 0.443 | 0.458 |
| ASAP7 `muli.sequential.8` | 0.286 | 0.376 | 0.450 | 0.524 |
| ASAP7 `muli` (pipelined) | 0.307 | 0.430 | 0.598 | 0.767 |
| sky130 `divui.sequential` | 2.091 | 2.586 | 2.537 | 3.680 |
| sky130 `muli.sequential.4` | 2.682 | 3.355 | 3.980 | 4.375 |
| sky130 `muli.sequential.8` | 2.774 | 3.763 | 4.352 | 5.022 |
| sky130 `muli` (pipelined) | 3.143 | 4.280 | 5.701 | 7.123 |

The divider is also characterized at 1, 2 and 4 bits (ASAP7: 0.113, 0.154,
0.168). Read the multiplier rows with the accumulator in mind: a step is a
partial product and a full-width add, one carry-save tree with one prefix
adder at its end (see "The adders"), so it grows slowly with the width: at
64 bits the sequential unit's step is 0.458 ns (four bits a step) against
the pipelined unit's whole product at 0.767.

The ready path is where the two implementations differ port to port. On
ASAP7 the sequential multiplier's is 0.033 ns and the pipelined one's
0.124 ns; on sky130 they are 0.404 ns (step 8; 0.391 at step 4) and
0.799 ns. The dividers differ the same way: the sequential divider's ready
path is 0.034 ns (ASAP7) and 0.414 ns (sky130), and the pipelined one's
0.160 ns and 1.234 ns. A pipelined unit's ready path is its stall enable,
which reaches every stage.

Only the placers that model the ready and valid paths read those numbers
(`fpl22`, `costaware`). `fpga20` models the data path alone, and for a unit
with a latency reads only the port-to-register delays (see "A unit's
registers"); and a sequential unit's latency comes from the op's `latency` attribute
before the model's table (`esa-unit-impl` writes it). So on the esa flow an
`fpga20` placement is the same with these entries and without them; the
latency table is read only for an op that names the implementation and
carries no `latency`.

### The units keyed by size

Some units join or split a number of channels, and their handshake grows
with it. A fork's ready is an AND over its outputs, and a mux's data a
select over its inputs. A design's forks are not all two-way: the
Gemmini actors exported by StreamBlocks have 3,744 forks, 1,171 of them
wider than two, 83 with 32 outputs or more, and the widest with 208. An
entry measured at two outputs times every one of them as a two-way fork.

So a PDK characterization also writes these units at several sizes, each an
entry of its own, `<name>.size.<N>` (`generated_units.SIZES`: 2, 3, 4, 8,
16, 32, 64, 128 and 256). The units are fork, lazy_fork, mux, merge,
control_merge and first. The size is in the key for the reason the
multiplier's step is: an entry nests by retiming path, bitwidth and clock
period, and a size is none of those. The base entry, `<name>`, is the size-2
one, as before. A sized entry is measured at 1, 8, 32 and 64 bits only,
since a width is also looked up at the smallest one at or above it.

`TimingDatabase::getModel(op)` reads the op's size as `HandshakeToHW` writes
the RTL's `SIZE`:

- fork and lazy_fork: their results;
- mux and control_merge: their data operands;
- merge, first, join and blocker: their operands;
- stand_in: its kills (the racing units below).

It then returns the entry for the smallest size at or above it, a bound from
above, as for a width. Past the largest size, it returns the largest, with a
remark once per size:

```
remark: TimingDatabase::getModel: no timing model for "handshake.fork.size.300";
the entry for "handshake.fork.size.256", the largest size characterised, is
used instead
```

A model with no sized entries for a unit, `components.json` for one, times
it by its base entry, as before. The placers and `esa-cut-to-period` all go
through `getModel(op)`, so every one of them reads the sized entries.

A bound from above holds only if no larger size has a shorter path, and a
measurement can have one: ABC maps each size afresh, and a merge at 256
inputs came out faster than at 128. So the characterization writes each
sized entry's delays as the largest at its size or any smaller one
(`report_parser.bound_sizes`). On the four models this raises 16 to 18 of
the 54 sized entries, by at most 0.23 ns on ASAP7 and 1.5 ns on sky130.

What the sizes measured, the longest of an entry's delays (any port to any
port, any of its widths), in ns, before that bound:

| unit | model | 2 | 8 | 32 | 64 | 128 | 256 |
|---|---|---|---|---|---|---|---|
| mux | ASAP7 SLVT | 0.090 | 0.221 | 0.411 | 0.677 | 1.124 | 2.547 |
| | sky130 | 1.447 | 1.766 | 3.536 | 5.663 | 10.140 | 17.482 |
| first | ASAP7 SLVT | 0.165 | 0.271 | 0.551 | 0.980 | 1.850 | 3.682 |
| | sky130 | 1.877 | 3.555 | 6.623 | 9.848 | 17.700 | 35.768 |
| control_merge | ASAP7 SLVT | 0.131 | 0.161 | 0.343 | 0.600 | 0.983 | 1.811 |
| | sky130 | 1.140 | 2.464 | 5.534 | 7.361 | 12.296 | 22.463 |
| merge | ASAP7 SLVT | 0.129 | 0.173 | 0.405 | 0.884 | 0.931 | 0.744 |
| | sky130 | 1.121 | 2.499 | 6.406 | 10.022 | 9.875 | 8.963 |
| lazy_fork | ASAP7 SLVT | 0.010 | 0.048 | 0.115 | 0.186 | 0.230 | 0.536 |
| | sky130 | 0.114 | 0.291 | 1.070 | 1.785 | 3.128 | 7.406 |
| fork | ASAP7 SLVT | 0.017 | 0.079 | 0.096 | 0.081 | 0.136 | 0.091 |
| | sky130 | 0.180 | 0.450 | 0.970 | 1.147 | 1.247 | 1.079 |

Of the sized entries longer than 0.1 ns on SLVT, LVT is 1.09 to 1.25 times
them and RVT 1.41 to 1.63 times.

A fork's ready stays shallow: 256 outputs cost little more than eight. The
mux, first and control_merge grow in proportion to their inputs, not to
the logarithm of them: their generators write the selection as a loop of
`if`s over the inputs, and synthesis keeps the loop a chain. In the mux
(`generators/handshake/mux.py`) the index matches one input at most, which
synthesis cannot tell; in first and control_merge the loop is a priority
among the valid inputs, which a prefix structure would make logarithmic
and a loop does not. A unit's own delay is not one a placer can cut, so on
ASAP7 SLVT a mux of more than about a hundred inputs does not fit a 1 ns
period whatever the buffers.

### The racing units

The units of a round that races its guards and stops the losers
(`handshake.first`, `handshake.priority`, `handshake.commit`,
`handshake.stand_in`, the drop-counting `handshake.load`, and the lowering's
`kill_or`) are measured like every other generated unit, on their
generators' RTL. Until they were, their entries were copies of other units'
(first's of its phase-3 RTL, with VR and ready from control_merge and mux;
priority's of first's; commit's of lazy_fork's; stand_in's of a slot's), and
a full run of the script could not finish: priority's ports `hi` and `lo`,
and the `kill` of a commit, a stand-in and a dropping load, had no port
class, the load's `KILL_DROP` had no values to sweep, and a stand-in's one
kill is below the sizes a sized unit was swept at.

What the characterization measures of them, beside the classes every unit
has:

- `first` and `priority` decide on their payload: an input wins when it is
  non-zero, so their valid out (and a first's inputs' ready) reads the data
  through a zero-detect (`utils.payload_condition_units`). That path, data
  into valid and into ready, is written as their `CV` and `CR`, the delay of
  a condition, which is what the payload is to them. A first is sized by its
  inputs (2 to 256); a priority has two, `hi` and `lo`.
- `commit` is a wire on its channel (valid, ready and data measure 0), and
  its kill, the AND of its valid in and its ready out, is a port of its own
  class, `kill`: `VK` (valid in to kill) and `RK` (the ready of its output,
  `outs_ready`, a signal into the unit, to kill), keys beside `VR`..`VD` that
  only a commit's entry has.
- `stand_in` passes its flag through a multiplexer and an OR, and its kills
  end in its two registers (`sent`, `owe`): the kills into the registers are
  its port model's `inport` `kill`, at every width. It is sized by its kills
  (`handshake.stand_in.size.<N>`, from 1: `generated_units.base_size` takes a
  unit's base size from its SIZE's lower bound), and getModel reads the
  stand-in's number of kills as HandshakeToHW writes its `SIZE`.
- `load` with `KILL_DROP` (a load in a kill domain, which counts the words it
  owes and drops them on a kill) is another circuit, and its own entry,
  `handshake.load.kill_drop` (`generated_units.VARIANT_KEYS`); the base
  entry stays the plain load's. getModel reads it for a load that carries
  `handshake.kill_domain`.
- `race` (`handshake.race`, a whole racing decision as one unit) decides on
  its payloads too (`payload_condition_units`): every input, a token's
  payload or a flag's bit, reaches the valid out through the candidates'
  terms. Its ports `tokens` and `flags` are data. It is written at a
  STRUCTURE, its CANDIDATES, not at a size: `generated_units.race_shapes`
  gives, for 2, 3, 4, 8, 16, 32, 64 and 128 inputs, the nests a lowering
  makes -- a chain of priorities over a flag each (the longest `after`), an
  F of a guard each (the widest tie), one guard over every flag (the widest
  AND), a priority chain over tokens (a hold over settled networks), and a
  mixed nest (a token, then guards over a flag and a negated one, P and F in
  turn) -- and its entry at a size, `handshake.race.size.<N>`, is the
  maximum over them. A nest a width cannot tell apart (more flag candidates
  than the width has distinct non-zero payloads) is not written at that
  width. Each shape of size N has N inputs and at most N candidates, so
  getModel's size for a race is the larger of its inputs (tokens and flags
  together) and its candidates. A race with ALTERNATIVES (candidates of one
  payload or one token, a shared subtree taken in once a place that reads
  it) has more candidates than inputs, and is not characterized apart: its
  extra candidates are terms of the AND/OR, the prefix OR and the
  multiplexer, and a race of at most N inputs and N candidates is timed by
  the size-N entry, whose shapes have the longest `after`, the widest tie
  and the widest AND such a race can have, each alone (an approximation for
  a race that combines them, as for any race). A race's readies
  read no data -- an input is ready while it has not given its token, or
  when the round completes, from the other inputs' valids and the output's
  ready -- so its data into ready is not measured
  (`ready_reads_no_data_units`) and its CR is 0: the path a timer finds
  there is false, through cells ABC shares between the decision and the
  readies (0.234 ns once, a race of four tokens at 64 bits, which the sizes
  above it inherited).
- `kill_or`, the OR of a kill domain's commits, is not an operation: the
  lowering puts it beside a domain that several commits stop. It is written
  under the generator config's name, `kill_or.size.<N>` (2 to 256 inputs,
  one width: `utils.dataless_units`), and its data delay is the OR. No op is
  timed by it; a consumer that times a domain's reset reads it by name.

A run of some units writes them into an existing model and leaves every
other entry as it is there (`--units`, `--update`):

```sh
python3 main.py --synth-tool asap7 --dynamatic-dir "$DYN" \
  --json-input "$DYN/data/rtl-config-vhdl.json" \
  --json-output "$DYN/data/components-asap7.json" --clock-period 1.0 \
  --units handshake.first,handshake.priority,handshake.commit,handshake.stand_in,kill_or,handshake.load \
  --update
```

An entry the run writes replaces the one of the same key in place, a new one
follows its unit's last entry, and the `.stages.json` beside the model is
updated the same way. The plain load, measured again in that run, came out
byte-identical to its entry, and a second run of the same units wrote the
same file. A run starts from an empty `tmp/reports`: OpenSTA appends to a
report file, and a report a previous run left would be read with the run's
own, as the larger of the two.

ASAP7 SLVT at 1 ns, in ns (the width-independent delays are the largest at 1
to 64 bits, as for every unit; the stage is the `.stages.json` largest):

| entry | valid | ready | VR | CV | VD | VK, RK | data at 8 bits (kill_or: its one bit) | kill into registers | stage |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| handshake.first.size.2 | 0.103 | 0.046 | 0.058 | 0.159 | 0.140 | - | 0.128 | - | 0.241 |
| handshake.first.size.3 | 0.121 | 0.078 | 0.064 | 0.167 | 0.168 | - | 0.144 | - | 0.212 |
| handshake.first.size.4 | 0.134 | 0.078 | 0.064 | 0.175 | 0.207 | - | 0.147 | - | 0.260 |
| handshake.first.size.8 | 0.180 | 0.087 | 0.114 | 0.201 | 0.247 | - | 0.195 | - | 0.323 |
| handshake.first.size.16 | 0.255 | 0.109 | 0.183 | 0.286 | 0.325 | - | 0.294 | - | 0.393 |
| handshake.first.size.64 | 0.818 | 0.173 | 0.282 | 0.754 | 0.840 | - | 0.776 | - | 1.022 |
| handshake.first.size.256 | 2.919 | 0.467 | 0.615 | 2.872 | 2.959 | - | 2.788 | - | 2.992 |
| handshake.priority | 0.087 | 0.047 | 0.066 | 0.144 | 0.147 | - | 0.113 | - | 0.219 |
| handshake.commit | 0 | 0 | 0 | 0 | 0 | 0.010, 0.009 | 0 | - | - |
| handshake.stand_in.size.1 | 0.009 | 0.010 | 0 | 0 | 0 | - | 0.010 | 0.039 | 0.095 |
| handshake.stand_in.size.2 | 0.009 | 0.010 | 0 | 0 | 0 | - | 0.010 | 0.042 | 0.089 |
| handshake.stand_in.size.3 | 0.009 | 0.012 | 0 | 0 | 0 | - | 0.010 | 0.042 | 0.096 |
| handshake.load | 0.037 | 0 | 0 | 0 | 0 | - | 0.010 | - | 0.152 |
| handshake.load.kill_drop | 0.029 | 0 | 0 | 0 | 0 | - | 0.010 | 0.047 | 0.188 |
| kill_or.size.2 | - | - | - | - | - | - | 0.012 | - | - |
| kill_or.size.3 | - | - | - | - | - | - | 0.015 | - | - |
| kill_or.size.4 | - | - | - | - | - | - | 0.020 | - | - |
| kill_or.size.8 | - | - | - | - | - | - | 0.047 | - | - |
| handshake.race.size.2 | 0.121 | 0.039 | 0.050 | 0.182 | 0.167 | - | 0.142 | - | 0.442 |
| handshake.race.size.3 | 0.161 | 0.063 | 0.067 | 0.202 | 0.202 | - | 0.145 | - | 0.403 |
| handshake.race.size.4 | 0.185 | 0.075 | 0.174 | 0.222 | 0.226 | - | 0.207 | - | 0.416 |
| handshake.race.size.8 | 0.263 | 0.075 | 0.174 | 0.278 | 0.276 | - | 0.208 | - | 0.472 |
| handshake.race.size.16 | 0.322 | 0.096 | 0.184 | 0.303 | 0.371 | - | 0.265 | - | 0.519 |
| handshake.race.size.32 | 0.428 | 0.113 | 0.264 | 0.372 | 0.446 | - | 0.314 | - | 0.559 |
| handshake.race.size.64 | 0.627 | 0.135 | 0.464 | 0.408 | 0.636 | - | 0.406 | - | 0.713 |
| handshake.race.size.128 | 0.953 | 0.174 | 0.815 | 0.558 | 0.978 | - | 0.639 | - | 1.029 |

Every race entry's CR is 0 (its readies read no data, above), so the table,
which has no CR column, says all there is.

A race of N inputs replaces a nest of first and priority units over the same
inputs, which the chain lowering built one unit per `esa.f` or `esa.p`: on
picorv32's Cpu seven units deep, each 0.09-0.16 ns valid or condition to
valid, about 1 ns in series by these entries, where one race of 8 to 16
inputs is 0.26-0.32 (valid) and 0.28-0.30 (CV). At two inputs it is a
first's or a priority's plus 20-40 ps (its literal and its predecessors'
terms in front of the multiplexer); the race pays off from the second unit
of a nest. From 64 inputs it is faster than a first of as many (0.627 ns of
valid against 0.818 at 64, 0.953 against 1.475 at 128): a first's
completing-round term reads every other input for each input, where a race's
is one prefix and one suffix AND over the arrivals. At 128 inputs its stage
no longer fits a 1 ns period by itself; a larger race is timed by the
128-input entry, a bound from below, with a remark.

A first grows with its inputs faster than any other sized unit: each input's
ready in the cycle the round completes reads every other input (the
completing-round term), a loop over the inputs inside a loop over them, and
synthesis keeps both chains. At 64 inputs it no longer fits a 1 ns period by
itself; the racing rounds the compiler builds have two to four.

The width-independent delays are the largest over 1 to 64 bits, and for
these units that is the zero-detect of a 64-bit payload: a priority's `CV`
is 0.062 ns at 1 bit and 0.144 at 64, a first's (two inputs) 0.060 and 0.159.
A round's payloads are flags and action indices of one to three bits, so
the model times its racing units as wider than they are.

The sky130 and ASAP7 LVT and RVT models keep their copied entries: a run of
first's sizes 128 and 256 takes more than an hour on ASAP7 alone.

### The widths past 64 bits

A design's datapath is wider than 64 bits. In Gemmini's handshake IR, as
streamblocks hands it to the buffer placer, adders reach 259 bits,
subtractors 323, comparators 257 and the (sequential) multipliers 262, and
shifts, ORs and buffers reach 1,091 to 1,152. A width is looked up at the
smallest one at or above it; above the widest, each consumer does
something else:

- `TimingDatabase::getInternalDelay` and `getTotalDelay` find no data delay
  and fail, and the buffer placers then time the unit's data path as zero
  (the 0.001 ns floor of `addUnitTimingConstraints`). `getLatency` takes
  the widest entry, with a remark: a latency is a stage count, which the
  width does not change.
- streamblocks' `esa-cut-to-period` takes the widest entry, for the data
  delay and for a registered unit's stage, and lists the unit in its
  report (`wider_than_model`); it used to grow a carry chain with log2 of
  the width instead.

So a PDK characterization also writes a unit at 128, 256 and 512 bits
(`utils.WIDE_WIDTHS`), which bounds every adder, subtractor, comparator and
multiplier of those designs from above; the sequential multipliers, steps
4 and 8, go to 512 bits too. Some units stay at 1 to 64 bits
(`utils.narrow_units`), where a wide entry would say nothing the widest one
does not:

- `fork`, `lazy_fork` and `cond_br`: their data is a wire, 0.0 measured up
  to 512 bits;
- `absf` (which clears the sign bit, a wire as well), `sitofp`, `uitofp`
  and `fptosi`: a float is 32 or 64 bits;
- the dividers, `divsi`, `divui`, `remsi` and `remui`, and the sequential
  divider: no design divides more than 33 bits (Gemmini's dividers are 16
  and 17 bits, picorv32's 32, the streamblocks lanes' 32 and 33);
- the pipelined `muli`: streamblocks lowers a multiply to the sequential
  unit for a cell library unless told otherwise, so no design built for
  one has it (its wide ones, the streamblocks lanes' up to 256 bits, are
  built for an FPGA and timed with `components.json`); its data path is
  registered, 0.0 at every width.

The entries keyed by size stay at 1, 8, 32 and 64 bits: a sized unit's
data path is its select over the inputs, which the width only fans out,
and Gemmini's wide sized units are forks (wires) and muxes of up to 16
inputs at 128 bits.

A wide point gives its unit the data delay at its width, its stage (the
`.stages.json` report) and, for a sequential multiplier, its latency
table's entry. It does not enter the delays the model holds once for every
width (`valid`, `ready`, `VR`, `CV`, `CR`, `VC`, `VD`), which stay the
maximum over 1 to 64 bits. Those are a unit's handshake, and at 512 bits it
fans out over the data: on ASAP7 SLVT, a first's `VD` is 156 ps against 117
up to 64 bits, a merge's 150 against 129, a mux's `VR` and `CR` 111 and 110
against 89 and 87, a buffer's ready 74 against 61. The model has one number
for each, and a maximum over every width would charge a wide unit's
fan-out to every narrow one; a wide unit's handshake is understated by that
much instead. With the wide points kept out of them, every entry the
models had -- each width up to 64 bits, each of these delays, each stage --
came out of the regeneration as it was.

The carry chains and a shift, data delay in ns (`cmpi` is the slowest of
its ten predicates):

| unit | model | 64 | 128 | 256 | 512 |
| --- | --- | --- | --- | --- | --- |
| `addi` | ASAP7 SLVT | 0.217 | 0.250 | 0.306 | 0.334 |
| | sky130 | 2.876 | 3.280 | 3.554 | 4.163 |
| `subi` | ASAP7 SLVT | 0.241 | 0.265 | 0.315 | 0.342 |
| | sky130 | 2.396 | 3.270 | 3.770 | 4.035 |
| `cmpi` | ASAP7 SLVT | 0.183 | 0.206 | 0.210 | 0.254 |
| | sky130 | 1.528 | 1.682 | 2.130 | 2.410 |
| `shli` | ASAP7 SLVT | 0.211 | 0.234 | 0.271 | 0.282 |
| | sky130 | 2.602 | 3.501 | 3.886 | 4.450 |
| `andi` | ASAP7 SLVT | 0.010 | 0.010 | 0.010 | 0.010 |
| | sky130 | 0.114 | 0.114 | 0.114 | 0.114 |

From 64 to 512 bits, eight times the width, the prefix adders grow by 1.39
(ASAP7's comparator) to 1.68 times (sky130's subtractor), around the 1.5
that log2 of the width gives. On the arithmetic and the shifts, LVT is 1.17
to 1.19 times SLVT and RVT 1.47 to 1.54 times, at every width. The bitwise
units do not grow, and neither do `select`, `mux`, `merge`,
`control_merge`, `buffer` and `load`, whose data path is a gate or two per
bit: they are written wide all the same, since a placer's lookup above the
widest finds nothing at all.

The sequential multipliers' step (`.stages.json`, ns), the floor such a
unit puts under the clock:

| unit | model | 64 | 128 | 256 | 512 |
| --- | --- | --- | --- | --- | --- |
| `muli.sequential.4` | ASAP7 SLVT | 0.458 | 0.516 | 0.596 | 0.628 |
| | ASAP7 RVT | 0.692 | 0.771 | 0.901 | 0.951 |
| | sky130 | 4.375 | 4.896 | 5.683 | 6.452 |
| `muli.sequential.8` | ASAP7 SLVT | 0.524 | 0.553 | 0.641 | 0.677 |
| | ASAP7 RVT | 0.778 | 0.836 | 0.944 | 1.022 |
| | sky130 | 5.022 | 6.253 | 6.405 | 7.735 |

On RVT a 512-bit multiplier at eight bits a step no longer fits a 1 ns
period (1.022 ns); Gemmini's 262-bit ones are timed by that entry.

Two things did not grow with the width. sky130's `first` is 2.053 ns at
128 bits and 2.001 at 256; it was already not monotone below 64 bits (1.749
at 16, 1.470 at 32), and a width between 129 and 256 bits is timed 52 ps
short of the 128-bit one. And the stages of the units that hold a slot or
a flag (`buffer`, `mux`, `merge`, `control_merge`, `first`, `load`) rise
and fall by up to 31 ps on ASAP7 SLVT (a merge's is 163 ps at 128 bits and
132 at 256) and 400 ps on sky130 (`first`, 2.011 to 1.612 ns): the path is
the flag's register through the fan-out tree ABC builds to every data bit,
and ABC builds that tree afresh at each width: the merge's on SLVT came
out a buffer shallower for 256 loads than for 128. The stages are a
report; the placer does not read them.

### What the model does not contain

The characterization script skips some units and carries their entries from
the reference model, so that the model stays complete for the buffer placer:

- `utils.py`'s `skipping_units`: the floating-point units, `store`, `end`,
  `return`, `join`, `mem_controller` and the LSQ;
- the dividers, but on Vivado only;
- on the generator config, `skipping_units_generated` (see "Which RTL is
  measured").

On the hand-written files, more units dropped out of an ASAP7 run for
reasons in the RTL:

- the dataful `control_merge` asserts false in
  `data/vhdl/handshake/control_merge.vhd` ("implementation with data signal
  has a bug");
- `sitofp` and `fptosi` elaborated only at a 32-bit data type;
- the pipelined `divsi` also elaborated only at 32 bits, and `divui` not at
  all.

Their generators write all of them at every width, so the PDK models now
measure `control_merge`, `remsi`, `remui` and `uitofp`, which used to carry
the reference model's FPGA numbers (about 1.1 ns on every path), and the
pipelined dividers and conversions at every width. Buffer placement warns
`no timing model for op` for each unit still missing and treats it as
zero-delay.

`mem_controller` now resolves its dependency (`mem_controller.vhd` names
`mem_controller_loadless`, which the dependency dictionary keyed under the unit
name rather than the file's), but it is still on the skip list: its ports are
the BRAM interface (`loadEn`, `loadAddr`, `storeData`) and the per-access
channels (`ldAddr`, `ldData`), which `VhdlInterfaceInfo.categorize_ports` has
no rule for and asserts on, and its `NUM_LOADS`/`NUM_CONTROLS`/`NUM_STORES`
have no entry in `parameters_ranges`. The BRAM side is not a handshake channel
and has no place in the model's delay classes at all.

`VC` is the delay from a `valid` input to a `condition` output, and the only
unit with a `condition`-class *output* is `control_merge`'s `index`. It was
zero throughout while that unit's hand-written VHDL refused to elaborate;
measured on the generator's, it is 92 ps on ASAP7 SLVT, and zero for every
other unit. `CV` and `CR` are measured (`select`, `mux` and `cond_br` have
them); until this change they were thrown away, because the delay classes are
queried under the names `condition`/`valid`/`ready` and were matched under
`control`/`valid`/`ready` when the JSON was assembled. That was true of a
Vivado run of this script too, so `components.json`'s `CV`, `CR` and `VC` are
worth re-measuring.

Latency is not measured here. `main.py` copies each unit's latency table from
`--reference-json` (by default `data/components.json`), since a unit's pipeline
depth is a property of its RTL and not of what it is mapped onto; units the
reference does not list get a combinational, zero-latency table. The
exception is a unit the reference cannot list because the config does not
name it, the sequential divider and multiplier above: their latency is a
formula of the width and the step, and it is written against the measured
delay of one iteration. `inport` and
`outport` are the unit's registers, as for every unit (see "A unit's
registers").

## How Timing Information is Used

Timing data is primarily used during **buffer placement**, which inserts buffers in the dataflow circuit. While basic buffer placement (i.e., `on-merges`) ignores timing, the advanced MILP algorithms (fpga20 and flp22) rely heavily on this information to optimize circuit performance and area.

Timing information (especially reg2reg delays) is also used in the **backend**, in order to generate appropriate RTL units which meet speed requirements. 

# Implementation Overview

In this section, we present the data structures used to store timing information, along with the code that extracts this information from the JSON and populates those structures.

## Core Data Structures

The timing system uses the following core data structures:

- **[TimingDatabase](https://github.com/EPFL-LAP/dynamatic/blob/main/include/dynamatic/Support/TimingModels.h#L221)**: IR-level timing container
  - Contains the timing data for the entire IR.
  - Stores multiple `TimingModel` instances (one per operation).
  - Provides accessor methods to retrieve timing information.
  - Gets populated from the JSON file during buffer placement passes.

- **[TimingModel](https://github.com/EPFL-LAP/dynamatic/blob/main/include/dynamatic/Support/TimingModels.h#L151)**: Per-operation timing data container
  - Encapsulates all timing data for a single operation (latencies and delays).
  - Uses `BitwidthDepMetric` structure to represent bitwidth-dependent values (see below).
  - Contains nested `PortModel` structures for port2reg delay information. 

- **[PortModel](https://github.com/KillianMcCourt/dynamatic/blob/pr1-clean/include/dynamatic/Support/TimingModels.h#L152)** : Port2reg delay values container

  - There are two objects of this class in the Timing Model class for input port and output port.

  - This structure contains three fields : data, valid and ready delays. The first one is represented using the `BitwidthDepMetric` structure.

- **[BitwidthDepMetric](https://github.com/EPFL-LAP/dynamatic/blob/main/include/dynamatic/Support/TimingModels.h#L46)**: Bitwidth-dependent timing map
  - Maps bitwidths to timing information. This information can for instance be integers, or complex structures, like maps.
  - Supports queries like `getCeilMetric(bitwidth)` to return the timing value for the closest equal or greater supported bitwidth.


- **[DelayDepMetric](https://github.com/EPFL-LAP/dynamatic/blob/main/include/dynamatic/Support/TimingModels.h#L46)**: Bitwidth-dependent timing map
  - Maps delays to timing values (e.g., for delay 3.5ns → 9 cycles)
  - Supports queries like `getDelayMetric(targetCP)` to return the timing value for the highest listed delay that remains smaller than the targetCP.


## Loading Timing Data from JSON
Before detailing the process, an introduction of the main functions involved is required :

- ```fromJSON((const ljson::Value &jsonValue, T &target, ljson::Path path)``` : this is the primary function used, with a number of overloads for various T object types. These overloads are, in order :  [first called](https://github.com/EPFL-LAP/dynamatic/blob/main/lib/Support/TimingModels.cpp#L373) on the TimingDatabase, then [on every](https://github.com/EPFL-LAP/dynamatic/blob/main/lib/Support/TimingModels.cpp#L330) TimingModel inside the Database, then on individual fields(example for BitwidthDepMetric [here](https://github.com/EPFL-LAP/dynamatic/blob/main/lib/Support/TimingModels.cpp#L373) ); PortModels also have a dedicated [overload](https://github.com/EPFL-LAP/dynamatic/blob/main/lib/Support/TimingModels.cpp#L396) .

- [```deserializenested((ArrayRef<std::string> keys, const ljson::Object *object, T &out, ljson::Path path)```](https://github.com/EPFL-LAP/dynamatic/blob/main/lib/Support/TimingModels.cpp#L256): this function is called by the TimingModel fromJSON. It calls the ```fromJSON(*value, out, currentPath)```   for the inidividual fields, by iterating across the path provided by the ```TimingModel```-level ```fromJSON```. Therefore, it handles the deserialisation of said fields, by passing back the object deserialized. 

The process follows these steps:

1. **Initialization**  
   Create an empty `TimingDatabase`, and call the initialization `readFromJSON` on it. This function:

   1.1 **File Reading**  
   Loads the entire contents of the `components.json` into a string, and then parses it as a JSON.

   1.2 **Begin Extraction**  
   We then call `fromJSON` on the `TimingDatabase` and the parsed JSON to begin the deserialization process.

2. **Deserialization**  
   The [`TimingDatabase`](https://github.com/EPFL-LAP/dynamatic/blob/main/lib/Support/TimingModels.cpp#L439) `fromJSON` overload iterates over the JSON object, where each key represents an operation name and the values are the timing information. For every found operation, it will :

   2.1 **Create a `TimingModel`** instance.

   2.2 **Call `fromJSON` on that `TimingModel` and the parsed JSON**. This `fromJSON` contains a list of timing characteristics that are to be filled. For each it uses predefined string arrays as nested key paths, for example :`Data delays: {"delay", "data"}`.

   - 2.2.1 **For each field and it's nested key path**, it will call [`deserializeNested`](https://github.com/EPFL-LAP/dynamatic/blob/main/lib/Support/TimingModels.cpp#L268). This function validates that each step in the path exists and is the correct type (object vs value) exists.  
   - 
   - 2.2.2 This in turn **calls the appropriate `fromJSON` and writes the result back into the field**. For example,for [`BitwidthDepMetric<double>`](https://github.com/EPFL-LAP/dynamatic/blob/main/lib/Support/TimingModels.cpp#L295), the fromJSON parses integer bitwidth keys and their associated timing values, writing results back into the `TimingModel`which made the request.

   2.3 Once every key listed in 2.2 has been handled, we **Write back the `TimingModel` into the database.**
  
Once deserialisation is done for **all operators**, the database will contain the full information of the JSON. 

##  Core Functions of Data Structures

### TimingDatabase

The TimingDatabase provides several core methods:

1. **[bool insertTimingModel(StringRef name, TimingModel &model)](https://github.com/EPFL-LAP/dynamatic/blob/main/lib/Support/TimingModels.cpp#L183)**: inserts the timing model `model` with the key `name` in the TimingDatabase.

2. **[TimingModel* getModel(OperationName opName)](https://github.com/EPFL-LAP/dynamatic/blob/main/lib/Support/TimingModels.cpp#L183)**: returns the TimingModel of operation with name `opName`.

3. **[TimingModel* getModel(Operation* op)](https://github.com/EPFL-LAP/dynamatic/blob/main/lib/Support/TimingModels.cpp#L183)**: returns the TimingModel of operation `op`: the entry for its implementation (`<name>.<IMPL>.<STEP>`, `<name>.<IMPL>`), or for its size (`<name>.size.<N>`, the smallest size at or above the op's), or, for a load in a kill domain, `handshake.load.kill_drop`, or its name's.

4.  **[LogicalResult getLatency(Operation *op, SignalType signalType, double &latency)](https://github.com/EPFL-LAP/dynamatic/blob/main/lib/Support/TimingModels.cpp#L114)**: queries the latency of a certain operation `op` for output port of type `signalType` and it saves the latency as unsigned cycle count in the `latency` variable.

5. **[LogicalResult getInternalDelay(Operation *op, SignalType signalType, double &delay)](https://github.com/EPFL-LAP/dynamatic/blob/main/lib/Support/TimingModels.cpp#L143)**: queries the reg2reg internal delay of a certain operation `op` for output port of type `signalType` and it saves the delay as a double (in nanoseconds) in the `delay` variable.

6. **[LogicalResult getPortDelay(Operation *op, SignalType signalType, double &delay)](https://github.com/EPFL-LAP/dynamatic/blob/main/lib/Support/TimingModels.cpp#L161)**: queries the port2reg delay of a certain operation `op` for input/output port of type `signalType` and it saves the delay as a double (in nanoseconds) in the `delay` variable.

7. **[LogicalResult getTotalDelay(Operation *op, SignalType signalType, double &delay)](https://github.com/EPFL-LAP/dynamatic/blob/main/lib/Support/TimingModels.cpp#L183)**: queries the total delay of a certain operation `op` for output port of type `signalType` and it saves the delay as a double (in nanoseconds) in the `delay` variable.

The LogicalResult or boolean types of these functions represent the successful or unsuccessful execution of the function.

The functions 4-7 automatically handle bitwidth lookup and return the appropriate timing value for the requested operation and signal type.

### TimingModel

The TimingModel provides several core methods:


1. **[LogicalResult getTotalDataDelay(unsigned bitwidth, double &delay)]()**: queries the total data delay at a certain bitwidth `bitwidth` and it saves the delay as a double (in nanoseconds) in the `delay` variable.

2. **[bool fromJSON(const llvm::json::Value &jsonValue, TimingModel &model, llvm::json::Path path)]()**: extracts the TimingModel information from the JSON fragment `jsonValue` located at the specified path `path` relative to the root of the full JSON structure, and stores it in the variable `model`. 

3. **[bool fromJSON(const llvm::json::Value &jsonValue, TimingModel::PortModel &model, llvm::json::Path path)]()**: extracts the PortModel information from the JSON fragment `jsonValue` located at the specified path `path` relative to the root of the full JSON structure, and stores it in the variable `model`. 

The LogicalResult or boolean types of these functions represent the successful or unsuccessful execution of the function.

### BitwidthDepMetric

The main function of BitwidthDepMetric is the following:

1. **[LogicalResult getCeilMetric(unsigned bitwidth, M &metric)]()**: queries the metric with the smallest key among the ones with a key bigger than `bitwidth` and saves the metric in the variable `metric`.

### DelayDepMetric

The functions of BitwidthDepMetric are the following:  

1. **LogicalResult [getDelayCeilMetric(double targetPeriod, M &metric)](https://github.com/EPFL-LAP/dynamatic/blob/doc_branch_2/include/dynamatic/Support/TimingModels.h#L109)**: finds the highest delay that does not exceed the targetPeriod and returns the corresponding metric value. This selects the fastest implementation that still meets timing constraints. If no suitable delay is found, falls back to the lowest available delay with a critical warning.

2. **LogicalResult [getDelayCeilValue(double targetPeriod, double &delay)](https://github.com/EPFL-LAP/dynamatic/blob/doc_branch_2/include/dynamatic/Support/TimingModels.h#L142)**: similar to getDelayCeilMetric but returns the delay value itself rather than the associated metric. Finds the highest delay that is less than or equal to targetPeriod, or falls back to the minimum delay if no suitable option exists.w


# Timing Information in the IRs

Timing information is generally used immediately upon being obtained, for instance latency is obtained for the MILP solver during the buffer placement stage. However, the reg2eg internal delay must be made available in the backend to select the correct implementation to instantiate, but depends on targetCP which isn't known in the backend. 

Therefore, internal delay is added as an attribute to arithmetic ops in the IR at the end of the buffer placement stage, and is represented in the hardware IR. The value given is chosen using getDelayCeilValue, ensuring the choice passed into the IR is the same one that was made at any other point with getDelayCeilMetric. 

Sample code of the attribute :

in handhsake IR :

```
    %57 = addf %56, %54 {...
internal_delay = "3_649333"} : <f32>
```

in hardware IR : 

```
hw.module.extern @handshake_addf_0(... INTERNAL_DELAY = "3_649333"}}

```





# Timing Information in FloPoCo units - Current architecture naming standard

FloPoCo units are identified by the triplet **{operator name, bitwidth, measured internal delay}** which serves to uniquely identify them. The "measured internal delay" refers to the reg2reg delay obtained from Vivado's post-place-and-route timing analysis, which provides the actual achieved delay rather than the target specification

We use different VHDL architectures to differentiate between different implementations of the same operator. Each floating point wrapper file (addf.vhd, mulf.vhd, etc.) contains a separate architecture for each FloPoCo implementation, identified by a bitwidth-delay pair added as a suffix to "arch" to form a unique name. The legacy Dynamatic backend supports this approach by allowing an "arch-name" to be specified, which we leverage to select the appropriate architecture for each operator implementation

Both the operator specific wrappers and the shared flopoco reference file are generated by the [seperate unit module generator](https://github.com/ETHZ-DYNAMO/flopoco-to-dataflow-converter). See its own documentation for further details.

Consider the following example from [addf.vhd](https://github.com/EPFL-LAP/dynamatic/blob/doc_branch_2/data/vhdl/arith/flopoco/addf.vhd), which shows how all architectures are present inside the file, but distinguished by architecture name:

```
architecture arch_64_5_091333 of addf is
    
...

        operator : entity work.FloatingPointAdder_64_5_091333(arch)
        port map (
            clk   => clk,
            ce_1 => oehb_ready,
            ce_2 => oehb_ready,
            ce_3 => oehb_ready,
            ce_4 => oehb_ready,
            ce_5 => oehb_ready,
            ce_6 => oehb_ready,
            ce_7 => oehb_ready,
            X     => ip_lhs,
            Y     => ip_rhs,
            R     => ip_result
        );
end architecture;

architecture arch_64_9_068000 of addf is

...
        operator : entity work.FloatingPointAdder_64_9_068000(arch)
        port map (
            clk   => clk,
            ce_1 => oehb_ready,
            ce_2 => oehb_ready,
            X     => ip_lhs,
            Y     => ip_rhs,
            R     => ip_result
        );
end architecture;
```



Therefore, the desired version of the operator is used, based on the timing information passed through the hardware IR's INTERNAL_DELAY field and the operation bitwidth.

**Note :  usage of the dedicated flopco unit module is reccomended to ensure consistent data between the json used for timing information and the backend**.

