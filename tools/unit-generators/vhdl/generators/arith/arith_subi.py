from generators.support.raw_unit import generate_raw_unit


def generate_arith_subi(name, params):
    bitwidth = params["bitwidth"]
    body = f"""
  result_v <= std_logic_vector(unsigned(lhs_v) - unsigned(rhs_v));
"""
    return generate_raw_unit(
        name=name,
        op="subi",
        inputs=[("lhs", bitwidth), ("rhs", bitwidth)],
        outputs=[("result", bitwidth)],
        body=body,
    )
