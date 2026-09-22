from generators.support.arith_binary import generate_arith_binary
from generators.support.sequential_divider import generate_sequential_divider


def generate_remui(name, params):
    impl = params.get("impl", "pipelined")
    if impl == "sequential":
        return _generate_remui_sequential(name, params)
    if impl != "pipelined":
        raise ValueError(f"remui: unknown impl {impl!r} (pipelined or sequential)")
    return _generate_remui_pipelined(name, params)


def _generate_remui_pipelined(name, params):

    latency = params["latency"]
    # FIXME: The latency of the long division depends on the bitwidth, but it
    # was hardcoded to 35 in the performance model.
    #
    # Here, we use the actual latency of the Vitis IP (see below for the
    # formula). This wouldn't change most of our benchmarks in the integration
    # tests (they use 32-bit division in any case), but we need to remember to
    # change the timing model to reflect this.
    bitwidth = params["bitwidth"]
    # The long division algorithm in the Vitis IP needs:
    # 2 cycles from the input/output regs
    # 1 cycle from the input reg of the division unit
    # BITWIDTH number for the actual division.
    latency = bitwidth + 2 + 1

    extra_signals = params.get("extra_signals", None)

    body = f"""
    remui_vitis_hls_wrapper_U1 : entity work.remui_vitis_hls_wrapper
    generic map({bitwidth}, {bitwidth}, {bitwidth})
    port map(
      clk   => clk,
      reset => rst,
      ce    => valid_buffer_ready,
      din0  => lhs,
      din1  => rhs,
      dout  => result
    );
    """

    return generate_arith_binary(
        name=name,
        handshake_op="remui",
        bitwidth=bitwidth,
        body=body,
        latency=latency,
        extra_signals=extra_signals
    )


def _generate_remui_sequential(name, params):
    """The unsigned remainder of the shared sequential iteration: the
    same BITWIDTH restoring steps a divui runs, the remainder register
    leaving instead of the quotient one. A zero divisor gives the dividend
    back, the way the Vitis IP does. Latency BITWIDTH + 1."""

    if params.get("extra_signals", None):
        raise ValueError("remui: the sequential unit carries no extra signals")
    return generate_sequential_divider(
        name, "remui", params["bitwidth"], signed=False,
        remainder=True)
