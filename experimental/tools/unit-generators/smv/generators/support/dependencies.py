import re


def combinational_reads(text, module):
    """What each DEFINE of `module` in the SMV `text` reads, transitively,
    through the module's other DEFINEs: the module's parameters and
    variables it ends at. A combinational path from an input to an output of
    the unit is a DEFINE of the output reading the input."""
    m = re.search(r"^MODULE\s+" + re.escape(module) + r"\s*\(([^)]*)\)(.*?)(?=^MODULE\s|\Z)", text, re.M | re.S)
    if not m:
        raise ValueError(f"no module {module}")
    body = m.group(2)
    defines = {}
    for block in re.findall(r"DEFINE(.*?)(?=^\s*(?:VAR|ASSIGN|DEFINE|INVAR|TRANS|INIT)\b|\Z)", body, re.M | re.S):
        for name, expr in re.findall(r"(\w+)\s*:=\s*(.*?);(?=\s*(?:\w+\s*:=|--|$))", block, re.S):
            defines[name] = set(re.findall(r"\b[A-Za-z_]\w*\b", expr)) - {"case", "esac", "TRUE", "FALSE"}
    closure = {}

    def reads(name, stack=()):
        if name in closure:
            return closure[name]
        if name not in defines or name in stack:
            return {name}
        out = set()
        for d in defines[name]:
            out |= reads(d, stack + (name,)) if d in defines else {d}
        closure[name] = out
        return out

    return {name: reads(name) for name in defines}
