from generators.support.utils import *


def parse_candidates(text, size_tokens, size_flags, bitwidth):
    """The candidates of a race from its CANDIDATES parameter
    (RaceOp::getCandidatesEncoding), as the VHDL generator reads them
    (tools/unit-generators/vhdl/generators/handshake/race.py): '/' between
    candidates, ':' between fields, `p<payload>` or `t<token>` first, then
    `f<flags>`, `u<unless>`, `a<after>`."""
    cands = []
    for k, entry in enumerate(text.split("/")):
        fields = entry.split(":")
        cand = {"payload": None, "token": None,
                "flags": [], "unless": [], "after": []}
        head = fields[0]
        if head[:1] == "p":
            cand["payload"] = int(head[1:])
            if not 0 < cand["payload"] < 2 ** bitwidth:
                raise ValueError(f"race candidate {k}: payload {head[1:]} is not a "
                                 f"non-zero {bitwidth}-bit value")
        elif head[:1] == "t":
            cand["token"] = int(head[1:])
            if not 0 <= cand["token"] < size_tokens:
                raise ValueError(f"race candidate {k}: no token input {head[1:]}")
        else:
            raise ValueError(f"race candidate {k}: '{entry}' starts with neither "
                             "a payload (p) nor a token (t)")
        for field in fields[1:]:
            key = {"f": "flags", "u": "unless", "a": "after"}.get(field[:1])
            if key is None:
                raise ValueError(f"race candidate {k}: unknown field '{field}'")
            cand[key] = [int(x) for x in field[1:].split(",") if x != ""]
        for f in cand["flags"] + cand["unless"]:
            if not 0 <= f < size_flags:
                raise ValueError(f"race candidate {k}: no flag input {f}")
        cands.append(cand)
    for k, cand in enumerate(cands):
        for j in cand["after"]:
            if not 0 <= j < len(cands) or j == k:
                raise ValueError(f"race candidate {k}: after {j}")
        if cand["token"] is None and not cand["flags"] and not cand["unless"]:
            raise ValueError(f"race candidate {k} reads no input")
    return cands


def generate_race(name, params):
    """A whole racing decision in one unit (`handshake.race`), as a NuSMV
    model: candidates over flags (a payload of their own) and tokens (the
    token's payload), the lowest-index winner the first cycle one wins --
    enabled, every candidate of its `after` refused -- zero the first cycle
    every candidate is refused, one answer a round, each input taken the cycle
    it arrives. Alternatives (candidates of one payload, or of one token) are
    terms like any other: those that win together carry the same payload.

    The state is the RTL generator's, register for register
    (tools/unit-generators/vhdl/generators/handshake/race.py): `seen_<i>`,
    the value each input arrived with (`tval_<t>`, `fval_<f>`), `winner`,
    `has_win`, `emitted`. There is no reset input in SMV, so `init()` carries
    what `rst` carries in the RTL. `verify-race.py` checks the model against a
    specification written apart from it.

    The round closes in the cycle it completes: an input that gave its token
    is ready again the cycle every other input arrived with the answer taken
    or being taken, and gives the next round's (`again_<i>`); with the answer
    out earlier, a next round those tokens decide is answered then (`e_`).
    The parameters: the tokens' payloads, their valids, the flags, their
    valids, the output's ready -- export-rtl's order for the arrays `tokens`
    and `flags`.
    """
    nt = params["size_tokens"]
    nf = params["size_flags"]
    data_type = SmvScalarType(params[ATTR_BITWIDTH])
    w = data_type.bitwidth
    if w == 0:
        raise ValueError(
            "handshake.race has no dataless form: the payload is the answer, "
            "and zero is 'nothing selected'.")
    if nt + nf == 0:
        raise ValueError("handshake.race has no input")
    cands = parse_candidates(params["candidates"], nt, nf, w)
    return _generate_race(name, nt, nf, data_type, cands, params["candidates"])


def _generate_race(name, nt, nf, data_type, cands, encoding):
    n = nt + nf
    w = data_type.bitwidth
    zero = data_type.format_constant(0)

    def nonzero(x):
        # a one-bit payload is a boolean in these models
        return x if w == 1 else f"{x} != {zero}"

    def iname(i):
        return f"tokens_{i}" if i < nt else f"flags_{i - nt}"

    params = [f"tokens_{t}" for t in range(nt)] + \
             [f"tokens_{t}_valid" for t in range(nt)] + \
             [f"flags_{f}" for f in range(nf)] + \
             [f"flags_{f}_valid" for f in range(nf)] + ["outs_ready"]

    def conj(terms):
        return " & ".join(terms) if terms else "TRUE"

    def disj(terms):
        return " | ".join(terms) if terms else "FALSE"

    def decision(p, tv):
        """The candidates' decision over one view (`{p}lt_f`, `{p}lf_f`,
        `{p}car_t`, `{p}emp_t`; tv(t) token t's payload in the view)."""
        out = []
        for k, c in enumerate(cands):
            en = [f"{p}lt_{f}" for f in c["flags"]] + [f"{p}lf_{f}" for f in c["unless"]]
            rf = [f"{p}lf_{f}" for f in c["flags"]] + [f"{p}lt_{f}" for f in c["unless"]]
            if c["token"] is not None:
                en.append(f"{p}car_{c['token']}")
                rf.append(f"{p}emp_{c['token']}")
            out.append(f"{p}en_{k} := {conj(en)};")
            out.append(f"{p}rf_{k} := {disj(rf)};")
            out.append(f"{p}win_{k} := {conj([f'{p}en_{k}'] + [f'{p}rf_{j}' for j in c['after']])};")
        out.append(f"{p}any_win := {disj([f'{p}win_{k}' for k in range(len(cands))])};")
        out.append(f"{p}all_ref := {conj([f'{p}rf_{k}' for k in range(len(cands))])};")
        out.append(f"{p}pay := case")
        for k, c in enumerate(cands):
            value = tv(c["token"]) if c["token"] is not None else data_type.format_constant(c["payload"])
            out.append(f"  {p}win_{k} : {value};")
        out.append(f"  TRUE : {zero};")
        out.append("esac;")
        return out

    d = []
    for i in range(n):
        d.append(f"arr_{i} := seen_{i} | {iname(i)}_valid;")
    for i in range(n):
        others = [f"arr_{j}" for j in range(n) if j != i]
        d.append(f"others_in_{i} := {conj(others)};")
    d.append(f"closing := {conj([f'arr_{i}' for i in range(n)])};")
    for t in range(nt):
        d.append(f"tv_{t} := seen_{t} ? tval_{t} : tokens_{t};")
        d.append(f"car_{t} := arr_{t} & ({nonzero(f'tv_{t}')});")
        d.append(f"emp_{t} := arr_{t} & !({nonzero(f'tv_{t}')});")
    for f in range(nf):
        i = nt + f
        d.append(f"fv_{f} := seen_{i} ? fval_{f} : flags_{f};")
        d.append(f"lt_{f} := arr_{i} & fv_{f};")
        d.append(f"lf_{f} := arr_{i} & !fv_{f};")
    d += decision("", lambda t: f"tv_{t}")
    d.append("valid_i := (has_win | any_win | all_ref) & !emitted;")
    d.append("fire := valid_i & outs_ready;")
    d.append("done := closing & (emitted | fire);")
    for i in range(n):
        d.append(f"done_wo_{i} := others_in_{i} & (emitted | outs_ready);")
        d.append(f"again_{i} := {iname(i)}_valid & seen_{i} & done_wo_{i};")
        d.append(f"e_arr_{i} := {iname(i)}_valid & seen_{i} & others_in_{i} & emitted;")
    for t in range(nt):
        d.append(f"e_car_{t} := e_arr_{t} & ({nonzero(f'tokens_{t}')});")
        d.append(f"e_emp_{t} := e_arr_{t} & !({nonzero(f'tokens_{t}')});")
    for f in range(nf):
        i = nt + f
        d.append(f"e_lt_{f} := e_arr_{i} & flags_{f};")
        d.append(f"e_lf_{f} := e_arr_{i} & !flags_{f};")
    d += decision("e_", lambda t: f"tokens_{t}")
    d.append("early := emitted & closing & (e_any_win | e_all_ref);")

    var = [f"seen_{i} : boolean;" for i in range(n)]
    var += [f"tval_{t} : {data_type};" for t in range(nt)]
    var += [f"fval_{f} : boolean;" for f in range(nf)]
    var += [f"winner : {data_type};", "has_win : boolean;", "emitted : boolean;"]

    a = []
    for i in range(n):
        a.append(f"init(seen_{i}) := FALSE;")
        a.append(f"next(seen_{i}) := done ? again_{i} : arr_{i};")
    for t in range(nt):
        a.append(f"init(tval_{t}) := {zero};")
        a.append(f"next(tval_{t}) := (done ? again_{t} : (tokens_{t}_valid & !seen_{t})) ? tokens_{t} : tval_{t};")
    for f in range(nf):
        i = nt + f
        a.append(f"init(fval_{f}) := FALSE;")
        a.append(f"next(fval_{f}) := (done ? again_{i} : (flags_{f}_valid & !seen_{i})) ? flags_{f} : fval_{f};")
    a.append("init(has_win) := FALSE;")
    a.append("next(has_win) := done ? (emitted & e_any_win) : (has_win | any_win);")
    a.append(f"init(winner) := {zero};")
    a.append("next(winner) := done ? (emitted ? e_pay : winner) : ((!has_win & any_win) ? pay : winner);")
    a.append("init(emitted) := FALSE;")
    a.append("next(emitted) := done ? (emitted & early & outs_ready) : (emitted | fire);")

    readies = [f"{iname(i)}_ready := !seen_{i} | done_wo_{i};" for i in range(n)]
    nl = "\n  "
    return f"""
-- candidates: {encoding}
MODULE {name}({", ".join(params)})
  VAR
  {nl.join(var)}

  DEFINE
  -- An input that has not given this round's token is always ready, so a
  -- valid one is taken (arr: arrived, now or before), with its value from
  -- the input now, from its register once seen. A candidate wins once
  -- enabled with every candidate of its `after` refused; the round answers
  -- the lowest-index winner, or zero once every candidate is refused.
  {nl.join(d)}

  ASSIGN
  {nl.join(a)}

  -- output
  DEFINE
  {nl.join(readies)}
  outs_valid := valid_i | early;
  outs := emitted ? e_pay : (has_win ? winner : pay);
"""
