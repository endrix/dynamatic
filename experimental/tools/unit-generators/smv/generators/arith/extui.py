from generators.support.delay_buffer import generate_delay_buffer
from generators.support.arith_utils import *
from generators.support.utils import *


def generate_extui(name, params):
    latency = params[ATTR_LATENCY]
    input_type = SmvScalarType(params[ATTR_IN_BITWIDTH])
    output_type = SmvScalarType(params[ATTR_OUT_BITWIDTH])
    abstract_data = params[ATTR_ABSTRACT_DATA]

    if abstract_data:
        return generate_abstract_unary_op(name, latency, output_type)
    else:
        return _generate_extui(name, latency, input_type, output_type)


def _generate_extui(name, latency, input_type, output_type):
    # A one-bit channel is a boolean in these models, and `extend` takes a
    # word: the boolean is made a one-bit word first, and zero-extended.
    word = "word1(ins)" if input_type.bitwidth == 1 else "ins"
    return f"""
{generate_unanary_op_header(name)}
  DEFINE outs := extend({word}, {output_type.bitwidth - input_type.bitwidth});
  
  {generate_delay_buffer(f"{name}__delay_buffer", {ATTR_LATENCY: latency})}
"""
