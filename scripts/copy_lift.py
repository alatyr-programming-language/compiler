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
            if depth == 0 and j > i:
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
    return 0


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
