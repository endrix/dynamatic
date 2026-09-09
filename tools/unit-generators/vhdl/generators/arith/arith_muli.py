from generators.support.raw_unit import generate_raw_unit


def generate_arith_muli(name, params):
    bitwidth = params["bitwidth"]
    body = f"""
  result_v <= std_logic_vector(resize(unsigned(lhs_v) * unsigned(rhs_v), {bitwidth}));
"""
    return generate_raw_unit(
        name=name,
        op="muli",
        inputs=[("lhs", bitwidth), ("rhs", bitwidth)],
        outputs=[("result", bitwidth)],
        body=body,
    )
