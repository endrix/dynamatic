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
    """A whole racing decision in one unit (`handshake.race`): the VHDL
    generator's twin (tools/unit-generators/vhdl/generators/handshake/
    race.py), register for register. Candidates over flags and tokens; the
    lowest-index winner -- enabled, every candidate of its `after` refused --
    the first cycle one wins, zero the first cycle every candidate is refused;
    one token an input a round, taken on arrival; one answer a round. An input
    that gave its token is ready again the cycle every other input has
    arrived with the answer taken or being taken (never reading its own
    valid), and a next round its tokens decide is answered then when the
    output is free (`e_`). The output's valid reads no ready.
    """
    nt = params["size_tokens"]
    nf = params["size_flags"]
    w = params["bitwidth"]
    if w == 0:
        raise ValueError(
            "handshake.race has no dataless form: the payload is the answer, "
            "and zero is 'nothing selected'.")
    if params.get("extra_signals", None):
        raise ValueError(
            "handshake.race holds payloads alone; a channel with extra "
            "signals would lose them (the op's verifier refuses it)")
    if nt + nf == 0:
        raise ValueError("handshake.race has no input")
    cands = parse_candidates(params["candidates"], nt, nf, w)
    return _generate_race(name, nt, nf, w, cands, params["candidates"])


def _generate_race(name, nt, nf, w, cands, encoding):
    n = nt + nf
    c = len(cands)

    def conj(terms):
        return " & ".join(terms) if terms else "1'b1"

    def disj(terms):
        return " | ".join(terms) if terms else "1'b0"

    def decision(p, tv):
        out = []
        for k, cand in enumerate(cands):
            en = [f"{p}lt[{f}]" for f in cand["flags"]] + [f"{p}lf[{f}]" for f in cand["unless"]]
            rf = [f"{p}lf[{f}]" for f in cand["flags"]] + [f"{p}lt[{f}]" for f in cand["unless"]]
            if cand["token"] is not None:
                en.append(f"{p}car[{cand['token']}]")
                rf.append(f"{p}emp[{cand['token']}]")
            out.append(f"assign {p}en[{k}] = {conj(en)};")
            out.append(f"assign {p}rf[{k}] = {disj(rf)};")
            out.append(f"assign {p}win[{k}] = {conj([f'{p}en[{k}]'] + [f'{p}rf[{j}]' for j in cand['after']])};")
        out.append(f"assign {p}any_win = |{p}win;")
        out.append(f"assign {p}all_ref = &{p}rf;")
        # the lowest-index winner: a winner with no winner before it
        out.append(f"assign {p}sel[0] = {p}win[0];")
        for k in range(1, c):
            out.append(f"assign {p}sel[{k}] = {p}win[{k}] & ~(|{p}win[{k} - 1 : 0]);")
        pays = []
        for k, cand in enumerate(cands):
            value = tv(cand["token"]) if cand["token"] is not None else f"{w}'d{cand['payload']}"
            pays.append(f"({{{w}{{{p}sel[{k}]}}}} & {value})")
        out.append(f"assign {p}pay = " + "\n    | ".join(pays) + ";")
        return out

    ports = []
    if nt:
        ports += [f"  input  [{nt} * {w} - 1 : 0] tokens,",
                  f"  input  [{nt} - 1 : 0] tokens_valid,",
                  f"  output [{nt} - 1 : 0] tokens_ready,"]
    if nf:
        ports += [f"  input  [{nf} - 1 : 0] flags,",
                  f"  input  [{nf} - 1 : 0] flags_valid,",
                  f"  output [{nf} - 1 : 0] flags_ready,"]

    body = []
    iv = []
    if nf:
        iv.append("flags_valid")
    if nt:
        iv.append("tokens_valid")
    body.append(f"wire [{n} - 1 : 0] iv = {{{', '.join(iv)}}};")
    body.append(f"wire [{n} - 1 : 0] arr = seen | iv;")
    body.append(f"wire [{n} - 1 : 0] others_in;")
    for i in range(n):
        others = [f"arr[{j}]" for j in range(n) if j != i]
        body.append(f"assign others_in[{i}] = {conj(others)};")
    body.append("wire closing = &arr;")
    for p in ("", "e_"):
        if nt:
            body.append(f"wire [{nt} - 1 : 0] {p}car, {p}emp;")
        if nf:
            body.append(f"wire [{nf} - 1 : 0] {p}lt, {p}lf;")
        body.append(f"wire [{c} - 1 : 0] {p}en, {p}rf, {p}win, {p}sel;")
        body.append(f"wire {p}any_win, {p}all_ref;")
        body.append(f"wire [{w} - 1 : 0] {p}pay;")
    for t in range(nt):
        body.append(f"wire [{w} - 1 : 0] tv{t} = seen[{t}] ? tval[{t} * {w} +: {w}] : tokens[{t} * {w} +: {w}];")
        body.append(f"assign car[{t}] = arr[{t}] & (tv{t} != {w}'d0);")
        body.append(f"assign emp[{t}] = arr[{t}] & (tv{t} == {w}'d0);")
    for f in range(nf):
        i = nt + f
        body.append(f"wire fv{f} = seen[{i}] ? fval[{f}] : flags[{f}];")
        body.append(f"assign lt[{f}] = arr[{i}] & fv{f};")
        body.append(f"assign lf[{f}] = arr[{i}] & ~fv{f};")
    body += decision("", lambda t: f"tv{t}")
    body.append(f"wire [{n} - 1 : 0] e_arr = iv & seen & others_in & {{{n}{{emitted}}}};")
    for t in range(nt):
        body.append(f"assign e_car[{t}] = e_arr[{t}] & (tokens[{t} * {w} +: {w}] != {w}'d0);")
        body.append(f"assign e_emp[{t}] = e_arr[{t}] & (tokens[{t} * {w} +: {w}] == {w}'d0);")
    for f in range(nf):
        i = nt + f
        body.append(f"assign e_lt[{f}] = e_arr[{i}] & flags[{f}];")
        body.append(f"assign e_lf[{f}] = e_arr[{i}] & ~flags[{f}];")
    body += decision("e_", lambda t: f"tokens[{t} * {w} +: {w}]")

    regs = [f"reg [{n} - 1 : 0] seen;", f"reg [{w} - 1 : 0] winner;",
            "reg has_win;", "reg emitted;"]
    if nt:
        regs.append(f"reg [{nt} * {w} - 1 : 0] tval;")
    if nf:
        regs.append(f"reg [{nf} - 1 : 0] fval;")
    resets = [f"seen    <= {{{n}{{1'b0}}}};", f"winner  <= {{{w}{{1'b0}}}};",
              "has_win <= 1'b0;", "emitted <= 1'b0;"]
    if nt:
        resets.append(f"tval    <= {{{nt * w}{{1'b0}}}};")
    if nf:
        resets.append(f"fval    <= {{{nf}{{1'b0}}}};")
    take_again = [f"if (again[{t}]) tval[{t} * {w} +: {w}] <= tokens[{t} * {w} +: {w}];" for t in range(nt)] + \
                 [f"if (again[{nt + f}]) fval[{f}] <= flags[{f}];" for f in range(nf)]
    take_now = [f"if (iv[{t}] && !seen[{t}]) tval[{t} * {w} +: {w}] <= tokens[{t} * {w} +: {w}];" for t in range(nt)] + \
               [f"if (iv[{nt + f}] && !seen[{nt + f}]) fval[{f}] <= flags[{f}];" for f in range(nf)]
    readies = []
    if nt:
        readies.append(f"assign tokens_ready = ~seen[{nt} - 1 : 0] | done_wo[{nt} - 1 : 0];")
    if nf:
        readies.append(f"assign flags_ready  = ~seen[{n} - 1 : {nt}] | done_wo[{n} - 1 : {nt}];")

    nl = "\n  "
    return f"""

// Module of race
// candidates: {encoding}

module {name}(
  input  clk,
  input  rst,
  // Input channels: the tokens, then the flags
{chr(10).join(ports)}
  // Output channel
  output [{w} - 1 : 0] outs,
  output outs_valid,
  input  outs_ready
);
  // Round state: which inputs gave their token, the value each gave, the
  // answer held while the sink stalls, whether it has been taken.
  {nl.join(regs)}

  // An input that has not given this round's token is always ready, so a
  // valid one is taken (`arr`), with its value from the input now, from its
  // register once seen. A candidate wins once enabled with every candidate
  // of its `after` refused; the round answers the lowest-index winner, or
  // zero once every candidate is refused.
  {nl.join(body)}

  wire valid_i = (has_win | any_win | all_ref) & ~emitted;
  wire fire    = valid_i & outs_ready;
  wire done    = closing & (emitted | fire);
  // An input that gave its token is ready again the cycle the round
  // completes, read from the OTHER inputs alone; what it gives then is the
  // next round's, answered now when it decides and the output is free.
  wire [{n} - 1 : 0] done_wo = others_in & {{{n}{{emitted | outs_ready}}}};
  wire [{n} - 1 : 0] again   = iv & seen & done_wo;
  wire early = emitted & closing & (e_any_win | e_all_ref);
  {nl.join(readies)}

  assign outs_valid = valid_i | early;
  assign outs       = emitted ? e_pay : (has_win ? winner : pay);

  always @(posedge clk) begin
    if (rst) begin
      {(nl + "    ").join(resets)}
    end else if (done) begin
      // The next round, from what it gave in this cycle.
      seen <= again;
      {(nl + "    ").join(take_again)}
      if (emitted) begin
        has_win <= e_any_win;
        winner  <= e_pay;
        emitted <= early & outs_ready;
      end else begin
        has_win <= 1'b0;
        emitted <= 1'b0;
      end
    end else begin
      seen <= arr;
      {(nl + "    ").join(take_now)}
      // An answer found while the sink is stalled is held.
      if (!has_win && any_win) begin
        has_win <= 1'b1;
        winner  <= pay;
      end
      if (fire)
        emitted <= 1'b1;
    end
  end
endmodule
"""
