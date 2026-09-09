from generators.support.raw_unit import generate_raw_unit


def generate_arith_extui(name, params):
    input_bitwidth = params["input_bitwidth"]
    output_bitwidth = params["output_bitwidth"]
    body = f"""
  outs_v({output_bitwidth} - 1 downto {input_bitwidth}) <= (others => '0');
  outs_v({input_bitwidth} - 1 downto 0) <= ins_v;
"""
    return generate_raw_unit(
        name=name,
        op="extui",
        inputs=[("ins", input_bitwidth)],
        outputs=[("outs", output_bitwidth)],
        body=body,
    )
