from generators.support.unary import generate_unary, generate_delay_stages


def generate_sitofp(name, params):
    latency = params["latency"]

    # The conversion is one combinational step; its result is delayed by
    # the unit's latency, the depth of the valid propagation buffer, so data
    # and valid leave together at any latency. (The stages were five
    # regardless, copying the Vitis IP's latency, and the unit was wrong at
    # any other.)
    delay_signals, delay_body = generate_delay_stages(
        "converted", "outs", 32, latency)

    signals = f"""
  signal converted : std_logic_vector(32 - 1 downto 0);
  signal float_value : float32;
{delay_signals}
    """

    body = f"""
  float_value <= to_float(signed(ins));
  converted <= to_std_logic_vector(float_value);

{delay_body}
    """

    return generate_unary(
        name=name,
        handshake_op="sitofp",
        input_bitwidth=32,
        output_bitwidth=32,
        signals=signals,
        body=body,
        extra_signals=params.get("extra_signals", None),
        latency=latency
    )
