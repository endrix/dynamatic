def parse_candidates(text, size_tokens, size_flags, bitwidth):
    """The candidates of a race from its CANDIDATES parameter
    (RaceOp::getCandidatesEncoding): one after the other, separated by '/',
    each a ':'-separated list of fields -- `p<payload>` or `t<token>` first,
    then `f<flags>`, `u<unless>`, `a<after>`, each a comma-separated list.

    Returns a list of dicts with keys payload (int or None), token (int or
    None), flags, unless, after (lists of int). Checks what the generators
    rely on; the op's verifier checks the rest (distinct payloads, the order
    transitively closed and acyclic).
    """
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
    """A whole racing decision in one unit (`handshake.race`).

    Candidates -- a payload over flags, or a token input -- each answered the
    cycle the inputs that have arrived determine it: a candidate WINS when
    its flags arrived true, its `unless` flags false and its token non-zero
    (ENABLED), and every candidate of its `after` list is REFUSED (one of its
    flags arrived false, an `unless` flag true, its token zero). The lowest
    index among the winners is emitted the first cycle one wins; zero, the
    reserved "nothing selected", the first cycle every candidate is refused.
    Each input gives one token a round, taken the cycle it arrives; the unit
    emits one answer a round.

    The registers are `first`'s (first.py), plus the value each input
    arrived with: `seen` a bit an input, `winner`/`has_win` the answer held
    while the sink stalls, `emitted`, and `tval`/`fval`, a token's payload
    and a flag's bit, since a candidate may be decided cycles after one of
    its inputs arrived. The decision itself is combinational in the inputs
    and those registers (latency zero): an input's arrival (`arr`, seen or
    valid now) and value, the literals, the candidates' AND and OR terms,
    the predecessors' refusals, a priority among the winners by index and
    the payload multiplexer -- a depth logarithmic in the flags, the
    predecessors and the candidates, where a nest of `first` and `priority`
    units is as deep as the nest.

    THE ROUND CLOSES IN THE CYCLE IT COMPLETES, as `first`'s: an input that
    gave its token is ready again the cycle every other input has arrived
    with the answer taken or being taken (read from the OTHER inputs' valid
    and the output's ready, never its own valid), and gives the next round's
    then. With the answer out earlier the output is free, and a next round
    those tokens decide -- a winner, or every candidate refused -- is
    answered in that same cycle (the `early` view: the same decision over
    the next round's tokens alone). The output's valid reads no ready.
    """
    size_tokens = params["size_tokens"]
    size_flags = params["size_flags"]
    bitwidth = params["bitwidth"]
    extra_signals = params.get("extra_signals", None)

    if bitwidth == 0:
        raise ValueError(
            "handshake.race has no dataless form: the payload is the answer, "
            "and zero is 'nothing selected'.")
    if extra_signals:
        raise ValueError(
            "handshake.race holds payloads alone; a channel with extra "
            "signals would lose them (the op's verifier refuses it)")
    if size_tokens + size_flags == 0:
        raise ValueError("handshake.race has no input")
    cands = parse_candidates(params["candidates"], size_tokens, size_flags,
                             bitwidth)
    return _generate_race(name, size_tokens, size_flags, bitwidth, cands,
                          params["candidates"])


def _bits(value, width):
    """A VHDL bit-string literal of `value` at `width` bits."""
    return '"' + format(value, f"0{width}b") + '"'


def _terms(terms, op, empty):
    return f" {op} ".join(terms) if terms else empty


def _decision(prefix, cands, size_tokens, bitwidth, tval):
    """The candidates' decision over one view of the inputs, as concurrent
    assignments: `{prefix}en`, `{prefix}rf`, `{prefix}win` a bit a candidate,
    `{prefix}any_win`, `{prefix}all_ref` and `{prefix}pay`, the lowest-index
    winner's payload. The view's literals are `{prefix}lt`/`{prefix}lf` (a
    flag arrived true / false) and `{prefix}car`/`{prefix}emp` (a token
    arrived non-zero / zero); `tval(t)` is token t's payload in the view."""
    n = len(cands)
    lines = []
    for k, c in enumerate(cands):
        en = [f"{prefix}lt({f})" for f in c["flags"]] + \
             [f"{prefix}lf({f})" for f in c["unless"]]
        rf = [f"{prefix}lf({f})" for f in c["flags"]] + \
             [f"{prefix}lt({f})" for f in c["unless"]]
        if c["token"] is not None:
            en.append(f"{prefix}car({c['token']})")
            rf.append(f"{prefix}emp({c['token']})")
        lines.append(f"{prefix}en({k}) <= {_terms(en, 'and', chr(39) + '1' + chr(39))};")
        lines.append(f"{prefix}rf({k}) <= {_terms(rf, 'or', chr(39) + '0' + chr(39))};")
        win = [f"{prefix}en({k})"] + [f"{prefix}rf({j})" for j in c["after"]]
        lines.append(f"{prefix}win({k}) <= {_terms(win, 'and', '')};")
    lines.append(f"{prefix}any_win <= '1' when {prefix}win /= (0 to {n} - 1 => '0') else '0';")
    lines.append(f"{prefix}all_ref <= '1' when {prefix}rf = (0 to {n} - 1 => '1') else '0';")
    # the lowest-index winner: a winner with no winner before it
    lines.append(f"{prefix}sel(0) <= {prefix}win(0);")
    if n > 1:
        lines.append(f"{prefix}before(0) <= {prefix}win(0);")
    for k in range(1, n):
        lines.append(f"{prefix}sel({k}) <= {prefix}win({k}) and not {prefix}before({k - 1});")
        if k < n - 1:
            lines.append(f"{prefix}before({k}) <= {prefix}before({k - 1}) or {prefix}win({k});")
    pays = []
    for k, c in enumerate(cands):
        value = tval(c["token"]) if c["token"] is not None else _bits(c["payload"], bitwidth)
        pays.append(f"((({bitwidth} - 1) downto 0 => {prefix}sel({k})) and {value})")
    lines.append(f"{prefix}pay <= " + "\n           or ".join(pays) + ";")
    return "\n".join(lines)


def _generate_race(name, nt, nf, w, cands, encoding):
    n = nt + nf
    c = len(cands)

    ports = []
    if nt:
        ports.append(f"""    tokens       : in  data_array({nt} - 1 downto 0)({w} - 1 downto 0);
    tokens_valid : in  std_logic_vector({nt} - 1 downto 0);
    tokens_ready : out std_logic_vector({nt} - 1 downto 0);""")
    if nf:
        ports.append(f"""    flags       : in  data_array({nf} - 1 downto 0)(0 downto 0);
    flags_valid : in  std_logic_vector({nf} - 1 downto 0);
    flags_ready : out std_logic_vector({nf} - 1 downto 0);""")
    entity = f"""
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.types.all;

-- Entity of race
-- candidates: {encoding}
entity {name} is
  port (
    clk : in std_logic;
    rst : in std_logic;
    -- input channels: the tokens, then the flags
{chr(10).join(ports)}
    -- output channel
    outs       : out std_logic_vector({w} - 1 downto 0);
    outs_valid : out std_logic;
    outs_ready : in  std_logic
  );
end entity;
"""

    # Inputs are numbered tokens first, then flags, in `seen` and friends.
    decl = []
    if nt:
        decl.append(f"  signal tval : data_array({nt} - 1 downto 0)({w} - 1 downto 0);")
        for t in range(nt):
            decl.append(f"  signal tv{t} : std_logic_vector({w} - 1 downto 0);")
        decl.append(f"  signal car, emp, e_car, e_emp : std_logic_vector({nt} - 1 downto 0);")
    if nf:
        decl.append(f"  signal fval, fv, lt, lf, e_lt, e_lf : std_logic_vector({nf} - 1 downto 0);")
    for p in ("", "e_"):
        decl.append(f"  signal {p}en, {p}rf, {p}win, {p}sel : std_logic_vector(0 to {c} - 1);")
        if c > 1:
            decl.append(f"  signal {p}before : std_logic_vector(0 to {c} - 2);")
        decl.append(f"  signal {p}any_win, {p}all_ref : std_logic;")
        decl.append(f"  signal {p}pay : std_logic_vector({w} - 1 downto 0);")

    body = []
    # the inputs as one vector: valid, and arrival this round
    iv = []
    if nf:
        iv.append("flags_valid")
    if nt:
        iv.append("tokens_valid")
    body.append(f"iv <= {' & '.join(iv)};")
    body.append("arr <= seen or iv;")
    # all the others arrived, for each input: a prefix and a suffix AND
    body.append("pre(0) <= '1';")
    for i in range(1, n):
        body.append(f"pre({i}) <= pre({i - 1}) and arr({i - 1});")
    body.append(f"suf({n - 1}) <= '1';")
    for i in range(n - 2, -1, -1):
        body.append(f"suf({i}) <= suf({i + 1}) and arr({i + 1});")
    body.append("others_in <= pre and suf;")
    body.append(f"closing <= pre({n - 1}) and arr({n - 1});")
    # the round's view: what arrived, with the value it arrived with
    for t in range(nt):
        body.append(f"tv{t} <= tval({t}) when seen({t}) = '1' else tokens({t});")
        body.append(f"car({t}) <= arr({t}) when unsigned(tv{t}) /= 0 else '0';")
        body.append(f"emp({t}) <= arr({t}) when unsigned(tv{t}) = 0 else '0';")
    for f in range(nf):
        i = nt + f
        body.append(f"fv({f}) <= fval({f}) when seen({i}) = '1' else flags({f})(0);")
        body.append(f"lt({f}) <= arr({i}) and fv({f});")
        body.append(f"lf({f}) <= arr({i}) and not fv({f});")
    body.append(_decision("", cands, nt, w, lambda t: f"tv{t}"))
    # the next round's view, in this round's completing cycle with the answer
    # out: the inputs that gave this round's token and give the next one's
    body.append("e_arr <= iv and seen and others_in and (others_in'range => emitted);")
    for t in range(nt):
        body.append(f"e_car({t}) <= e_arr({t}) when unsigned(tokens({t})) /= 0 else '0';")
        body.append(f"e_emp({t}) <= e_arr({t}) when unsigned(tokens({t})) = 0 else '0';")
    for f in range(nf):
        i = nt + f
        body.append(f"e_lt({f}) <= e_arr({i}) and flags({f})(0);")
        body.append(f"e_lf({f}) <= e_arr({i}) and not flags({f})(0);")
    body.append(_decision("e_", cands, nt, w, lambda t: f"tokens({t})"))

    body_text = "\n  ".join("\n".join(body).split("\n"))
    tregs_reset = "\n        tval    <= (others => (others => '0'));" if nt else ""
    fregs_reset = "\n        fval    <= (others => '0');" if nf else ""
    again_take = "".join(
        f"\n        if again({t}) = '1' then\n          tval({t}) <= tokens({t});\n        end if;"
        for t in range(nt)) + "".join(
        f"\n        if again({nt + f}) = '1' then\n          fval({f}) <= flags({f})(0);\n        end if;"
        for f in range(nf))
    taken_take = "".join(
        f"\n        if iv({t}) = '1' and seen({t}) = '0' then\n          tval({t}) <= tokens({t});\n        end if;"
        for t in range(nt)) + "".join(
        f"\n        if iv({nt + f}) = '1' and seen({nt + f}) = '0' then\n          fval({f}) <= flags({f})(0);\n        end if;"
        for f in range(nf))
    readies = []
    if nt:
        readies.append(f"tokens_ready <= not seen({nt} - 1 downto 0) or done_wo({nt} - 1 downto 0);")
    if nf:
        readies.append(f"flags_ready  <= not seen({n} - 1 downto {nt}) or done_wo({n} - 1 downto {nt});")

    architecture = f"""
-- Architecture of race
architecture arch of {name} is
  -- Round state: which inputs gave their token, the value each gave, the
  -- answer held while the sink stalls, whether it has been taken.
  signal seen    : std_logic_vector({n} - 1 downto 0);
  signal winner  : std_logic_vector({w} - 1 downto 0);
  signal has_win : std_logic;
  signal emitted : std_logic;

  signal iv, arr, pre, suf, others_in : std_logic_vector({n} - 1 downto 0);
  signal done_wo, again, e_arr        : std_logic_vector({n} - 1 downto 0);
  signal closing, valid_i, fire, done : std_logic;
  signal early                        : std_logic;
{chr(10).join(decl)}
begin
  -- An input that has not given this round's token is always ready, so a
  -- valid one is taken (`arr`: arrived, now or before) -- with its value
  -- from the input now, from its register once seen.
  {body_text}

  -- Emit the instant a candidate wins, or zero the instant every candidate
  -- is refused. Combinational in valid and data: latency zero. Once every
  -- input is in, one of the two holds.
  valid_i <= (has_win or any_win or all_ref) and not emitted;
  fire    <= valid_i and outs_ready;
  -- The round is over once every input has given its token AND the answer
  -- has been taken, in either order.
  done    <= closing and (emitted or fire);

  -- An input that gave its token is ready again the cycle the round
  -- completes, read from the OTHER inputs alone (its own token is in, so
  -- the round is closing when they are, and then answers): never its own
  -- valid, and the output's valid never reads its ready. What it gives then
  -- is the next round's; with the answer out earlier, the next round those
  -- tokens decide is answered now.
  done_wo <= others_in and ({n} - 1 downto 0 => (emitted or outs_ready));
  again   <= iv and seen and done_wo;
  early   <= emitted and closing and (e_any_win or e_all_ref);
  {(chr(10) + "  ").join(readies)}

  outs_valid <= valid_i or early;
  outs       <= e_pay when emitted = '1' else
                winner when has_win = '1' else
                pay;

  process (clk) is
  begin
    if rising_edge(clk) then
      if rst = '1' then
        seen    <= (others => '0');
        winner  <= (others => '0');
        has_win <= '0';
        emitted <= '0';{tregs_reset}{fregs_reset}
      elsif done = '1' then
        -- The next round, from what it gave in this cycle: its answer
        -- offered now if those tokens decide it, held if not taken; else
        -- decided from the registers from the next cycle on.
        seen <= again;{again_take}
        if emitted = '1' then
          has_win <= e_any_win;
          winner  <= e_pay;
          emitted <= early and outs_ready;
        else
          has_win <= '0';
          emitted <= '0';
        end if;
      else
        seen <= arr;{taken_take}
        -- An answer found while the sink is stalled is held rather than
        -- re-decided: a winner of lower index may come later.
        if has_win = '0' and any_win = '1' then
          has_win <= '1';
          winner  <= pay;
        end if;
        -- Having answered, stay quiet while absorbing the late inputs.
        if fire = '1' then
          emitted <= '1';
        end if;
      end if;
    end if;
  end process;
end architecture;
"""
    return entity + architecture
