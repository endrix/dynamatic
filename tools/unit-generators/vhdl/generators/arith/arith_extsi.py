from generators.support.raw_unit import generate_raw_unit


def generate_arith_extsi(name, params):
    input_bitwidth = params["input_bitwidth"]
    output_bitwidth = params["output_bitwidth"]
    body = f"""
  outs_v({output_bitwidth} - 1 downto {input_bitwidth}) <= (others => ins_v({input_bitwidth} - 1));
  outs_v({input_bitwidth} - 1 downto 0) <= ins_v;
"""
    return generate_raw_unit(
        name=name,
        op="extsi",
        inputs=[("ins", input_bitwidth)],
        outputs=[("outs", output_bitwidth)],
        body=body,
    )
