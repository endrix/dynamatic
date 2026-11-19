"""bound_sizes.py <dynamatic source root>: report_parser.bound_sizes on a model
of two units at two and three sizes, the port models printed per signal and width."""
import json
import sys

sys.path.insert(0, f"{sys.argv[1]}/tools/backend/synth-characterization")
import report_parser  # noqa: E402


def entry(outport_valid, data_widths):
    return {"latency": {}, "delay": {
        "data": {w: 0.0 for w in data_widths},
        "valid": {"1": 0.0}, "ready": {"1": 0.0},
        "VR": 0.0, "CV": 0.0, "CR": 0.0, "VC": 0.0, "VD": 0.0},
        "inport": report_parser.ZERO_PORT_MODEL,
        "outport": {"delay": {"data": {"64": 0.0}, "valid": outport_valid,
                              "ready": {"1": 0.0},
                              "VR": 0, "CV": 0, "CR": 0, "VC": 0, "VD": 0}}}


ALL = ["1", "2", "4", "8", "16", "32", "64", "128"]
SIZED = ["1", "8", "32", "64"]
model = {
    # the base size, at every width; 0.5 at 4 bits and 0.9 at 128
    "u.size.2": entry({"1": 0.1, "2": 0.1, "4": 0.5, "8": 0.1, "16": 0.1,
                       "32": 0.1, "64": 0.1, "128": 0.9}, ALL),
    # past it, at SIZED_WIDTHS only: longer than the base at 8 bits and up
    "u.size.3": entry({"1": 0.2, "8": 0.3, "32": 0.4, "64": 0.6}, SIZED),
    # shorter than size 3 at 32 bits (ABC maps each size afresh)
    "u.size.4": entry({"1": 0.2, "8": 0.3, "32": 0.35, "64": 0.7}, SIZED),
    # a base that rises from 2 to 8 bits, above size 3's own 8-bit delay
    "v.size.2": entry({"1": 0.1, "2": 0.1, "4": 0.1, "8": 0.5, "16": 0.1,
                       "32": 0.1, "64": 0.1, "128": 0.2}, ALL),
    # past the base's 128 bits, its own 64-bit delay is the larger
    "v.size.3": entry({"1": 0.2, "8": 0.3, "32": 0.3, "64": 0.8}, SIZED),
}
report_parser.bound_sizes(model)
for key in model:
    valid = model[key]["outport"]["delay"]["valid"]
    print(key, " ".join(f"{w}:{valid[w]}" for w in sorted(valid, key=int)))
    inport = model[key]["inport"]
    print(key, "inport", "zero" if inport == report_parser.ZERO_PORT_MODEL else json.dumps(inport))
