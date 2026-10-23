import re


def add_reset(text):
    """The SMV model of a unit a `handshake.commit` stops (`KILL_RESET`): the
    same model with a reset input, `rst`, its last parameter, driven by the
    commit's `kill` (export-rtl maps it there for such a unit). The RTL's
    reset is synchronous, so a state variable is back at its initial value
    the step after `rst`: every `next(v) := e;` of a variable with an
    `init(v) := i;` becomes `next(v) := rst ? i : (e);`, in every module of
    the text, and every instance of a module of the text is handed `rst`.
    A variable with no `init` is a free choice and stays one.
    """
    modules = re.findall(r"^[ \t]*MODULE\s+(\w+)", text, re.M)

    def module_header(m):
        params = m.group(3)
        if params is None or not params.strip():
            return f"{m.group(1)}MODULE {m.group(2)}(rst)"
        return f"{m.group(1)}MODULE {m.group(2)}({params}, rst)"

    # (a generator may indent a MODULE line: the data control_merge does)
    text = re.sub(r"^([ \t]*)MODULE\s+(\w+)\s*(?:\(([^)]*)\))?", module_header, text, flags=re.M)

    # the instances of the text's own modules
    def instances(line):
        if line.lstrip().startswith("MODULE"):
            return line
        for name in modules:
            out, i = "", 0
            for m in re.finditer(rf"\b{re.escape(name)}\(", line):
                start = m.end()
                depth, j = 1, start
                while depth:
                    depth += {"(": 1, ")": -1}.get(line[j], 0)
                    j += 1
                args = line[start:j - 1]
                out += line[i:start] + (f"{args}, rst" if args.strip() else "rst") + ")"
                i = j
            line = out + line[i:]
        return line

    text = "\n".join(instances(line) for line in text.split("\n"))

    # the reset of every initialized variable, module by module
    parts = re.split(r"(?=^[ \t]*MODULE\s)", text, flags=re.M)
    out = []
    for part in parts:
        inits = dict(re.findall(r"init\((\w+)\)\s*:=\s*([^;]+);", part))
        res, pos = "", 0
        for m in re.finditer(r"next\((\w+)\)\s*:=", part):
            var = m.group(1)
            if var not in inits or m.start() < pos:
                continue
            j, depth = m.end(), 0
            while True:
                if part.startswith("case", j) and not part[j + 4:j + 5].isalnum():
                    depth += 1
                    j += 4
                    continue
                if part.startswith("esac", j) and not part[j + 4:j + 5].isalnum():
                    depth -= 1
                    j += 4
                    continue
                if part[j] == ";" and depth == 0:
                    break
                j += 1
            expr = part[m.end():j]
            res += part[pos:m.end()] + f" rst ? {inits[var].strip()} : ({expr.strip()})"
            pos = j
        out.append(res + part[pos:])
    return "".join(out)
