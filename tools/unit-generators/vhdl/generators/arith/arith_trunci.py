from generators.support.raw_unit import generate_raw_unit


def generate_arith_trunci(name, params):
    input_bitwidth = params["input_bitwidth"]
    output_bitwidth = params["output_bitwidth"]
    body = f"""
  outs_v <= ins_v({output_bitwidth} - 1 downto 0);
"""
    return generate_raw_unit(
        name=name,
        op="trunci",
        inputs=[("ins", input_bitwidth)],
        outputs=[("outs", output_bitwidth)],
        body=body,
    )
