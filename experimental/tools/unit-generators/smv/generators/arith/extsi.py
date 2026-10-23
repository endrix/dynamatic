from generators.support.delay_buffer import generate_delay_buffer
from generators.support.arith_utils import *
from generators.support.utils import *


def generate_extsi(name, params):
    latency = params[ATTR_LATENCY]
    input_type = SmvScalarType(params[ATTR_IN_BITWIDTH])
    output_type = SmvScalarType(params[ATTR_OUT_BITWIDTH])
    abstract_data = params[ATTR_ABSTRACT_DATA]

    if abstract_data:
        return generate_abstract_unary_op(name, latency, output_type)
    elif input_type.bitwidth == 1:
        return _generate_extsi_bool(name, latency, input_type, output_type)
    else:
        return _generate_extsi(name, latency, input_type, output_type)


# The channels are unsigned words, and `extend` of an unsigned word fills with
# zeros: a sign extension extends the SIGNED word and reads it back unsigned
# (-1 at 4 bits is 1111 at 8, not 00001111).
def _generate_extsi(name, latency, input_type, output_type):
    return f"""
{generate_unanary_op_header(name)}
  DEFINE outs := unsigned(extend(signed(ins), {output_type.bitwidth - input_type.bitwidth}));
  
  {generate_delay_buffer(f"{name}__delay_buffer", {ATTR_LATENCY: latency})}
"""


# A one-bit channel is a boolean: a one-bit word first, whose one bit is the
# sign, so TRUE becomes all ones (the mask a priority step makes of a test).
def _generate_extsi_bool(name, latency, input_type, output_type):
    return f"""
{generate_unanary_op_header(name)}
  DEFINE outs := unsigned(extend(signed(word1(ins)), {output_type.bitwidth - input_type.bitwidth}));
  
  {generate_delay_buffer(f"{name}__delay_buffer", {ATTR_LATENCY: latency})}
"""
