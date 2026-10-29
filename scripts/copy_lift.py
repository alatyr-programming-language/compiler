#!/usr/bin/env python3
"""copy_lift.py — which private emitter copies can be deleted TODAY, and what blocks the rest.

docs/ir.md §2.4 lists the decisions the compiler makes four times; §7.2 says each copy goes "when the
census allows". The census never said WHICH ones allow it now, and a first attempt at answering that
question by hand got it wrong in the permissive direction: it checked that a family's bodies were
byte-identical and that it read no `*_SUB_*` backend GLOBAL, and called four families liftable. Three of
them call a backend-LOCAL function (`*_local_arrty_span`, `*_operand_unsigned`), so lifting them would
have silently changed the callee — a refactor that is not one, caught only because the bodies were read
after the verdict was written.

So the test is the transitive closure, not one property:

  LIFTABLE(family) = all three copies exist
                     AND bodies are identical after prefix normalisation
                     AND no backend global is read anywhere in the closure
                     AND no backend-LOCAL function is called anywhere in the closure (outside the family)

The closure matters because a copy that calls `a64_local_arrty_span` is not one decision but two, and
the second one stays in aarch64 — the "shared" copy would then answer from a different place per target,
which is the bug class this whole exercise removes rather than fixes.

usage:
  scripts/copy_lift.py [--root DIR] [--verbose] [family ...]   # families default to §2.4's list
  scripts/copy_lift.py --self-test
Exit code: 0 if the run completed (a BLOCKED family is a finding, not an error); 2 if it could not
parse the tree — an instrument that reads nothing reports nothing, and silence is not a pass.
"""
import io, os, re, sys, difflib

BACKENDS = {'aarch64.al': 'a64', 'riscv64.al': 'rv', 'wat.al': 'wat'}
## Every emitter, including x86_64. `BACKENDS` deliberately excludes `lower.al` because a family is
## detected through the twins' `_a64_`/`_rv_`/`_wat_` prefixes and x86 spells its helpers differently — but
## that is a reason it cannot be *lifted* by the same move, not a reason it cannot hold a private copy. For
## "is any copy still private" x86_64 counts, so the two sets are deliberately different.
EMITTERS = ('lower.al', 'aarch64.al', 'riscv64.al', 'wat.al')
# Families from docs/ir.md §2.4 — the decisions named there, prefix-normalised.
FAMILIES = [
    'operand_narrow', 'local_narrow',
    'operand_signed', 'operand_signed_dep', 'bin_init_signed', 'shift_call_signed',
    'local_ann_signed', 'local_rhs',
    'operand_unsigned', 'cmp_unsigned', 'local_ann_unsigned', 'index_elem_unsigned',
    'unchecked_init_unsigned', 'hole_index_signed', 'local_arrty_span', 'slice_param_elem_span',
    # `slice_ann_elem_span` is x86_64's superset copy of the shared span scan, renamed off
    # `slice_param_elem_span` by #1077 so the bare name stopped meaning two things. It has ONE
    # definition, so it is not a copy family and the census reports nothing about it — which is
    # precisely why it is listed by name here: the family count fell 14 -> 13 when the collision was
    # fixed, and a falling count that nobody can explain is how a copy gets forgotten. docs/ir.md
    # §2.4 and the note at `lower_ctx.al:512` carry what this instrument cannot see.
    'slice_ann_elem_span',
    'ann_arr_words', 'local_ann_span', 'slice_elem_span', 'tyname_words',
    # `emit_narrow` / `emit_narrow_trap` are NOT families and are out of the list on purpose: the third
    # copy does not exist because there is no third decision to copy — wasm spells the same narrowing as
    # `wat_narrow_pre` / `wat_narrow_post`, and `docs/ir.md` §2.4 says the width is "per-target ISA
    # spelling, not a duplicated decision at all". Left in the list they would report blocked forever and
    # the census could never reach zero, which is the wrong question (§2.4, and the note at :323).
    # `local_scan` STAYS: there the twins really do share one decision and wasm's differs in behaviour
    # (a shadowed name reuses the slot on aarch64/riscv64, not on wasm) — #1066.
    'local_scan', 'inst_add',
    'comp_cond_fold', 'comp_range_bound', 'emit_{p}_match_arms', 'try_success_disc',
    # hoisted by #1045 for two backends only — kept in the list so the census sees the third, not so it
    # can be forgotten: see §2.4, a family is closed when the LAST private copy is gone.
    'field_is_scalar',
]
KEYWORDS = {'if', 'else', 'while', 'for', 'match', 'loop', 'return', 'break', 'continue',
            'and', 'or', 'not', 'in', 'fn', 'mut', 'pub', 'unchecked', 'bitcast', 'deref',
            'sizeof', 'alignof', 'typeinfo', 'struct', 'enum', 'union', 'some', 'none'}


def strip_noise(line):
    """Drop the `##` comment and the string literals: neither is code."""
    i = line.find('##')
    if i >= 0:
        line = line[:i]
    return re.sub(r'"(?:[^"\\]|\\.)*"', '""', line)


def parse(path):
    """-> {name: {'file':basename,'start':line,'end':line,'body':text}} for `name := fn` defs."""
    raw = io.open(path, encoding='utf-8', errors='replace').read().split('\n')
    out = {}
    for i, ln in enumerate(raw):
        m = re.match(r'\s*(?:pub\s+)?([a-z_][a-z0-9_]*)\s*:=\s*fn\b', ln)
        if not m:
            continue
        depth = 0
        for j in range(i, len(raw)):
            depth += strip_noise(raw[j]).count('{') - strip_noise(raw[j]).count('}')
            ## `j >= i`, not `j > i`: a ONE-LINE definition (`f := fn(...) -> T { expr }`) returns
            ## depth to 0 on its own line, and requiring a later line made the scan run past it and
            ## swallow every following definition until some accidental depth-0 — measured on main
            ## 99476a5, `lower_ctx.al:33 decl_at` came back with `pub decl_get := fn(...)` inside
            ## its body. Bodies that are not the body are how a duplicate detector invents duplicates
            ## and misses real ones; the span is the whole of what is compared.
            if depth == 0 and j >= i:
                out[m.group(1)] = {'file': os.path.basename(path), 'start': i + 1,
                                   'end': j + 1, 'body': '\n'.join(raw[i:j + 1])}
                break
    return out


def callees(body):
    """Function identifiers called in `body`: lowercase, not `::`-qualified, not a keyword."""
    out = set()
    for ln in body.split('\n'):
        s = strip_noise(ln)
        for m in re.finditer(r'(?<![:\w.])([a-z_][a-z0-9_]*)\s*\(', s):
            n = m.group(1)
            if n not in KEYWORDS:
                out.add(n)
    return out


def globals_read(body):
    """Backend globals touched: `A64_*` / `RV_*` / `WAT_*`."""
    return set(re.findall(r'\b(?:A64|RV|WAT)_[A-Z0-9_]+\b', strip_noise(body)))


def load(root):
    defs, byfile = {}, {}
    for d in ('src', os.path.join('src', 'lower')):
        p = os.path.join(root, d)
        if not os.path.isdir(p):
            continue
        for f in sorted(os.listdir(p)):
            if not f.endswith('.al'):
                continue
            got = parse(os.path.join(p, f))
            for k, v in got.items():
                defs.setdefault(k, []).append(v)
            byfile[os.path.basename(p) + '/' + f] = got
    return defs, byfile


def strip_comments(body):
    """Drop `##` line comments and indentation — neither reaches the emitted output.

    String literals are NOT touched, deliberately: `strip_noise` above blanks them out, and that
    would be unsound here. Two backends whose bodies differ ONLY in a string they emit would look
    identical, and the whole point of this test is to refuse a hoist that would change bytes. A
    `##` inside a string is likewise not a comment, so the scan tracks quote state rather than
    cutting at the first `##` it sees.
    """
    out = []
    for line in body.splitlines():
        kept, i, instr = [], 0, False
        while i < len(line):
            ch = line[i]
            if instr:
                if ch == '\\':
                    i += 2
                    continue
                if ch == '"':
                    instr = False
            elif ch == '"':
                instr = True
            elif ch == '#' and line[i:i + 2] == '##':
                break
            kept.append(ch)
            i += 1
        if ''.join(kept).strip():
            out.append(''.join(kept).strip())
    return '\n'.join(out)


def diff_detail(norm):
    """Say WHAT differs, not just that it does.

    `bodies DIFFER between backends` was true and useless: it did not tell a lane whether the
    difference is a spelling (a register name, a comment, one extra guard) — which a hoist absorbs
    by keeping the shared decision and parameterising the rest — or a different DECISION, which
    needs a spec answer first. #1056 is exactly that case: `field_is_scalar` differs between wasm
    and the twins, and it took reading both bodies to see that wasm asks `not an aggregate` where
    the twins ask `== 1`, and that wasm's own comment calls the weaker question unsafe. No
    instrument said it, because none was asked to.

    So: compare every pair, report the CLOSEST one (where a hoist would start), how many lines
    apart they are, and the first few differing lines verbatim. A one-line difference reads as a
    spelling; a dozen scattered lines that change control flow reads as a decision.
    """
    names = sorted(norm)
    scored = []
    for i, a in enumerate(names):
        for b in names[i + 1:]:
            la = [l.strip() for l in norm[a].splitlines() if l.strip()]
            lb = [l.strip() for l in norm[b].splitlines() if l.strip()]
            only_a, only_b = [], []
            for line in difflib.unified_diff(la, lb, lineterm='', n=0):
                if line.startswith('---') or line.startswith('+++'):
                    continue
                if line.startswith('-'):
                    only_a.append(line[1:].strip())
                elif line.startswith('+'):
                    only_b.append(line[1:].strip())
            scored.append((len(only_a) + len(only_b), a, b, only_a, only_b))
    scored.sort(key=lambda t: (t[0], t[1], t[2]))
    scored = [s for s in scored if s[0] > 0]
    if not scored:
        # Every pair's code lines match, yet the raw bodies differ: the difference is in
        # whitespace or comments that `strip_comments` kept (a string literal, most likely — it is
        # deliberately not blanked out, because a string can reach the emitted output). Say so;
        # "0 lines apart" on its own reads as a contradiction.
        return 'bodies DIFFER in non-code text only (a string literal?); code lines match x3'
    n, a, b, only_a, only_b = scored[0]
    out = 'bodies DIFFER: closest pair %s/%s, %d line(s) apart' % (a, b, n)
    for l in only_a[:3]:
        out += ' | %s-only: %s' % (a, l[:90])
    for l in only_b[:3]:
        out += ' | %s-only: %s' % (b, l[:90])
    return out


def _norm_sig(body):
    """-> (params, ret) normalized, or (None, None) if the head does not parse."""
    m = re.match(r'\s*(?:pub\s+)?[a-z_][a-z0-9_]*\s*:=\s*fn\s*\((.*?)\)\s*(?:->\s*([^{]+))?\{',
                body, re.S)
    if not m:
        return None, None
    return (re.sub(r'\s+', ' ', m.group(1)).strip(),
            re.sub(r'\s+', ' ', m.group(2) or '').strip())


def _norm_body(name, body):
    """Body as a shape: comments gone, the function's OWN name replaced, backend callee prefixes
    stripped, whitespace collapsed. Two spellings of one decision collide here on purpose."""
    b = strip_comments(body)
    b = re.sub(r'\b%s\b' % re.escape(name), 'FN', b)
    b = re.sub(r'\b(?:a64|rv|wat|x86)_([a-z])', r'\1', b)
    return re.sub(r'\s+', ' ', b).strip()


def _code(name, body):
    """The executable text only: `pub` and statement separators normalized too.

    Why this is NOT the same as `_norm_body`. `_norm_body` keeps `pub` and keeps `;`, and that
    difference is the difference between a copy and NOT a copy: `decl_at` in lower.al differs from
    `pub decl_at` in lower_ctx.al by the keyword alone, and `decl_get` by a `;` alone — both are
    genuinely the same decision written twice. Meanwhile `streq` in lower.al was reported an exact
    copy of `driver.al:62` while the `pub` version in lower_ctx.al carries NO fast-reject that
    lower.al's has: `if a_n != b_n { return false }`. A detector that calls that 'exact' invites
    someone to delete the fast path and repoint 257 call sites at a different implementation — which
    is a behaviour change dressed as a refactor. So the shape match and the code match are reported
    apart, and only a CODE match may be deleted."""
    b = _norm_body(name, body)
    b = re.sub(r'^\s*pub\s+', '', b)
    b = b.replace(';', ' ')
    return re.sub(r'\s+', ' ', b).strip()


def classify_copies(root):
    """-> (exact, superset). EXACT: same signature, same executable code — deletable by repointing
    the call sites at the shared one. SUPERSET: same signature, the emitter's body does strictly more
    (or something different) — NOT deletable without a decision, and reported so the next agent does
    not 'lift' it and silently change behaviour."""
    defs, _ = load(root)
    shared = {}
    for sname, fns in defs.items():
        for d in fns:
            if d['file'] in EMITTERS:
                continue
            p, r = _norm_sig(d['body'])
            if p is None:
                continue
            shared.setdefault((p, r), []).append((d, _norm_body(sname, d['body']),
                                                  _code(sname, d['body'])))
    exact, sup = [], []
    for name, fns in sorted(defs.items()):
        for d in fns:
            if d['file'] not in EMITTERS:
                continue
            p, r = _norm_sig(d['body'])
            if p is None:
                continue
            nb, nc = _norm_body(name, d['body']), _code(name, d['body'])
            hit_shape = [s for s in shared.get((p, r), []) if nb == s[1]]
            if not hit_shape:
                continue
            sd, _, sc = shared[(p, r)][0]
            code_hits = [s for s in hit_shape if nc == s[2]]
            pub = [s for s in code_hits if 'pub ' in s[0]['body'].split('{')[0]]
            # Prefer the PUBLIC shared definition as the home to repoint at: a private one in another
            # module cannot be called cross-module, so naming it would send the next agent to a target
            # that does not compile.
            home = (pub or code_hits or [shared[(p, r)][0]])[0][0]
            rec = {'name': name, 'file': d['file'], 'line': d['start'],
                   'shared_file': home['file'], 'shared_line': home['start'],
                   'pub': bool(pub), 'mark': ''}
            if code_hits:
                exact.append(rec)
            else:
                rec['differs'] = ('emitter body does more or different code than %s:%s — NOT deletable '
                                  'by repointing' % (home['file'], home['start']))
                sup.append(rec)
    return exact, sup


def private_exact(root):
    """The deletable set: emitter functions whose EXECUTABLE code equals a shared function's, found
    by shape and not by the FAMILIES name list. Delegates to classify_copies() and keeps only EXACT
    code matches, so the gate never asks for a lift that would drop behaviour — see _code().

    Why shape and not names: `FAMILIES` is a list of names, so a private copy written under a fresh
    name is invisible to it — measured on main `99476a5`: pasting the shared span scan into `lower.al`
    under a new name left `--gate` at rc=0 with zero mentions. Criterion 2 says the private copies are
    GONE; a census that knows only the duplicates already listed does not hold that. Near-matches were
    measured too and are NOT refused: at a Jaccard floor of 0.6 over same-signature pairs the tree
    yields **1068** hits, which is noise — refusing them teaches the next agent to lower the floor or
    delete the check. Code equality is the line that can be held.

    An acknowledged copy carries `## copy-ok: #<issue> — <why this one cannot be shared yet>` on the
    line above its definition; the reason prints on every run, and a marker citing no issue is refused.
    """
    exact, _sup = classify_copies(root)
    for e in exact:
        path = os.path.join(root, 'src', e['file'])
        if not os.path.isfile(path):
            for cand in ('src/lower',):
                alt = os.path.join(root, cand, e['file'])
                if os.path.isfile(alt):
                    path = alt
                    break
        try:
            lines = io.open(path, encoding='utf-8', errors='replace').read().split('\n')
            for k in (e['line'] - 1, e['line'] - 2):
                if 0 <= k < len(lines) and 'copy-ok:' in lines[k]:
                    e['mark'] = lines[k].split('copy-ok:', 1)[1].strip()
                    break
        except OSError:
            pass
    return exact


def private_superset(root):
    """Same signature, different code: reported, never refused. These are the ones a naive 'lift it'
    would silently rewrite — `streq` in lower.al carries a length-first fast reject the shared one
    does not, so repointing its 257 call sites is a behaviour change, not a refactor."""
    _ex, sup = classify_copies(root)
    return sup


def classify(root, families):
    """-> (liftable[(fam,lines)], blocked{fam:[blockers]}, ok) — the verdicts, unprefixed by printing."""
    defs, _ = load(root)
    if not defs:
        return [], {}, False
    local = {n for n, ds in defs.items() if any(d['file'] in ('aarch64.al', 'riscv64.al', 'wat.al') for d in ds)}
    liftable, blocked = [], {}
    for fam in families:
        # a family is usually `a64_X/rv_X/wat_X`; some carry the prefix in the middle
        # (`emit_a64_match_arms`), spelled with a `{p}` template.
        tmpl = '{p}' in fam
        own = set()
        copies = {}
        for f, pfx in BACKENDS.items():
            name = fam.replace('{p}', pfx) if tmpl else '%s_%s' % (pfx, fam)
            own.add(name)
            if name in defs:
                copies[pfx] = defs[name][0]
        label = fam.replace('{p}', '*') if tmpl else fam
        if len(copies) != 3:
            shared = fam in defs
            if shared and copies:
                # THE HALF-HOIST. A shared definition exists AND a backend still carries its own — which the
                # previous condition read as "already one shared copy, nothing to report" and stayed silent
                # about, because it tested the BACKEND-LOCAL names for presence: the very thing to report was
                # what silenced it. `wat_field_is_scalar` is this: #1045 hoisted field_is_scalar into
                # lower_layout and deleted the aarch64 and riscv64 copies, leaving wasm's, and the census
                # called the family clean. "Decided once" is not true of three backends until the last copy
                # is gone, and a criterion met twice out of three is not met.
                blocked[label] = ['shared copy exists, but %d backend(s) still keep their own: %s'
                                  % (len(copies), ', '.join('%s (%s:%d)' % (n, copies[n]['file'], copies[n]['start'])
                                                          for n in sorted(copies)))]
                continue
            if shared:
                # "fully hoisted" must mean ONE definition, not "no backend-prefixed copies remain".
                # `BACKENDS` covers the three twins only, so x86_64's emitter (`lower.al`) never enters
                # `copies` — and when a family is lifted into `lower_ctx` while `lower.al` keeps its own
                # definition under the SAME bare name, `fam in defs` is satisfied by either one and the
                # family was reported closed with two live definitions of the decision. Measured on the
                # #1066 tree: `slice_param_elem_span` is defined at `lower.al:6273` AND `lower_ctx.al:529`
                # — two definitions, reported as one shared decision. `lower.al:6273` is not even a copy
                # in the harmless sense: it carries a variadic branch (`name : ...T`) that returns a span
                # where the shared scan answers {0,0}, so the two definitions ANSWER DIFFERENTLY.
                # A census that calls a family closed because a name resolves somewhere is not a census of
                # copies; this is the same failure as the half-hoist above, one level up.
                shared_defs = defs[fam]
                in_emitter = [d for d in shared_defs if d['file'] in EMITTERS]
                if len(shared_defs) > 1:
                    blocked[label] = ['NOT hoisted: %d definitions of the bare name remain — %s%s'
                                      % (len(shared_defs),
                                         ', '.join('%s:%d' % (d['file'], d['start']) for d in shared_defs),
                                         ' — %d of them in an EMITTER, where a private copy is what criterion 2 '
                                         'forbids' % len(in_emitter) if in_emitter else '')]
                    continue
                if in_emitter:
                    blocked[label] = ['the one remaining definition sits in an emitter (%s:%d), not in shared '
                                     'code — criterion 2 is not met'
                                     % (in_emitter[0]['file'], in_emitter[0]['start'])]
                    continue
                continue          # fully hoisted: exactly one shared definition, no private copies left
            blocked[label] = ['only %d of 3 copies present' % len(copies)]
            continue
        # normalise BOTH the lowercase call prefix and the uppercase global prefix: a family whose three
        # copies differ only in their own backend's global (`A64_SUB_N` vs `RV_SUB_N`) is the same shape
        # three times, and the useful verdict is "blocked BY that global", not "bodies differ" — which
        # would hide the blocker behind a shape complaint.
        norm = {}
        for p, c in copies.items():
            b = re.sub(r'\b%s_' % p, 'X_', c['body'])
            b = re.sub(r'\b%s_' % {'a64': 'A64', 'rv': 'RV', 'wat': 'WAT'}[p], 'X_', b)
            norm[p] = strip_comments(b)
        vals = list(norm.values())
        if any(v != vals[0] for v in vals):
            blocked[label] = [diff_detail(norm)]
            continue
        seen, stack, blockers = set(), [], []
        for p, c in copies.items():
            stack.append((c['body'], 0))
        while stack:
            body, depth = stack.pop()
            if depth > 12:
                continue
            for g in globals_read(body):
                if g not in blockers:
                    blockers.append(g)
            for c in callees(body):
                if c in seen:
                    continue
                seen.add(c)
                if c in own or (not tmpl and c.endswith('_' + fam)):
                    continue      # a call into the family itself is internal, not a blocker
                if c in local:
                    tag = '%s (backend-local, %s:%d)' % (c, defs[c][0]['file'], defs[c][0]['start'])
                    if tag not in blockers:
                        blockers.append(tag)
                    stack.append((defs[c][0]['body'], depth + 1))
        lines = sum(c['end'] - c['start'] + 1 for c in copies.values())
        if blockers:
            blocked[label] = blockers
        else:
            liftable.append((label, lines))
    return liftable, blocked, True


def analyse(root, families, verbose):
    liftable, blocked, ok = classify(root, families)
    if not ok:
        print('copy_lift: parsed NO function definitions under %s — nothing is known' % root)
        return 2
    tot = sum(l for _, l in liftable)
    print('copy lift: families=%d LIFTABLE=%d (%d lines of definition) BLOCKED=%d'
          % (len(liftable) + len(blocked), len(liftable), tot, len(blocked)))
    for fam, lines in sorted(liftable):
        print('  LIFTABLE %-26s %4d lines  (identical x3, closure free of backend state)' % (fam, lines))
    for fam in sorted(blocked):
        print('  BLOCKED  %-26s %s' % (fam, '; '.join(blocked[fam][:4])))
    if verbose:
        print('  (closure depth 12; backend-local means defined in aarch64.al/riscv64.al/wat.al)')
    return 0


def capture(fn, *a, **kw):
    """Run `fn`, catching SystemExit, and return (rc, everything it printed). A self-test that only
    reads the return code cannot tell a refusal from a refusal-with-the-right-words, and the words are
    what the next agent acts on."""
    import io as _io, contextlib
    buf = _io.StringIO()
    rc = 0
    try:
        with contextlib.redirect_stdout(buf):
            r = fn(*a, **kw)
        rc = 0 if r is None else int(r)
    except SystemExit as e:
        rc = 0 if e.code is None else int(e.code)
    return rc, buf.getvalue()


def self_test():
    """Planted trees, and EVERY verdict asserted: an instrument nobody has seen give the wrong answer
    is an instrument nobody has seen work."""
    import tempfile, shutil
    t = tempfile.mkdtemp()
    os.makedirs(os.path.join(t, 'src'))
    def w(rel, txt):
        # APPEND: several families are planted in the same emitter file, and overwriting would leave
        # only the last one — which is exactly what the first version of this self-test did, and it
        # then "passed" two checks about families whose fixture had been erased.
        p = os.path.join(t, 'src', rel)
        with open(p, 'a', encoding='utf-8') as fh:
            fh.write(txt)
    F = {'a64': 'aarch64', 'rv': 'riscv64', 'wat': 'wat'}
    # 1. a clean triple: identical, calls only shared helpers -> LIFTABLE
    for pfx, f in F.items():
        w(f'{f}.al', f'{pfx}_clean := fn(x : ptr(u8)) -> bool {{\n  mut r := false\n  if shared_q(x) {{ r = true }}\n  r\n}}\n')
    # 2. identical but calls a backend-local helper -> BLOCKED (the mistake this instrument exists for)
    for pfx, f in F.items():
        w(f'{f}.al', f'{pfx}_chain := fn(x : ptr(u8)) -> bool {{\n  mut r := false\n  if {pfx}_helper(x) {{ r = true }}\n  r\n}}\n'
                     f'{pfx}_helper := fn(x : ptr(u8)) -> bool {{\n  false\n}}\n')
    # 3. identical but reads a backend global -> BLOCKED
    for pfx, f in F.items():
        g = {'a64': 'A64', 'rv': 'RV', 'wat': 'WAT'}[pfx]
        w(f'{f}.al', f'{pfx}_glob := fn(x : ptr(u8)) -> bool {{\n  mut r := false\n  if {g}_SUB_N > 0 {{ r = true }}\n  r\n}}\n')
    # 4. bodies differ -> BLOCKED
    w('aarch64.al', 'a64_diff := fn(x : ptr(u8)) -> bool {\n  true\n}\n')
    w('riscv64.al', 'rv_diff := fn(x : ptr(u8)) -> bool {\n  false\n}\n')
    w('wat.al', 'wat_diff := fn(x : ptr(u8)) -> bool {\n  true\n}\n')
    # 5. two hops to a backend-local helper -> BLOCKED, naming the far one (closure, not depth 1)
    for pfx, f in F.items():
        w(f'{f}.al', f'{pfx}_deep := fn(x : ptr(u8)) -> bool {{\n  mut r := false\n  if {pfx}_mid(x) {{ r = true }}\n  r\n}}\n'
                     f'{pfx}_mid := fn(x : ptr(u8)) -> bool {{\n  {pfx}_tail(x)\n}}\n'
                     f'{pfx}_tail := fn(x : ptr(u8)) -> bool {{\n  false\n}}\n')
    # 6. a call back into the family is internal, not a blocker
    for pfx, f in F.items():
        w(f'{f}.al', f'{pfx}_self := fn(x : ptr(u8), d : i64) -> bool {{\n  mut r := false\n  if d > 0 {{ r = {pfx}_self(x, d - 1) }}\n  r\n}}\n')
    # 7. already lifted: one shared copy, no backend copies -> not reported at all
    w('lower_layout.al', 'shared_q := fn(x : ptr(u8)) -> bool {\n  false\n}\n')
    # 8. identical code, DIFFERENT comments -> LIFTABLE. A `##` comment never reaches the emitted
    #    output, so blocking on one was a false blocker; `comp_range_bound` (320 lines) sat behind
    #    exactly this on the real tree.
    for pfx, f, cmt in (('a64', 'aarch64', 'x86-shaped note'), ('rv', 'riscv64', 'riscv note'),
                        ('wat', 'wat', 'wasm note')):
        w(f'{f}.al', f'{pfx}_cmt := fn(x : ptr(u8)) -> bool {{\n  ## {cmt}\n  true\n}}\n')
    # 9. identical code, DIFFERENT string literal -> BLOCKED. This is the soundness half of #8:
    #    a string CAN reach the emitted output, so the stripper must not blank strings out. If it
    #    did, this family would read LIFTABLE and the hoist would silently change bytes.
    for pfx, f, s in (('a64', 'aarch64', 'aarch64'), ('rv', 'riscv64', 'riscv64'),
                      ('wat', 'wat', 'wasm')):
        w(f'{f}.al', f'{pfx}_str := fn(x : ptr(u8)) -> ptr(u8) {{\n  "{s}"\n}}\n')
    # 10. a `##` INSIDE a string is not a comment: the stripper tracks quote state, and if it cut
    #     at the first `##` it saw, two different strings would compare equal.
    w('aarch64.al', 'a64_hash := fn(x : ptr(u8)) -> ptr(u8) {\n  "a ## b"\n}\n')
    w('riscv64.al', 'rv_hash := fn(x : ptr(u8)) -> ptr(u8) {\n  "a ## c"\n}\n')
    w('wat.al', 'wat_hash := fn(x : ptr(u8)) -> ptr(u8) {\n  "a ## b"\n}\n')
    fams = ['clean', 'chain', 'glob', 'diff', 'deep', 'self', 'shared_q', 'cmt', 'str', 'hash']
    liftable, blocked, ok = classify(t, fams)
    L = {f for f, _ in liftable}
    bad = 0
    seen_n = [0]

    def chk(name, cond, note=''):
        nonlocal bad
        seen_n[0] += 1
        if cond:
            print('  ok   %s' % name)
        else:
            print('  FAIL %s — %s' % (name, note) if note else '  FAIL %s' % name)
            print('       liftable=%s' % sorted(L))
            print('       blocked=%s' % {k: v[:1] for k, v in blocked.items()})
            bad += 1
    chk('a clean identical triple is LIFTABLE', 'clean' in L)
    chk('a call to a backend-local helper BLOCKS it', blocked.get('chain') and any('chain_helper' in b or 'helper' in b for b in blocked['chain']))
    chk('a backend global read BLOCKS it', blocked.get('glob') and any('SUB_N' in b for b in blocked['glob']))
    difftxt = ' '.join(blocked.get('diff', []))
    chk('differing bodies BLOCK it', difftxt.startswith('bodies DIFFER'))
    chk('and SAY what differs: the closest pair', 'closest pair a64/rv' in difftxt,
        'naming the pair is what makes the blocker actionable')
    chk('and quote the differing line', 'rv-only: false' in difftxt,
        'a lane must see the difference without opening three files')
    chk('the closure is transitive, not one hop', blocked.get('deep') and any('tail' in b for b in blocked['deep']))
    chk('a comment-only difference is LIFTABLE, not a blocker', 'cmt' in L,
        'a `##` never reaches the emitted output; blocking on it hid 320 lines on the real tree')
    chk('a DIFFERENT STRING LITERAL still BLOCKS', 'str' in blocked and 'str' not in L,
        'the soundness half: a string can reach the output, so the stripper must not blank strings')
    chk('a `##` inside a string is not cut as a comment', 'hash' in blocked and 'hash' not in L,
        'cutting at the first `##` seen would make two different strings compare equal')
    chk('a self-call is internal, not a blocker', 'self' in L)
    chk('an already-lifted family is not reported', 'shared_q' not in L and 'shared_q' not in blocked)
    chk('the run parsed something', ok)
    # The argument trap. `copy_lift.py .` once reported "1 family, blocked: `.`" and that number reached the
    # spec, because a positional was read as a family name and `.` is not one — the command invented a finding
    # instead of refusing. These three checks hold the refusal, so the lie cannot come back quietly.
    import subprocess
    me = os.path.abspath(__file__)
    def run(*a):
        p = subprocess.run([sys.executable, me] + list(a), capture_output=True, text=True)
        return p.returncode, (p.stdout + p.stderr)
    rc, out = run('no_such_family_xyz')
    chk('an unknown family name is refused, not answered', rc != 0 and 'no family' in out)
    rc, out = run('--jobs', '4')
    chk('an unknown option is refused, not eaten', rc != 0 and 'unknown option' in out)
    rc, out = run(t)
    chk('a bare directory is the root, not a phantom family', 'no family' not in out and 'copy lift:' in out)
    # The half-hoist. A shared definition plus ONE surviving private copy used to be reported as nothing at
    # all, because the condition tested the backend-local names for presence and treated a hit as "already
    # shared" — so the copy that was left behind was exactly what silenced the report. `wat_field_is_scalar`
    # is that case, found in the tree and invisible to the census.
    w('lower_layout.al', 'half := fn(x : ptr(u8)) -> bool {\n  false\n}\n')
    w('wat.al', 'wat_half := fn(x : ptr(u8)) -> bool {\n  false\n}\n')
    l2, b2, _ = classify(t, ['half'])
    chk('a HALF-hoist is reported, not called clean', 'half' not in {f for f, _ in l2}
        and b2.get('half') and 'still keep their own' in b2['half'][0]
        and 'wat.al' in b2['half'][0])
    # "Fully hoisted" means ONE definition. Two modules defining the same bare name is two copies of the
    # decision, and the old condition (`fam in defs`) could not tell them apart: BACKENDS excludes lower.al,
    # so x86_64's emitter never entered `copies`, and a family lifted into shared code while lower.al kept
    # its own definition was reported CLOSED. `slice_param_elem_span` is exactly that on the #1066 tree —
    # lower.al:6273 (with a variadic branch the shared scan lacks) and lower_ctx.al:529.
    w('lower_layout.al', 'hoist2 := fn(x : ptr(u8)) -> bool {\n  false\n}\n')
    w('lower.al', 'hoist2 := fn(x : ptr(u8)) -> bool {\n  true\n}\n')
    l3, b3, _ = classify(t, ['hoist2'])
    chk('two definitions of the bare name are NOT called hoisted', 'hoist2' not in {f for f, _ in l3}
        and b3.get('hoist2') and '2 definitions' in b3['hoist2'][0]
        and 'lower.al' in b3['hoist2'][0] and 'lower_layout.al' in b3['hoist2'][0])
    chk('and the emitter copy is named as the reason', 'EMITTER' in b3['hoist2'][0])
    # The control: exactly one shared definition, no private copy, is genuinely closed. Without this the
    # new rule could "pass" by reporting everything blocked, which would look strict and prove nothing.
    w('lower_layout.al', 'hoist1 := fn(x : ptr(u8)) -> bool {\n  false\n}\n')
    l4, b4, _ = classify(t, ['hoist1'])
    chk('ONE shared definition with no private copy is closed', 'hoist1' not in {f for f, _ in l4}
        and 'hoist1' not in b4)
    # The other half of the rule: a single definition that lives in an EMITTER is not shared code.
    w('lower.al', 'emitter_only := fn(x : ptr(u8)) -> bool {\n  false\n}\n')
    l5, b5, _ = classify(t, ['emitter_only'])
    chk('a lone definition in an emitter is not shared code', 'emitter_only' not in {f for f, _ in l5}
        and b5.get('emitter_only') and 'emitter' in b5['emitter_only'][0])
    # ── EXACT private copies, found by SHAPE, not by the FAMILIES list. The class this exists for:
    # a shared decision pasted into an emitter under a fresh name, which `FAMILIES` cannot see. Every
    # verdict below is asserted, including the ones that must NOT fire — an instrument that refuses
    # everything looks strict and proves nothing.
    w('lower_layout.al', 'shared_one := fn(x : ptr(u8), n : usize) -> bool {\n  mut r := false\n  if x != 0 { r = true }\n  r\n}\n')
    w('lower.al', 'x86_copy_one := fn(x : ptr(u8), n : usize) -> bool {\n  mut r := false\n  if x != 0 { r = true }\n  r\n}\n')
    pc = private_exact(t)
    chk('an EXACT copy under a NEW name is found by shape',
        any(e['name'] == 'x86_copy_one' and e['shared_file'] == 'lower_layout.al' for e in pc))
    bp = os.path.join(t, 'base_priv')
    io.open(bp, 'w', encoding='utf-8').write('private=0\n')
    rc_p, out_p = capture(private_ratchet, t, bp)
    chk('a NEW exact copy FAILS the ratchet and is named with its original',
        rc_p == 1 and 'x86_copy_one' in out_p and 'lower_layout.al' in out_p)
    chk('the refusal says HOW to acknowledge it', 'copy-ok:' in out_p)
    # A marker with a cited issue acknowledges it — and the reason prints, so it cannot go quiet.
    w('lower.al', '## copy-ok: #1234 — the shared one reads a global this emitter cannot see yet.\n'
                  'x86_copy_two := fn(x : ptr(u8), n : usize) -> bool {\n  mut r := false\n  if x != 0 { r = true }\n  r\n}\n')
    rc_p, out_p = capture(private_ratchet, t, bp)
    chk('a cited copy-ok marker is ACKed and prints its reason, while the unmarked copy still fails',
        rc_p == 1 and 'x86_copy_two' in out_p and '#1234' in out_p and 'ACK' in out_p
        and 'x86_copy_one' in out_p)
    # A marker that cites no issue is not a reason.
    w('lower.al', '## copy-ok: it is fine.\nx86_copy_three := fn(x : ptr(u8), n : usize) -> bool {\n  mut r := false\n  if x != 0 { r = true }\n  r\n}\n')
    rc_p, out_p = capture(private_ratchet, t, bp)
    chk('a copy-ok citing no issue is refused', rc_p == 1 and 'cites no issue' in out_p)
    # The control: with every copy in the baseline, the same tree passes. Without this the rule above
    # could "pass" only by never having been tried.
    names = {e['name'] for e in private_exact(t)}
    io.open(bp, 'w', encoding='utf-8').write(
        'private=%d\n' % len(names) + ''.join('B\t%s\tlower.al:0\tprivate x/y.al:0\t0\n' % n
                                                for n in sorted(names)))
    rc_p, out_p = capture(private_ratchet, t, bp)
    chk('the same tree PASSES once every copy is in the baseline (non-vacuity)', rc_p == 0)
    # No baseline is not a pass: the class would be silently unheld.
    rc_p, out_p = capture(private_ratchet, t, os.path.join(t, 'no_such_base'))
    chk('a missing baseline is rc=2, never a silent zero', rc_p == 2 and 'unheld' in out_p)
    # ── the parse span. A ONE-LINE definition must end on its own line. `j > i` made the scan run
    # past it and swallow every following definition until some accidental depth-0, so the body that
    # was compared was not the body — measured on main 99476a5, `lower_ctx.al:33 decl_at` came back
    # containing `pub decl_get := fn(...)`. An instrument that compares the wrong text both invents
    # duplicates and hides real ones, and every verdict downstream is then unfounded.
    w('lower_layout.al', 'one_liner := fn(x : usize) -> usize { x + 1 }\n'
                         'after_it := fn(x : usize) -> usize { x - 1 }\n')
    got = parse(os.path.join(t, 'src', 'lower_layout.al'))
    chk('a ONE-LINE definition ends on its own line',
        got['one_liner']['start'] == got['one_liner']['end']
        and 'after_it' not in got['one_liner']['body'])
    chk('and the definition after it is still found, not swallowed',
        'after_it' in got and got['after_it']['start'] > got['one_liner']['end'])
    shutil.rmtree(t)
    print('copy lift self-test: %d checks, %d failed' % (seen_n[0], bad))
    return 0 if bad == 0 else 1


def gate(root, baseline_path):
    """Hold the LIFTABLE count: once a family CAN be deleted, leaving it in place is a finding the gate
    refuses. BLOCKED families are reported but never fail — they name what the next slice must move.
    rc: 0 held, 1 grew, 2 unusable (no baseline, no parse, or a baseline that names no ceiling)."""
    liftable, blocked, ok = classify(root, FAMILIES)
    if not ok:
        print('copy lift gate: the tree did not parse — nothing is known, which is not a pass')
        return 2
    n = len(liftable)
    if not os.path.isfile(baseline_path):
        print('copy lift gate: FAIL — no baseline at %s. Record it with:' % baseline_path)
        print("  printf 'liftable=%%d\\n' %d > %s" % (n, baseline_path))
        print('  after lifting every family it reports, or set it to what is explained.')
        return 2
    base = None
    for ln in io.open(baseline_path, encoding='utf-8'):
        if ln.startswith('liftable='):
            base = ln.strip()[len('liftable='):].strip()
    if base is None or not base.isdigit():
        print('copy lift gate: FAIL — baseline holds no numeric `liftable=` ceiling (%s)' % baseline_path)
        return 2
    print('copy lift gate: liftable=%d baseline %s blocked=%d' % (n, base, len(blocked)))
    for fam, lines in sorted(liftable):
        print('  LIFTABLE %-26s %4d lines  — identical x3, closure free of backend state: DELETE IT' % (fam, lines))
    if n > int(base):
        print('copy lift gate: FAIL — %d families can be deleted and were not (baseline %s). Each one is a'
              % (n, base))
        print('  decision still made four times; lifting it is a byte-neutral refactor, and raising this')
        print('  ceiling would be recording the duplication as acceptable.')
        return 1
    print('  blocked (each names what the next slice must move first):')
    for fam in sorted(blocked):
        print('    %-26s %s' % (fam, '; '.join(blocked[fam][:3])))
    rc = private_ratchet(root, os.path.join(os.path.dirname(baseline_path),
                                             'copy_lift.private.baseline'))
    return rc


def private_ratchet(root, base_path):
    """Hold the EXACT private copies of shared decisions to the reviewed baseline, by name.

    rc: 0 held or improved, 1 a NEW copy appeared (or a marker cited no issue), 2 the baseline is
    missing or unreadable — an unmeasured tree is never a pass."""
    found = private_exact(root)
    if not os.path.isfile(base_path):
        print('copy lift private gate: NO baseline at %s — the class is unheld. Write it with:'
              % base_path)
        print('  python3 scripts/copy_lift.py --private-copies --write-baseline > %s' % base_path)
        return 2
    allowed, notes = set(), []
    for ln in io.open(base_path, encoding='utf-8'):
        ln = ln.strip()
        if not ln or ln.startswith('#'):
            continue
        if ln.startswith('private=') or ln.startswith('A='):
            notes.append(ln)
            continue
        # `class<TAB>name<TAB>emitter<TAB>home<TAB>calls` — the NAME is field 2. Reading field 1
        # would take the class letter for a name and report every copy as new, which is exactly the
        # kind of green-turned-red-by-format accident that makes a gate untrustworthy.
        f = ln.split('\t')
        if len(f) < 2 or not f[1]:
            print('copy lift private gate: malformed baseline line %r' % ln)
            return 2
        allowed.add(f[1])
    names = {e['name'] for e in found}
    new = sorted(names - allowed)
    gone = sorted(allowed - names)
    print('copy lift private gate: exact private copies=%d baseline %d (new=%d, retired=%d)'
          % (len(names), len(allowed), len(new), len(gone)))
    for e in found:
        if e['mark']:
            print('  ACK %-26s %s:%s copies %s:%s — %s'
                  % (e['name'], e['file'], e['line'], e['shared_file'], e['shared_line'], e['mark']))
    rc = 0
    if new:
        print('copy lift private gate: FAIL — %d NEW exact private cop%s of a shared decision:'
              % (len(new), 'y' if len(new) == 1 else 'ies'))
        for e in sorted(found, key=lambda x: (x['file'], x['line'])):
            if e['name'] in new:
                print('    %s:%s  %s  duplicates %s:%s'
                      % (e['file'], e['line'], e['name'], e['shared_file'], e['shared_line']))
        print('  One decision, one place (strict_forms.md §4). Call the shared one; if this copy')
        print('  genuinely cannot be shared yet, acknowledge it on the line above:')
        print('    ## copy-ok: #<issue> — <what forces a second copy here>')
        rc = 1
    unmarked_new = [e for e in found if e['name'] in new and e['mark'] and not re.search(r'#\d', e['mark'])]
    for e in unmarked_new:
        print('copy lift private gate: FAIL — the copy-ok marker on %s cites no issue; a reason must '
              'name one' % e['name'])
        rc = 1
    if gone:
        print('  retired since the baseline (coverage gained, delete those lines here in the same PR):')
        for n in gone:
            print('    %s' % n)
    return rc


if __name__ == '__main__':
    args = sys.argv[1:]
    root = '.'
    root_set = False
    if '--root' in args:
        i = args.index('--root'); root = args[i + 1]; root_set = True; del args[i:i + 2]
    verbose = '--verbose' in args
    if verbose:
        args.remove('--verbose')
    if '--self-test' in args:
        sys.exit(self_test())
    if '--private-copies' in args:
        args.remove('--private-copies')
        write = '--write-baseline' in args
        if write:
            args.remove('--write-baseline')
        found = private_exact(root)
        if write:
            # The SAME classified format the committed baseline uses, so `--write-baseline` regenerates
            # it. A baseline the documented command cannot produce is a trap: the next agent regenerates
            # it, the format changes under the ratchet's parser, and every copy reads as new.
            defs, _ = load(root)
            print('private=%d' % len(found))
            rows = []
            for e in sorted(found, key=lambda x: x['line']):
                ds = defs[e['name']]
                low = [x for x in ds if x['file'] == e['file']][0]
                nc = _code(e['name'], low['body'])
                pubs = [d for d in ds if 'pub ' in d['body'].split('{')[0]
                        and _code(e['name'], d['body']) == nc]
                pubany = [d for d in ds if 'pub ' in d['body'].split('{')[0]]
                c = sum(len(re.findall(r'(?<![:\w.])%s\s*\(' % re.escape(e['name']), strip_noise(ln)))
                        for ln in open(os.path.join(root, 'src', e['file']),
                                       encoding='utf-8', errors='replace'))
                if pubs:
                    cls, home = 'A', 'pub %s:%s' % (pubs[0]['file'], pubs[0]['start'])
                elif pubany:
                    cls, home = 'C', 'pub %s:%s DIFFERS' % (pubany[0]['file'], pubany[0]['start'])
                else:
                    cls, home = 'B', 'private %s:%s' % (e['shared_file'], e['shared_line'])
                rows.append((cls, e['name'], '%s:%s' % (e['file'], e['line']), home, c))
            # Grouped by class, then line — the committed baseline's order, so a regeneration is
            # byte-identical and a diff of the baseline means the TREE changed, not the sort.
            for cls in 'ABC':
                for r in [x for x in rows if x[0] == cls]:
                    print('%s\t%s\t%s\t%s\t%d' % r)
            sys.exit(0)
        print('copy lift: %d EXACT private copies of a shared decision in an emitter' % len(found))
        for e in sorted(found, key=lambda x: (x['file'], x['line'])):
            print('  %-26s %s:%-6s duplicates %s:%s%s'
                  % (e['name'], e['file'], e['line'], e['shared_file'], e['shared_line'],
                     '  [copy-ok: %s]' % e['mark'] if e['mark'] else ''))
        sys.exit(0)
    if '--gate' in args:
        args.remove('--gate')
        sys.exit(gate(root, os.path.join(root, 'scripts', 'copy_lift.baseline')))
    # A positional is a FAMILY NAME, not a path — which is how `copy_lift.py .` came to report one blocked
    # family named `.` and a human to write that number into the spec: the command answered a question nobody
    # asked, in a format that looked like an answer. So: a directory is the root, an unknown flag is an error,
    # and a family name must be one this tool knows. A typo in a family name is not a finding about that family.
    fams = []
    for a in args:
        if a.startswith('--'):
            sys.exit('copy lift: unknown option %s — known: --root DIR, --gate, --verbose, --self-test' % a)
        if os.path.isdir(a):
            if root_set and root != a:
                sys.exit('copy lift: root given twice (--root %s and %s)' % (root, a))
            root, root_set = a, True
            continue
        known = [f for f in FAMILIES if f == a or ('{p}' in f and f.replace('{p}', '*') == a)]
        if not known:
            sys.exit('copy lift: no family %r in this tool\'s list — pass a name from FAMILIES, or nothing '
                     'to check them all' % a)
        fams.append(a)
    fams = fams if fams else FAMILIES
    sys.exit(analyse(root, fams, verbose))
