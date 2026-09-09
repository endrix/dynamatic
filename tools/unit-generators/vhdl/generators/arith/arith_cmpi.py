from generators.support.raw_unit import generate_raw_unit


def generate_arith_cmpi(name, params):
    bitwidth = params["bitwidth"]
    predicate = params["predicate"]
    sign = _sign(predicate)
    symbol = _symbol(predicate)
    body = f"""
  result_v(0) <= '1' when ({sign}(lhs_v) {symbol} {sign}(rhs_v)) else '0';
"""
    return generate_raw_unit(
        name=name,
        op="cmpi",
        inputs=[("lhs", bitwidth), ("rhs", bitwidth)],
        outputs=[("result", 1)],
        body=body,
    )


def _symbol(predicate):
    match predicate:
        case "eq":
            return "="
        case "ne":
            return "/="
        case "slt" | "ult":
            return "<"
        case "sle" | "ule":
            return "<="
        case "sgt" | "ugt":
            return ">"
        case "sge" | "uge":
            return ">="
        case _:
            raise ValueError(f"Predicate {predicate} not known")


def _sign(predicate):
    match predicate:
        case "eq" | "ne":
            return ""
        case "slt" | "sle" | "sgt" | "sge":
            return "signed"
        case "ult" | "ule" | "ugt" | "uge":
            return "unsigned"
        case _:
            raise ValueError(f"Predicate {predicate} not known")
