from generators.support.raw_unit import generate_raw_unit


def generate_arith_ori(name, params):
    bitwidth = params["bitwidth"]
    body = f"""
  result_v <= lhs_v or rhs_v;
"""
    return generate_raw_unit(
        name=name,
        op="ori",
        inputs=[("lhs", bitwidth), ("rhs", bitwidth)],
        outputs=[("result", bitwidth)],
        body=body,
    )
