from generators.support.arith_binary import generate_arith_binary
from generators.support.sequential_divider import generate_sequential_divider


def generate_remsi(name, params):
    impl = params.get("impl", "pipelined")
    if impl == "sequential":
        return _generate_remsi_sequential(name, params)
    if impl != "pipelined":
        raise ValueError(f"remsi: unknown impl {impl!r} (pipelined or sequential)")
    return _generate_remsi_pipelined(name, params)


def _generate_remsi_pipelined(name, params):
    # KNOWN WRONG, and kept because it is what the FPGA flow has always
    # built: the wrapper this instantiates
    # (data/vhdl/support/vitis_hls_cores.vhd, and data/verilog/arith/remsi.v)
    # reaches the UNSIGNED Vitis core, so it computes the unsigned remainder
    # under a signed name. Measured against the signed core's own remainder
    # port: it differs on 40,386 of the 65,536 8-bit operand pairs, and
    # -128 rem -1 comes out -128 where it is 0. The sequential
    # implementation below is the signed answer and so does NOT agree with
    # this one. Correcting this means rewiring onto the signed core's
    # `remd`, which changes a shipped FPGA unit's answers and wants the
    # integration suite as its test surface: its own change, not this one.

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
    remsi_vitis_hls_wrapper_U1 : entity work.remsi_vitis_hls_wrapper
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
        handshake_op="remsi",
        bitwidth=bitwidth,
        body=body,
        latency=latency,
        extra_signals=extra_signals
    )


def _generate_remsi_sequential(name, params):
    """The signed remainder of the shared sequential iteration: the
    magnitudes divided, the remainder negated when the DIVIDEND is
    negative, which is C99's and RISC-V's sign rule and the one the Vitis
    signed division core's own `remd` output follows. Latency BITWIDTH +
    1."""

    if params.get("extra_signals", None):
        raise ValueError("remsi: the sequential unit carries no extra signals")
    return generate_sequential_divider(
        name, "remsi", params["bitwidth"], signed=True,
        remainder=True)
