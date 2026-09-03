# Parallel regions

The sequential lowering runs the regions of a function one after the other,
whatever their dependences. Two loop nests that touch disjoint memory and
share no value still form a chain: the exit branch of the first hands the
control token to the entry merge of the second, and the second cannot start
before the first has drained. On `mvt_float` that is one nest of 900
multiply-accumulates waiting on another of the same size.

`--handshake-parallelize-regions` removes that chain for groups of regions an
analysis has declared independent. It is off by default and does nothing to a
function without the attribute, so every existing flow is untouched.

## The analysis

`--cf-detect-parallel-regions` writes the attribute. It runs at the cf
level, after `mark-memory-interfaces`, where a function's top level is a
chain: a loop nest, a block or two of straight-line code, another nest,
and so on. A chain starts at a top-level loop with one entry, one exiting
block and one exit, and continues at its exit through such loops and
single-successor blocks until something else ends it, which is the block
the regions lead to; the block that enters the first loop is where they
start. A function may hold several chains.

The straight-line blocks join the loop after them (they are its preamble:
the next loop's constants, a lookahead's first reads), so every unit of
the chain holds a loop. Two units are dependent when:

- a value one computes reaches the other, through the branch into its
  first block or by direct use (dominance allows it). A constant does not
  count, nor does a block argument the unit only carries around unchanged,
  back to a free origin: the lowering re-makes constants and the later
  pass re-sources such values from the entry. A value handed to a block
  argument nothing reads carries nothing;
- a recorded memory dependence (`handshake.deps`) connects an access of
  one to an access of the other;
- they touch a common memory (function arguments and allocations are
  distinct memories; anything else is unknown) that one of them writes,
  unless every access to it goes to a memory controller that
  `mark-memory-interfaces` chose from the recorded dependences (it says so
  with `handshake.mem_interfaces_from_deps` on the function): such an
  access is one the dependence analysis found free of every other, and
  the controller executes accesses in arrival order. A controller that
  `force-memory-interface` put there says nothing, and the memory keeps
  the units in order. An LSQ would have to serve both units, which it
  cannot;
- an effect one declares on a value that is not a memref (a port, in
  streamblocks) meets an effect of the other on the same value, and one of
  them writes. Effects on different values are independent. An operation
  with an effect on nothing in particular makes its unit opaque, and
  nothing runs beside it. An allocation counts as nothing.

Regions are made within a range of consecutive units: everything before
the range is done when it starts, so only dependences inside the range
order anything. Within a range, dependent units merge into one region with
everything between them, and what is left is a run of regions no two of
which share a dependence. A unit that depends only on the last region
joins it. One that depends on an earlier region ends the range: the range
becomes a group when it holds two regions or more; when it holds one, a
new range starts right after the last unit the newcomer depends on, so
that the tail can still pair with it.

Each group becomes one entry of the attribute, in the block ids the
lowering will assign (position in the function), and a remark names it.
On `mvt_float`'s cf IR the pass finds `[1, 2, 3] [4, 5, 6] between blocks
0 and 7`; on streamblocks' two-lane relay, whose action is a pop loop into
a buffer and a push loop out of it per lane, `[1, 2, 3, 4, 5] [6, 7, 8, 9,
10, 11] between blocks 0 and 12`, the two lanes.

## The attribute

The pass reads `handshake.parallel_regions` on the function: an array of
groups, each a dictionary naming the block whose control starts the regions,
the regions as arrays of block ids in the order the sequential lowering ran
them, and the block they all lead to.

```mlir
handshake.func @mvt_float(...) attributes {
  handshake.parallel_regions = [{entry = 0 : ui32, regions = [[1, 2, 3], [4, 5, 6]], successor = 7 : ui32}]
}
```

Whoever writes the attribute is responsible for independence: no value flows
between the regions, no memory dependence crosses them, no LSQ serves two of
them. The pass checks what it can see in the Handshake IR (a live-out, a
`handshake.deps` edge between regions, an LSQ with inputs from two regions,
a second exit) and refuses the group with an error; it cannot see aliasing
that the analysis missed.

## What the pass does

For each group:

- The entry block's control, which fed the first region's control merge,
  now feeds every region's control merge. The serial edge from one region's
  exit branch into the next region's merge is gone.
- The regions' exit tokens (the false result of each region's exit branch)
  meet in a `join` in the successor block, which replaces the serial input of
  the successor's control merge.
- A value a later region received through an earlier region's exit branch is
  followed back through that region (branches, forks, buffers and
  loop-carried muxes are transparent) to where it came in. A value the entry
  block provided is used from the entry directly; a constant the lowering
  materialized inside the earlier region is re-made in the entry block,
  driven by the function's start. Anything else is a live-out and the group
  is refused.
- The wires that only carried those values out of a region -- the exit
  branch, and behind it the constants, forks and muxes that threaded them
  through the loop -- are erased.
- If the function carries `handshake.frequencies`, or the `frequencies`
  option names the profiler's CSV, the archs are rewritten to the new shape:
  the serial edges between regions dropped, an edge from the entry into
  every region added with the entry's count, an edge from every region into
  the successor added with the exit's count. The result is stored in the
  attribute, which buffer placement reads before any CSV.

Memory interfaces, `end` and block ids are untouched. The result is not
materialized (values gain and lose uses); run `handshake-materialize` after
it. Run it after `handshake-deactivate-mem-dependencies`, which reasons
over the sequential CFG and would otherwise see no path between the regions
and nothing to enforce.

## In the flow

`compile --parallel-regions` in the frontend (`PARALLEL_REGIONS`, the 20th
argument of `compile.sh`) runs the analysis before `lower-cf-to-handshake`
and the transformation right after `handshake-replace-memory-interfaces`,
before `handshake-materialize`. With a profile-driven buffer placement the
transformation is handed the profiler's CSV and stores the rewritten archs
on the function, which the placer reads before the CSV; the profile is
therefore taken before the handshake transformations instead of at
placement time, which changes nothing else. Fast token delivery does not
get the passes (it builds its own control network); the flag then says so
and does nothing.

The integration suite's `ParallelRegionsFixture` compiles the kernels the
analysis accepts (`mvt_float`, `kernel_3mm`, `kernel_3mm_float`, `lu`, from
a survey of all of them) with the flag, simulates them, records their
cycles for the performance report, and runs
`tools/backend/check-logic-loops.sh` on the export: yosys flattens the
design and asserts there is no combinational loop, which a simulator
would settle silently and buffer placement cannot see, having no timing
model for `join`. The script reads a Verilog export as is (a VHDL module
inside it, the LSQ, stays a black box) and a VHDL export through the GHDL
plugin; without yosys it reports that nothing was checked and the test
does not fail on it.

## Measured

`mvt_float`, the fixture the passes were built against: 17996 cycles to
9004, bit-exact outputs, the second nest's stores starting one cycle after
the first's, no combinational loop on the flattened netlist. The
transformation pass's output on the hand-annotated IR is the hand-written
proof of concept up to names, and the chain from the C flow's cf IR
through the analysis, the lowering and the flow's own pass order gives the
same 9004.

Through the frontend (`compile --parallel-regions`, VHDL, GHDL, outputs
checked against the C run, the export free of combinational loops), the
four kernels the analysis accepts, latency in cycles:

| kernel | placement | without | with |
|---|---|---|---|
| mvt_float | on-merges | 17997 | 9005 |
| mvt_float | fpga20 (cbc) | 17997 | 5291 |
| kernel_3mm | on-merges | 20006 | 14005 |
| kernel_3mm_float | on-merges | 31998 | 22001 |
| lu | on-merges | 619 | 613 |

With the fpga20 placement the MILP sees both nests' cycles through the
rewritten archs and pipelines them, which the serial design never let it
do: the on-merges and fpga20 latencies of the serial `mvt_float` are the
same 17997. `lu`'s second region is a single small block, so it gains
what that block costs.

## Not yet

- Regions that share written memory. They need an interface that orders
  each region's accesses among themselves and lets the regions interleave:
  outlining into callees, or an LSQ per region. The pass refuses them.
- A memory two regions only read is safe but gains nothing until it has two
  read ports.
- Regions with more than one exit, groups inside an enclosing loop, and
  regions that are not loop nests.
- The flow: neither pass is in `compile.sh` yet.
