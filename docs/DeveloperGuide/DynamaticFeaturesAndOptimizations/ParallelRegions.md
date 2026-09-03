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

`mvt_float`, the fixture the pass was built against: 17996 cycles to 9004,
bit-exact outputs, the second nest's stores starting one cycle after the
first's, no combinational loop on the flattened netlist. The pass's output
is the hand-written proof of concept up to names.

## Not yet

- Regions that share written memory. They need an interface that orders
  each region's accesses among themselves and lets the regions interleave:
  outlining into callees, or an LSQ per region. The pass refuses them.
- A memory two regions only read is safe but gains nothing until it has two
  read ports.
- Regions with more than one exit, or a group inside a loop.
- The analysis that writes the attribute (`--cf-detect-parallel-regions`).
