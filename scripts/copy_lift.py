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
import io, os, re, sys

BACKENDS = {'aarch64.al': 'a64', 'riscv64.al': 'rv', 'wat.al': 'wat'}
# Families from docs/ir.md §2.4 — the decisions named there, prefix-normalised.
FAMILIES = [
    'operand_narrow', 'local_narrow',
    'operand_signed', 'operand_signed_dep', 'bin_init_signed', 'shift_call_signed',
    'local_ann_signed', 'local_rhs',
    'operand_unsigned', 'cmp_unsigned', 'local_ann_unsigned', 'index_elem_unsigned',
    'unchecked_init_unsigned', 'hole_index_signed', 'local_arrty_span', 'slice_param_elem_span',
    'ann_arr_words', 'local_ann_span', 'slice_elem_span', 'tyname_words',
    'emit_narrow', 'emit_narrow_trap', 'local_scan', 'inst_add',
    'comp_cond_fold', 'comp_range_bound', 'emit_{p}_match_arms', 'try_success_disc',
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
            if fam in defs or any(n in defs for n in own):
                continue          # already one shared copy — nothing to report as a defect
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
            norm[p] = b
        vals = list(norm.values())
        if any(v != vals[0] for v in vals):
            blocked[label] = ['bodies DIFFER between backends']
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
    fams = ['clean', 'chain', 'glob', 'diff', 'deep', 'self', 'shared_q']
    liftable, blocked, ok = classify(t, fams)
    shutil.rmtree(t)
    L = {f for f, _ in liftable}
    bad = 0
    def chk(name, cond):
        nonlocal bad
        if cond:
            print('  ok   %s' % name)
        else:
            print('  FAIL %s — liftable=%s blocked=%s' % (name, sorted(L), {k: v[:2] for k, v in blocked.items()}))
            bad += 1
    chk('a clean identical triple is LIFTABLE', 'clean' in L)
    chk('a call to a backend-local helper BLOCKS it', blocked.get('chain') and any('chain_helper' in b or 'helper' in b for b in blocked['chain']))
    chk('a backend global read BLOCKS it', blocked.get('glob') and any('SUB_N' in b for b in blocked['glob']))
    chk('differing bodies BLOCK it', blocked.get('diff') == ['bodies DIFFER between backends'])
    chk('the closure is transitive, not one hop', blocked.get('deep') and any('tail' in b for b in blocked['deep']))
    chk('a self-call is internal, not a blocker', 'self' in L)
    chk('an already-lifted family is not reported', 'shared_q' not in L and 'shared_q' not in blocked)
    chk('the run parsed something', ok)
    print('copy lift self-test: 8 checks, %d failed' % bad)
    return 0 if bad == 0 else 1


if __name__ == '__main__':
    args = sys.argv[1:]
    root = '.'
    if '--root' in args:
        i = args.index('--root'); root = args[i + 1]; del args[i:i + 2]
    verbose = '--verbose' in args
    if verbose:
        args.remove('--verbose')
    if '--self-test' in args:
        sys.exit(self_test())
    fams = args if args else FAMILIES
    sys.exit(analyse(root, fams, verbose))
