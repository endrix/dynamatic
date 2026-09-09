from generators.support.raw_unit import generate_raw_unit


def generate_arith_constant(name, params):
    bitwidth = params["bitwidth"]
    value = params["value"]
    body = f"""
  outs_v <= "{value}";
"""
    return generate_raw_unit(
        name=name,
        op="constant",
        inputs=[],
        outputs=[("outs", bitwidth)],
        body=body,
    )
