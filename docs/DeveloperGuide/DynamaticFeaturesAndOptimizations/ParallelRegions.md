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
level, after `mark-memory-interfaces`, where a function is a graph of
blocks and its top-level loop nests are the natural regions: a nest starts
when its header is entered and is done when its exiting block leaves. A
nest is a candidate when one block enters it, one block leaves it, and to
one place. Consecutive candidates, the second entered from the first's
exiting block, are grouped while each new one is independent of every nest
already in the group:

- no value the earlier nest computes reaches the later one, whether
  through the branch into its header or by direct use from the exiting
  block (dominance allows it). A constant does not count, nor does a block
  argument the earlier nest only carries around unchanged, back to a free
  origin: the lowering re-makes constants and the later pass re-sources
  such values from the entry;
- no recorded memory dependence (`handshake.deps`) connects an access of
  one to an access of the other;
- of the memory both touch (function arguments and allocations are
  distinct memories; anything else is unknown), a memory both only read is
  free, and a memory one of them writes is free only when every access to
  it goes to a memory controller, which executes accesses in arrival
  order. That is the same trust in the dependence analysis that
  `mark-memory-interfaces` shows when it sends an access to a controller.
  An LSQ would have to serve both nests, which it cannot;
- neither nest holds an operation with memory behaviour other than a load
  or a store of a memref.

Each group of two or more nests becomes one entry of the attribute, in the
block ids the lowering will assign (position in the function), and a
remark names it. On `mvt_float`'s cf IR the pass finds `[1, 2, 3] [4, 5,
6] between blocks 0 and 7`, and the lowering forwards the attribute.

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

## Measured

`mvt_float`, the fixture the passes were built against: 17996 cycles to
9004, bit-exact outputs, the second nest's stores starting one cycle after
the first's, no combinational loop on the flattened netlist. The
transformation pass's output on the hand-annotated IR is the hand-written
proof of concept up to names, and the chain from the C flow's cf IR
through the analysis, the lowering and the flow's own pass order gives the
same 9004.

## Not yet

- Regions that share written memory. They need an interface that orders
  each region's accesses among themselves and lets the regions interleave:
  outlining into callees, or an LSQ per region. The pass refuses them.
- A memory two regions only read is safe but gains nothing until it has two
  read ports.
- Regions with more than one exit, groups inside an enclosing loop, and
  regions that are not loop nests.
- The flow: neither pass is in `compile.sh` yet.
