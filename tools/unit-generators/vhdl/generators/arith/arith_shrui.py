from generators.support.raw_unit import generate_raw_unit


def generate_arith_shrui(name, params):
    bitwidth = params["bitwidth"]
    # `to_integer` takes at most 31 bits; the amount is read from the low bits
    # that fit, and a set bit above them is a shift by at least the width.
    low = min(bitwidth, 31)
    signals = "  signal amount : natural;\n  signal overflow : std_logic;"
    if bitwidth > low:
        high = f"""
  overflow <= '0' when unsigned(rhs_v({bitwidth} - 1 downto {low})) = 0 else '1';"""
    else:
        high = """
  overflow <= '0';"""
    body = f"""
  amount <= to_integer(unsigned(rhs_v({low} - 1 downto 0)));{high}
  result_v <= std_logic_vector(shift_right(unsigned(lhs_v), amount)) when overflow = '0' else (others => '0');
"""
    return generate_raw_unit(
        name=name,
        op="shrui",
        inputs=[("lhs", bitwidth), ("rhs", bitwidth)],
        outputs=[("result", bitwidth)],
        body=body,
        signals=signals,
    )
