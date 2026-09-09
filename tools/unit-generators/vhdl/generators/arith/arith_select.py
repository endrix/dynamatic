from generators.support.raw_unit import generate_raw_unit


def generate_arith_select(name, params):
    bitwidth = params["bitwidth"]
    body = """
  result_v <= true_value_v when condition_v(0) = '1' else false_value_v;
"""
    return generate_raw_unit(
        name=name,
        op="select",
        inputs=[("condition", 1), ("true_value", bitwidth),
                ("false_value", bitwidth)],
        outputs=[("result", bitwidth)],
        body=body,
    )
