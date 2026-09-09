from generators.support.raw_unit import generate_raw_unit


def generate_arith_xori(name, params):
    bitwidth = params["bitwidth"]
    body = f"""
  result_v <= lhs_v xor rhs_v;
"""
    return generate_raw_unit(
        name=name,
        op="xori",
        inputs=[("lhs", bitwidth), ("rhs", bitwidth)],
        outputs=[("result", bitwidth)],
        body=body,
    )
