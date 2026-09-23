# The VHDL unit library on a standard-cell library

Dynamatic's unit library was written for an FPGA, and it is good at that. The
generators cover the whole handshake dialect, the buffers come in six
implementations, and the floating-point units come in two. What none of that
says is what happens when the target is a standard-cell library instead: an
FPGA tool retimes, has a dedicated carry chain, turns a small array into
distributed RAM, and has vendor IP for everything Dynamatic does not want to
write itself. A cell library has none of these. Thus a unit that relies on one
of them either fails to build or is built into something nobody would have
written on purpose.

This page sizes the "adapting the backend to a cell library" track of the
ASIC tuning plan kept in streamblocks-mlir
(`docs/plans/2026-09-17-asic-tuning-todo.md`); "the plan" below means that
file.

This page answers one question per unit. If a design instantiates it and the
target is a cell library, does it build, and is what it builds sane? Every
number below was measured rather than estimated, and the section at the end
says what it was measured with.

## Method

The audit is of the generators, not of `data/vhdl/`. Only six files under
`data/vhdl/support/` are still named by `data/rtl-config-vhdl.json` (`types`,
`spec_types`, `sharing_support`, `flopoco_ip_cores`, `vitis_hls_cores`,
`vivado_ip_cores`); the rest of `data/vhdl/` belongs to
`data/rtl-config-vhdl-vivado.json`, a separate configuration, and the default
VHDL flow reads none of it. That leaves 87 generator types named by the
default configuration, of which one (`rigidifier`) has no generator, plus the
LSQ, which has a generator of its own.

Thus each unit was generated at 32 bits with the parameters the flow passes
it, read into yosys through the GHDL plugin, mapped to ASAP7 SLVT with the
Sklansky adder, and timed with OpenSTA, which is
`tools/backend/report-timing.sh` at its defaults. Reading a generator tells
you what it means to emit; mapping what it emits tells you what it emits. As a
matter of fact the two disagree more often than is comfortable.

In addition, three cross-checks say the harness is measuring the right thing.
The pipelined `divsi` comes out at 17,531 cells and 3,205 flip-flops and
`remui` at 15,649 and 2,676, which are the numbers the sequential-divider work
recorded independently. No unit in the library infers a latch: across the 98
mapped netlists the sequential cells are 83,014 `DFFHQNx1` and 32
`DFFASRHQNx1`, and nothing else.

## The verdict

| class | units | what it means |
|---|---|---|
| **fine** | 67 | behavioural VHDL, no vendor content, no FPGA-only assumption |
| **broken** | 2 | does not build at all, for reasons that have nothing to do with the target |
| **vendor** | 7 | instantiates IP the repository does not ship; cannot be built on cells at all |
| **fpga-shaped** | 8 | builds, and the structure is one only a retiming FPGA tool exploits |
| **memory** | 2 | storage whose mapping depends on the target |
| **needs a look** | 2 | not settled by this audit |

Thus the answer to "three more items or thirteen" is: twenty-one units are
not plainly fine. Nine unit types cannot be built at all (the seven vendor
ones, `ndwire` and `rigidifier`), and three more fail in one configuration
(`SHIFT_REG_BREAK_DV` with data, `valid_merger` and `top_join` with extra
signals). The rest cost area and flip-flops rather than correctness. Separately, six units emit VHDL
that no tool can read, or cannot be generated at all, for reasons that have
nothing to do with the target; they are listed in their own section because
fixing them is cheap and independent.

## Every unit, measured

The classes are argued in the sections below. This is the evidence behind
them: every unit at 32 bits with the parameters the flow gives it, post
synthesis on ASAP7 SLVT at a 1 ns clock. A unit that is **vendor**,
**fpga-shaped** or **memory** appears in its own section instead, with the
implementation that the class is about.

| unit | cells | flip-flops | path | note |
|---|---|---|---|---|
| `absf` | 0 | 0 | 0.0 ps |  |
| `absi` | 80 | 0 | 294.6 ps |  |
| `addi` | 137 | 0 | 492.4 ps |  |
| `andi` | 37 | 0 | 10.3 ps |  |
| `cmpi` | 102 | 0 | 168.5 ps |  |
| `constant` | 0 | 0 | 0.0 ps | value is a bit-string |
| `extsi` | 0 | 0 | 0.0 ps |  |
| `extui` | 0 | 0 | 0.0 ps |  |
| `trunci` | 0 | 0 | 0.0 ps |  |
| `maxsi` | 198 | 0 | 244.6 ps |  |
| `maxui` | 197 | 0 | 208.8 ps |  |
| `minsi` | 182 | 0 | 228.9 ps |  |
| `minui` | 182 | 0 | 213.1 ps |  |
| `negf` | 1 | 0 | 2.3 ps |  |
| `noti` | 32 | 0 | 2.3 ps |  |
| `ori` | 37 | 0 | 11.9 ps |  |
| `shli` | 350 | 0 | 204.1 ps |  |
| `shrsi` | 353 | 0 | 240.1 ps |  |
| `shrui` | 350 | 0 | 191.5 ps |  |
| `subi` | 179 | 0 | 498.7 ps |  |
| `xori` | 37 | 0 | 18.6 ps |  |
| `select` | 83 | 2 | 133.5 ps |  |
| `extf` | 277 | 0 | 283.6 ps |  |
| `truncf` | 1307 | 0 | 999.1 ps | all combinational, 999 ps |
| `br` | 0 | 0 | 0.0 ps |  |
| `cond_br` | 9 | 0 | 35.5 ps |  |
| `fork` | 20 | 3 | 102.1 ps | size 3 |
| `lazy_fork` | 6 | 0 | 12.5 ps | size 3 |
| `merge` | 232 | 33 | 153.4 ps | size 3 |
| `mux` | 351 | 33 | 201.3 ps | size 3 |
| `control_merge` | 254 | 37 | 166.0 ps | size 3 |
| `first` | 314 | 37 | 216.8 ps | size 3 |
| `top_join` | 5 | 0 | 12.5 ps | size 3; broken with extra signals |
| `sink` | 0 | 0 | no path |  |
| `source` | 0 | 0 | no path |  |
| `ready_remover` | 0 | 0 | 0.0 ps |  |
| `valid_merger` | 0 | 0 | 0.0 ps | broken with extra signals, its only use |
| `blocker` | 5 | 0 | 10.3 ps |  |
| `init` | 220 | 33 | 155.2 ps |  |
| `bundle` | 0 | 0 | 0.0 ps |  |
| `unbundle` | 0 | 0 | 0.0 ps |  |
| `queue` | 640 | 137 | 202.3 ps | 4 slots; 32 slots is 5,193 / 1,045; array storage, which an FPGA puts in distributed RAM and a cell library in flops, correctly |
| `ndwire` | - | - | - | broken: does not parse at any width |
| `rigidifier` | - | - | - | broken: no generator registered |
| `buffer ONE_SLOT_BREAK_DV` | 144 | 33 | 137.7 ps |  |
| `buffer ONE_SLOT_BREAK_R` | 222 | 33 | 147.8 ps |  |
| `buffer ONE_SLOT_BREAK_DVR` | 149 | 34 | 135.1 ps |  |
| `buffer FIFO_BREAK_DV` | 638 | 134 | 169.3 ps | 4 slots; 32 slots is 5,430 / 1,036 |
| `buffer FIFO_BREAK_NONE` | 817 | 134 | 185.3 ps | 4 slots |
| `buffer COUNTER_BUFFER` | 156 | 35 | 162.8 ps | dv_latency 4 |
| `buffer SHIFT_REG_BREAK_DV` | 15 | 4 | 84.2 ps | dataless only; crashes with data |
| `load` | 299 | 44 | 147.8 ps |  |
| `store` | 0 | 0 | 0.0 ps |  |
| `mem_controller` | 621 | 68 | 586.8 ps | 1 load, 1 store, 1 control |
| `lsq` | - | - | - | 8+8 entries: 7,309 / 821 / 555.8 ps, through a clk/rst shim |
| `muli.sequential` | 1532 | 101 | 696.6 ps | step 8 |
| `divui.sequential` | 645 | 103 | 551.6 ps |  |
| `divsi.sequential` | 863 | 104 | 575.9 ps |  |
| `remui.sequential` | 608 | 104 | 602.7 ps |  |
| `remsi.sequential` | 862 | 105 | 513.1 ps |  |
| `addf.flopoco` | 1398 | 65 | 1044.1 ps | latency 1 |
| `subf.flopoco` | 1508 | 65 | 1032.3 ps | latency 1 |
| `mulf.flopoco` | 9076 | 1561 | 845.9 ps | latency 26 |
| `divf.flopoco` | 9339 | 1494 | 760.5 ps | latency 15 |
| `cmpf.flopoco` | 225 | 3 | 206.3 ps |  |
| `maximumf.flopoco` | 334 | 2 | 319.9 ps |  |
| `minimumf.flopoco` | 333 | 2 | 335.3 ps |  |
| `spec_commit` | 215 | 33 | 198.8 ps |  |
| `spec_save_commit` | 1003 | 138 | 221.1 ps |  |
| `speculating_branch` | 11 | 0 | 35.5 ps |  |
| `non_spec` | 0 | 0 | 0.0 ps |  |
| `speculator` | 1180 | 205 | 355.1 ps | the library's one asynchronous reset |
| `ii_monitor` | 0 | 0 | no path | simulation monitor, prints |
| `sharing_wrapper` | 1064 | 154 | 244.1 ps | 2 operands, latency 4 |

The fifteen raw-wire units, the arithmetic between an `unbundle` and a
`bundle`, are combinational by construction and there is nothing to say about
any of them beyond the number:

| unit | cells | path |
|---|---|---|
| `arith_addi` | 130 | 503.0 ps |
| `arith_andi` | 32 | 10.3 ps |
| `arith_cmpi` | 115 | 145.4 ps |
| `arith_constant` | 0 | no path |
| `arith_extsi` | 0 | 0.0 ps |
| `arith_extui` | 0 | 0.0 ps |
| `arith_muli` | 2519 | 683.6 ps |
| `arith_ori` | 32 | 11.9 ps |
| `arith_select` | 70 | 81.6 ps |
| `arith_shli` | 356 | 203.5 ps |
| `arith_shrsi` | 381 | 229.6 ps |
| `arith_shrui` | 351 | 202.1 ps |
| `arith_subi` | 174 | 481.1 ps |
| `arith_trunci` | 0 | 0.0 ps |
| `arith_xori` | 32 | 18.6 ps |

## vendor

Seven units, and they are one unit seven times: the floating-point operators
under `fpu_impl=vivado`.

| unit | evidence |
|---|---|
| `addf`, `subf`, `mulf`, `divf`, `cmpf`, `maximumf`, `minimumf` | `data/vhdl/support/vivado_ip_cores.vhd` declares `COMPONENT floating_point_v7_1_8` five times and no entity of that name exists anywhere in the repository. GHDL stops at `cannot find resource library "floating_point_v7_1_8"` before anything is elaborated. |

Two things make this less alarming than it looks, and one makes it worse.

The interface's own fallback is `FLOPOCO`, and the `dynamatic` frontend passes
`flopoco` (`tools/dynamatic/dynamatic.cpp:98`), so an ordinary compile never
reaches the IP. The FloPoCo cores are portable: 111,736 lines of plain
behavioural VHDL over `std_logic_arith`, with no LUT, carry or DSP primitive
in them, and all seven operators map on ASAP7 through that path (`addf` 1,398
cells and 65 flip-flops at 1,044 ps, `mulf` 9,076 and 1,561 at 846 ps, `divf`
9,339 and 1,494 at 761 ps, `cmpf` 225 and 3 at 206 ps).

However, the MLIR pass's own default is broken. The `impl` option of
`handshake-set-unit-impl-attr` defaults to `"VIVADO"`
(`include/dynamatic/Transforms/Passes.td:406`), but the enum's string forms
are lowercase (`flopoco`, `vivado`) and the lookup is case-sensitive, so the
default is not a value at all: run without `impl=`, the pass stops with
`Invalid FPU implementation: 'VIVADO'`. Nothing in the repository's own flow
reaches it, since `compile.sh` always passes `impl=$FPUNITS_GEN` and the
frontend sets that to `flopoco`. The vendor IP is reached only by asking for
it, `impl=vivado`. In addition, nothing ties the choice to the target at all,
which is the open item this audit was supposed to size.

A cell-library implementation is not needed here. FloPoCo already is one, and
what has to be written is a default and a link to `target`, not a unit.

Moreover, the FloPoCo path has a sharp edge of its own worth recording. The
wrapper instantiates `{core}_{bitwidth}_{internal_delay}`, and the shipped
library holds a fixed, discrete set of (width, delay) pairs
(`FloatingPointAdder_32_9_068000`, `FloatingPointMultiplier_32_2_034000`, and
so on, 22 cores of the three kinds in all). An `internal_delay` the library does not
hold does not elaborate; the number of `ce_` ports must equal `LATENCY`
exactly; and the delay comes out of the timing model, which is
re-characterised per PDK. A new PDK can therefore ask for a core that does not
exist.

## fpga-shaped

Eight units, in three families. All of them build; none of them is the shape
an ASIC designer would have chosen.

### The pipelined multiplier

`muli` at its default `impl=pipelined` is the plan's archetype: the
operands into a register, the whole array multiply in one combinational sweep,
then three delay registers. An FPGA tool retimes that into the DSP pipeline.
Nothing on a cell library does, so the full multiplier sits between two
registers and the delay registers are (pure) area.

| | cells | flip-flops | path |
|---|---|---|---|
| `muli` 32 bits, pipelined | 3,170 | 164 | 760.0 ps |
| `muli` 32 bits, sequential, step 8 | 1,532 | 101 | 696.6 ps |
| `muli` 64 bits, pipelined | 11,559 | 324 | 1,171.6 ps |
| `muli` 64 bits, sequential, step 8 | 3,442 | 198 | 838.1 ps |

At 64 bits the pipelined unit misses a 1 ns clock and the sequential one makes
it, which is the same result that was measured for the divider. Furthermore, a
second defect sits underneath. The data path's depth is hardcoded (`a_reg`,
`q0`, `q1`, `q2`, four stages) while `LATENCY` only sizes the
valid-propagation buffer, so the unit is correct at `LATENCY=4` and silently
wrong at any other value.

### The Vitis-derived integer dividers

`divui`, `divsi`, `remui` and `remsi` at `impl=pipelined` reach
`vitis_hls_cores.vhd`. That file is not a black box, unlike the Vivado IP: it
is Vitis HLS's own VHDL output, generic in width, and it maps. What it maps to
is one restoring-division stage per bit.

| unit, 32 bits | pipelined cells / FFs | sequential cells / FFs |
|---|---|---|
| `divui` | 17,353 / 3,172 | 645 / 103 |
| `divsi` | 17,531 / 3,205 | 863 / 104 |
| `remui` | 15,649 / 2,676 | 608 / 104 |
| `remsi` | 15,649 / 2,676 | 862 / 105 |

`remui` and `remsi` are identical because the pipelined `remsi` instantiates
the unsigned core, a defect that was documented by the sequential work. The
cell-library implementation exists (endrix/dynamatic#45 and #55) and is
selected by `target`; what remains is that the pipelined unit is still chosen
by default when no target is given.

In addition, one wart follows from this and is cheap to close. The RTL entries
for the four dividers carry `"dependencies": ["vitis_hls_cores"]`
unconditionally, so the file is copied into every export whatever
implementation was chosen. The picorv32 exports of the run
`/mnt/data/claude-scratch/rerun/b9/out/cells-1` (seven of them) contain `vitis_hls_cores.vhd` although its only division is a sequential
`divui` and nothing instantiates the core. It is analysed on every synthesis
for nothing.

### The float-integer conversions

`sitofp`, `uitofp` and `fptosi` are one combinational `to_float` (or
`to_signed`) conversion followed by five hardcoded delay registers. The
comment in the corresponding static unit says why: "this 5 stage latency is
used to imitate the latency of the Vitis IP". That is an FPGA-retiming
assumption stated outright.

| unit | cells | flip-flops | path |
|---|---|---|---|
| `sitofp` | 1,033 | 160 | 833.0 ps |
| `uitofp` | 968 | 155 | 659.2 ps |
| `fptosi` | 1,090 | 165 | 596.7 ps |

The 160 flip-flops are 5 x 32 bits of delay in front of a converter that is a
few hundred cells of logic. The ASIC form is the conversion with a latency the
unit actually implements: either one cycle, which the logic already supports
(the path is 833 ps at the worst of the three, so it closes at 1 ns), or a
genuine split of the normalisation across stages if a shorter period is
wanted. It is the same change the multiplier needs, and about the same size
(the sequential multiplier is roughly 120 lines of generator).

## memory

| unit | evidence |
|---|---|
| `ram` | 1024 words of 32 bits maps to 163,728 cells and 32,800 flip-flops. Above `sram_threshold` and with no declared initial content the generator also writes a synthesis view under `sram/`, the same entity wrapping a macro: FakeRAM2.0 for ASAP7 (one read-write port, a macro generated from the name pattern) or OpenRAM's 1rw1r for sky130 (fixed sizes, padded). The view is written when the memory has at least `sram_threshold` words and its declared content is all zeros (`_is_sram`); any other content keeps the array as flops. This audit did not measure a macro: its `sram_interface=openram` run had no `sram_macros` and fell back to flops. |
| `mem_to_bram` | pure combinational wiring to a dual-port block-RAM interface (`ce0`/`we0`/`address0`/`dout0` and the same again for port 1); 0 cells. It is the adapter required by the FPGA top level, and has no meaning against a macro (there is no second port to drive). |

As a result, `mem_controller` is not in this class. It is the arbiter rather
than the storage, and it is mapped to 621 cells and 68 flip-flops at 587 ps;
the block-RAM-shaped interface it drives is a naming question and not a
mapping one.

## needs a look

| unit | why it is not settled |
|---|---|
| `ii_monitor` | it maps to 0 cells because it is a simulation monitor that prints, and whether a unit that synthesizes to nothing should be in a tape-out flow at all is a decision rather than a measurement. |
| `sharing_wrapper` | it maps standalone (1,064 cells, 154 flip-flops, 244 ps) and it needs `sharing_support.vhd`, which is portable. What this audit did not do is exercise it inside a design, and there is no evidence either way about its protocol here; the deadlock the streamblocks helper-sharing experiment found was in that lowering's own shared instances, not in this unit. The protocol question is open, and it is not a cell-library question. |

## Defects that have nothing to do with the target

Six things in the library do not work at any target. They were found by
generating each unit and reading what came out, which is not something reading
the generator would have found.

- **`ndwire` emits VHDL that does not parse, at every width.** With data it
  drops the separator after `outs_ready` and leaves a trailing `;` in the port
  list (`';' or ')' expected after interface`). Without data the architecture
  writes `ins_valid and (state = RUNNING)`, an `and` between `std_logic` and
  `boolean`, for which no operator is declared. The unit is a
  non-determinism source for formal tools, which is presumably why nobody has
  hit it.
- **`SHIFT_REG_BREAK_DV` cannot be generated with data.**
  `_generate_shift_reg_break_dv` calls `_generate_shift_reg_break_dv_dataless(inner_name)`
  and the callee takes `(name, num_slots)`, so any `bitwidth > 0` raises
  `TypeError`. The dataless form is fine (15 cells, 4 flip-flops). One of the
  six buffer implementations, unusable.
- **`handshake.rigidifier` has no generator.** The entry is in
  `data/rtl-config-vhdl.json` and `vhdl-unit-generator.py` registers no
  `rigidifier`, so it raises `Module type rigidifier not found`.
- **`valid_merger` does not elaborate with extra signals.** The inner entity
  has ports `lhs_ins`/`lhs_outs` and the signal manager maps `lhs_in`/`lhs_out`.
  Extra signals are the only reason the unit exists (it is a speculation
  unit), so as shipped it is dead.
- **`join` and `top_join` do not elaborate with extra signals.** The unary
  signal manager declares `ins_valid : in std_logic` and the inner join takes
  `ins_valid : in std_logic_vector(size-1 downto 0)`; GHDL reports
  `can't associate "ins_valid" with port "ins_valid"`. A signal manager for an
  N-input unit is not a unary signal manager.
- **`cmpf`, `maximumf` and `minimumf` under `vivado` are broken before the IP
  matters.** The body references `oehb_ready`, a signal the arithmetic
  boilerplate stopped declaring, and passes generics `ID` and `NUM_STAGE` that
  the wrapper does not have.

In addition, five units refuse extra signals deliberately and say so: `divui`,
`divsi`, `remui`, `remsi` and `muli` under `impl=sequential` ("the sequential
divider carries no extra signals"). Every other unit has a signal-manager
path. The consequence is worth naming: extra signals exist for speculation,
and the sequential units are what a cell-library target selects, so
speculation and a cell library cannot be combined today.

Finally, one further finding, taken from the mapped netlists rather than from
the sources. The library's reset is synchronous everywhere except in one
place among the per-unit netlists: the `speculator_predictor` process inside
`speculator` is sensitive to `rst`, and it accounts for all 32 `DFFASRHQNx1`
cells there. The LSQ is the other: its generator writes `if reset = '1' ...
elsif rising_edge` processes and its netlist has 41 `DFFASRHQNx1`. The
`ndwire` generator is asynchronous as well, though it never reaches a netlist
because its output does not parse. A mixed reset style needs its own reset tree and a synchronizer (a
reset is not a data signal), so it is worth closing whether or not
speculation is used.

## The LSQ

The LSQ has its own generator and is worth a line. It is portable (no vendor
marker anywhere under `tools/backend/lsq-generator-python/`), and an instance
with eight load and eight store entries, 32-bit data, a 10-bit address and one
port of each maps to 7,309 cells and 821 flip-flops at 556 ps on ASAP7 SLVT.
Two observations. In the first place, its ports are `clock` and `reset`, where
every other unit in the library uses `clk` and `rst`, so `report-timing.sh`
cannot time it standalone without a shim (it constrains `clk` by name). And
the core emits a VHDL `assert`, which yosys carries into the netlist as a
`$assert` black box.

## What picorv32 uses

This matters because it separates "blocks our work" from "blocks someone
else's". Taking the unit type out of the header line of every generated file
across the seven exports of a picorv32 Core run, the design instantiates 35
handshake units and 13 raw-wire ones:

`addi`, `andi`, `blocker`, `buffer`, `bundle`, `cmpi`, `cond_br`, `constant`,
`control_merge`, `divui`, `extsi`, `extui`, `fork`, `init`, `lazy_fork`,
`load`, `mem_controller`, `merge`, `muli`, `mux`, `noti`, `ori`, `queue`,
`ram`, `select`, `shli`, `shrui`, `sink`, `source`, `store`, `subi`,
`top_join`, `trunci`, `unbundle`, `xori`, and `arith_` versions of `addi`,
`andi`, `cmpi`, `constant`, `extsi`, `extui`, `ori`, `select`, `shli`,
`shrui`, `subi`, `trunci`, `xori`.

Every one of them is in the **fine** class, with three qualifications. `divui`
and `muli` are in the design as sequential units already (`{'impl':
'sequential'}` on both), so the fpga-shaped default never reaches the design.
`ram` is there, 32 words of 32 bits with a `sram_threshold` of 64, so it is
below the threshold and is flops whatever the target does. And the export
carries `vitis_hls_cores.vhd` that nothing instantiates, for the reason given
above.

No float unit, no speculation unit, no `ndwire`, no `sharing_wrapper`, no LSQ.
So none of the twenty-one units that are not plainly fine blocks the picorv32
work, and the two that used to (`divui`, `muli`) were closed before this
audit.

## What to fix first

1. **The `VIVADO` default on `handshake-set-unit-impl-attr`.** It is one
   token in a `.td` file and it is not a valid value, so the pass fails when
   no `impl` is given. Making it `flopoco`, the interface's own fallback and
   the frontend's argument, is the one-token fix; making the choice follow
   `target` is the larger item the plan has.
2. **The five delay registers in `sitofp`, `uitofp` and `fptosi`.** The
   three carry 480 flip-flops at 32 bits, of which 15 are the valid pipeline
   and the rest five 32-bit data stages, behind combinational converters that
   close at 1 ns without them. A one-cycle unit keeps one stage, so the saving
   is about four fifths of the data flip-flops. They share the multiplier's
   defect too: `LATENCY` sizes only the valid pipeline while the data depth is
   fixed at five, so the unit is wrong at any other latency. The change is shaped like the
   sequential multiplier's and is about the same size; unlike the multiplier,
   no retiming story has to be preserved here, only a copied Vitis latency.
3. **`ndwire` and `SHIFT_REG_BREAK_DV`.** `ndwire` produces VHDL no tool
   can read at every width; `SHIFT_REG_BREAK_DV` cannot be generated with
   data, nor dataless with extra signals, and is fine only dataless without. Both are a few lines, and
   they are ranked here on cost rather than on importance: a library in which a
   sixth of the buffer implementations cannot be generated is a library
   nobody has run over.
4. **The unconditional `vitis_hls_cores` dependency.** The four divider
   entries should carry it only when the implementation is the pipelined one,
   the way `IMPL` already reaches the generator. Today every cell-library
   export ships and analyses Vitis HLS VHDL it does not instantiate.

Finally, the multiplier is deliberately kept off this list. It is already
covered by `target` and by an open piece of work on a genuinely pipelined
third implementation, and the units above are not covered by anything.

## Reproducing

```bash
SYNTH=/path/to/synthesis        # where install_synthesis_tools.sh put yosys, ghdl, opensta, asap7
mkdir -p out/muli
export PATH=$SYNTH/yosys/bin:$SYNTH/ghdl/bin:$SYNTH/opensta/bin:$PATH
export GHDL_PREFIX=$SYNTH/ghdl/lib/ghdl ASAP7_DIR=$SYNTH/asap7 STA=$SYNTH/opensta/bin/sta

# one unit, with the parameters the flow would pass it
python3 tools/unit-generators/vhdl/vhdl-unit-generator.py \
  -n muli -o out/muli/muli.vhd -t muli -p bitwidth=32 latency=4 extra_signals={}

# its support files next to it (types.vhd, and whichever of sharing_support,
# vitis_hls_cores, flopoco_ip_cores define an entity it instantiates but does
# not define), then
tools/backend/report-timing.sh out/muli muli 1000
```

However, two parameter traps cost time when this is repeated. `value` on
`constant` and `arith_constant` is a bit-string, not an integer, and a decimal
reaches the VHDL unchecked (`outs_v <= "7";`). And a unit whose module name is
a VHDL keyword, which `select` and `constant` are when generated under their
own type name, produces a file that does not parse; the flow never does this
because it names modules `handshake_constant_0`.

Every number on this page is post-synthesis on ASAP7 SLVT TT at a 1 ns clock
with the Sklansky adder, which is `report-timing.sh` at its defaults as of
2026-09-22. There is no placement behind them, so they understate long wires
and overstate high-fan-out nets; what they are good for is the comparison
between two implementations of the same unit, which is what the page uses them
for.
