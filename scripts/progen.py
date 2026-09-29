#!/usr/bin/env python3
"""scripts/progen.py — a seeded program GENERATOR feeding the cross-backend differential check (#582).

WHY THIS EXISTS
---------------
Every fixture in test/ is one point someone thought to write. The three sweeps compare aarch64,
riscv64 and wasm against x86_64 over that corpus, and the comparison needs NO expected value: one
program, four backends, the answers must agree. What was missing is the thing that feeds it. This
script generates programs that are valid BY CONSTRUCTION, runs each on all four backends, and reports
every program on which two backends finish normally with different exit codes — a silent miscompile
on at least one of them, found without anyone deciding what the right answer is.

WHAT A GENERATED PROGRAM IS
---------------------------
One package-less file: a handful of functions over `i64` or `u64`, each a body of typed locals,
bounded `while` loops, `if` statements and expressions over literals (negative ones included, #444),
parameters, calls to earlier functions, the glyph operators `+ - * / % & | ^` and the six
comparisons. It is kept well-defined on purpose, so that a disagreement can only be a compiler's:
  * every arithmetic operator is wrapped in `unchecked (...)`, so overflow is two's-complement wrap,
    specified (CG-7) and identical on every backend — never a trap one backend takes and another not;
  * every divisor is nonzero by construction (`(d % 7) + 8` for i64, `(d % 7) + 1` for u64), and a
    signed division never meets `MIN / -1` because the divisor is at least 2 in magnitude;
  * every loop runs a literal number of iterations (a counter against a small bound);
  * `main` folds the results into an exit code in 1..113 — below 126, as WASI requires.
Every program also carries an ambient `checked_add` trigger in an uncalled function: a single file that
spells no prelude trigger gets NO prelude, so all four backends take the built-in operator path and a
defect in the library path is invisible (#532).

DETERMINISM, TIMEOUTS, REDUCTION
--------------------------------
`--seed S` makes the whole run reproducible; every finding prints its own program seed. A run that
breaches the wall-clock ceiling is re-run ALONE before it is believed (#537): "the machine was busy"
and "this program hangs" are different findings. A disagreement is REDUCED — statements dropped,
expressions replaced by one of their operands or a literal — while the disagreement persists, so the
report is something a person can read.

NOT IN THE AUTHORITATIVE GATE (#582 item 7): its input is random by design, and the landing verdict
must be reproducible. Findings become ordinary fixtures. `--self-test` is deterministic and proves the
comparator can see a disagreement at all.

Usage (inside `nix develop`, from the repository root, after `seed/alatyr build package.al`):
    python3 scripts/progen.py run [--seed S] [--count N] [--cc PATH] [--out DIR]
    python3 scripts/progen.py show --seed S          # print the program a seed generates
    python3 scripts/progen.py self-test [--cc PATH]
"""
import argparse
import os
import random
import shutil
import subprocess
import sys
import tempfile
import time

CEILING = 10.0          # seconds per guest run, as the sweeps use
TRAP_MIN = 128          # an exit code at or above this is a signal/trap, not a value

# ---------------------------------------------------------------------------------------------
# The AST. Small tuples, so the reducer can rewrite them structurally.
#   ('lit', v)                         integer literal (v may be negative for i64)
#   ('var', name)
#   ('bin', op, l, r)                  op in + - * & | ^
#   ('div', op, l, r)                  op in / % ; r is wrapped nonzero at render time
#   ('cmp', op, l, r)                  bool-valued, only as an `if` condition
#   ('if', c, t, f)                    value-valued
#   ('call', fname, [args])
# Statements:
#   ('let', name, expr, mutable)
#   ('set', name, expr)
#   ('while', counter, bound, [stmts])   `counter` is declared by the loop itself
#   ('ifs', c, [then], [else])
# ---------------------------------------------------------------------------------------------

ARITH = ['+', '-', '*', '&', '|', '^']
DIVS = ['/', '%']
CMPS = ['==', '!=', '<', '<=', '>', '>=']


class Gen:
    def __init__(self, seed, ty):
        self.r = random.Random(seed)
        self.ty = ty                    # 'i64' or 'u64'
        self.fns = []                   # (name, nparams) generated so far
        self.n = 0

    def fresh(self, p):
        self.n += 1
        return f'{p}{self.n}'

    def lit(self):
        k = self.r.choice([0, 1, 2, 3, 7, 10, 42, 100, 255, 1000, 65535, 1 << 31, (1 << 62) + 3])
        if self.ty == 'i64' and self.r.random() < 0.4:
            k = -k
        return ('lit', k)

    def expr(self, scope, depth):
        r = self.r.random()
        if depth <= 0 or r < 0.25:
            if scope and self.r.random() < 0.6:
                return ('var', self.r.choice(scope))
            return self.lit()
        if r < 0.62:
            return ('bin', self.r.choice(ARITH), self.expr(scope, depth - 1), self.expr(scope, depth - 1))
        if r < 0.74:
            return ('div', self.r.choice(DIVS), self.expr(scope, depth - 1), self.expr(scope, depth - 1))
        if r < 0.86:
            return ('if', self.cond(scope, depth - 1), self.expr(scope, depth - 1), self.expr(scope, depth - 1))
        if self.fns:
            f, k = self.r.choice(self.fns)
            return ('call', f, [self.expr(scope, depth - 1) for _ in range(k)])
        return self.lit()

    def cond(self, scope, depth):
        return ('cmp', self.r.choice(CMPS), self.expr(scope, depth), self.expr(scope, depth))

    def stmts(self, scope, depth, n):
        out = []
        scope = list(scope)
        muts = []
        for _ in range(n):
            r = self.r.random()
            if r < 0.45 or not muts:
                name = self.fresh('v')
                out.append(('let', name, self.expr(scope, depth), True))
                scope.append(name)
                muts.append(name)
            elif r < 0.7:
                out.append(('set', self.r.choice(muts), self.expr(scope, depth)))
            elif r < 0.85 and depth > 0:
                c = self.fresh('i')
                body = [('set', self.r.choice(muts), self.expr(scope + [c], depth - 1))]
                out.append(('while', c, self.r.randint(1, 5), body))
            else:
                t = [('set', self.r.choice(muts), self.expr(scope, depth - 1))]
                e = [('set', self.r.choice(muts), self.expr(scope, depth - 1))]
                out.append(('ifs', self.cond(scope, depth - 1), t, e))
        return out, scope, muts

    def function(self):
        name = self.fresh('f')
        k = self.r.randint(1, 3)
        params = [self.fresh('p') for _ in range(k)]
        body, scope, muts = self.stmts(params, 3, self.r.randint(1, 5))
        ret = self.expr(scope, 3)
        fn = (name, params, body, ret)
        self.fns.append((name, k))
        return fn

    def program(self, nfns):
        fns = [self.function() for _ in range(nfns)]
        calls = []
        for f, k in self.fns:
            calls.append(('call', f, [self.lit() for _ in range(k)]))
        return {'ty': self.ty, 'fns': fns, 'calls': calls}


# ---------------------------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------------------------

def rlit(v, ty):
    if v < 0:
        return f'(0 - {-v})'
    return str(v)


def rexpr(e, ty):
    k = e[0]
    if k == 'lit':
        return rlit(e[1], ty)
    if k == 'var':
        return e[1]
    if k == 'bin':
        return f'unchecked ({rexpr(e[2], ty)} {e[1]} {rexpr(e[3], ty)})'
    if k == 'div':
        # nonzero, and at least 2 in magnitude for i64 so MIN / -1 cannot arise
        d = rexpr(e[3], ty)
        guard = f'unchecked (({d} % 7) + 8)' if ty == 'i64' else f'unchecked (({d} % 7) + 1)'
        return f'unchecked ({rexpr(e[2], ty)} {e[1]} {guard})'
    if k == 'cmp':
        return f'{rexpr(e[2], ty)} {e[1]} {rexpr(e[3], ty)}'
    if k == 'if':
        return f'(if {rexpr(e[1], ty)} {{ {rexpr(e[2], ty)} }} else {{ {rexpr(e[3], ty)} }})'
    if k == 'call':
        return f'{e[1]}(' + ', '.join(rexpr(a, ty) for a in e[2]) + ')'
    raise ValueError(k)


def rstmts(ss, ty, ind):
    out = []
    pad = '  ' * ind
    for s in ss:
        k = s[0]
        if k == 'let':
            out.append(f'{pad}mut {s[1]} : {ty} = {rexpr(s[2], ty)}')
        elif k == 'set':
            out.append(f'{pad}{s[1]} = {rexpr(s[2], ty)}')
        elif k == 'while':
            c = s[1]
            out.append(f'{pad}mut {c} : {ty} = 0')
            out.append(f'{pad}while {c} < {s[2]} {{')
            out += rstmts(s[3], ty, ind + 1)
            out.append(f'{pad}  {c} = {c} + 1')
            out.append(f'{pad}}}')
        elif k == 'ifs':
            out.append(f'{pad}if {rexpr(s[1], ty)} {{')
            out += rstmts(s[2], ty, ind + 1)
            out.append(f'{pad}}} else {{')
            out += rstmts(s[3], ty, ind + 1)
            out.append(f'{pad}}}')
        else:
            raise ValueError(k)
    return out


def render(prog, seed):
    ty = prog['ty']
    L = [f'## progen seed={seed} ty={ty} (scripts/progen.py) — a generated program; see #582.',
         '## The uncalled function below is the ambient prelude trigger (#532).',
         'progen_trigger := fn() -> u64 {',
         '  match checked_add(u8(1), u8(1)) { Some(v) => { u64(v) } None => { 0 } }',
         '}']
    for (name, params, body, ret) in prog['fns']:
        ps = ', '.join(f'{p} : {ty}' for p in params)
        L.append(f'{name} := fn({ps}) -> {ty} {{')
        L += rstmts(body, ty, 1)
        L.append(f'  return {rexpr(ret, ty)}')
        L.append('}')
    L.append('main := fn() -> u64 {')
    L.append(f'  mut acc : {ty} = 0')
    for c in prog['calls']:
        L.append(f'  acc = unchecked ((acc * 31) ^ {rexpr(c, ty)})')
    if ty == 'i64':
        L.append('  mut r : i64 = acc % 113')
        L.append('  if r < 0 { r = r + 113 }')
        L.append('  return u64(r) + 1')
    else:
        L.append('  return (acc % 113) + 1')
    L.append('}')
    return '\n'.join(L) + '\n'


def generate(seed):
    r = random.Random(seed)
    ty = r.choice(['i64', 'u64'])
    g = Gen(seed * 7919 + 1, ty)
    return g.program(r.randint(1, 4))


# ---------------------------------------------------------------------------------------------
# Running one program on the four backends
# ---------------------------------------------------------------------------------------------

def sh(cmd, timeout=None, cwd=None):
    t0 = time.time()
    try:
        p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout, cwd=cwd)
        return p.returncode, p.stdout, p.stderr, time.time() - t0, False
    except subprocess.TimeoutExpired:
        return None, b'', b'', time.time() - t0, True


def build(cc, backend, src, d):
    """Build `src` for `backend` in directory `d`; return (artifact or None, why)."""
    if backend == 'x86_64':
        out = os.path.join(d, 'x86')
        rc, _, err, _, _ = sh([cc, '-o', out, src], timeout=120)
        return (out, '') if rc == 0 else (None, 'compile: ' + err.decode(errors='replace')[:200])
    if backend in ('aarch64', 'riscv64'):
        s, o, elf = [os.path.join(d, backend + x) for x in ('.s', '.o', '.elf')]
        rc, out, err, _, _ = sh([cc, backend, src], timeout=120)
        if rc != 0:
            return None, 'compile: ' + err.decode(errors='replace')[:200]
        open(s, 'wb').write(out)
        pre = f'{backend}-unknown-linux-gnu-'
        if sh([pre + 'as', s, '-o', o], timeout=60)[0] != 0:
            return None, 'reject: as'
        if sh([pre + 'ld', o, '-o', elf], timeout=60)[0] != 0:
            return None, 'reject: ld'
        return elf, ''
    if backend == 'wasm':
        wat, wasm = os.path.join(d, 'w.wat'), os.path.join(d, 'w.wasm')
        rc, out, err, _, _ = sh([cc, 'wat', src], timeout=120)
        if rc != 0:
            return None, 'compile: ' + err.decode(errors='replace')[:200]
        open(wat, 'wb').write(out)
        if sh(['wat2wasm', wat, '-o', wasm], timeout=60)[0] != 0:
            return None, 'reject: wat2wasm'
        return wasm, ''
    raise ValueError(backend)


RUNNER = {'x86_64': [], 'aarch64': ['qemu-aarch64'], 'riscv64': ['qemu-riscv64'], 'wasm': ['wasmtime']}
BACKENDS = ['x86_64', 'aarch64', 'riscv64', 'wasm']


def run_artifact(backend, art):
    """Run once; on a ceiling breach, re-run ALONE once more before calling it a hang (#537)."""
    rc, _, _, _, to = sh(RUNNER[backend] + [art], timeout=CEILING)
    if to:
        rc, _, _, _, to = sh(RUNNER[backend] + [art], timeout=CEILING * 3)
        if to:
            return 'hang'
    if backend == 'wasm' and rc == 134:
        return 'trap'
    if rc >= TRAP_MIN or rc < 0:
        return 'trap'
    return rc


def observe(cc, text):
    """Return {backend: exit-code | 'trap' | 'hang' | 'build:<why>'} for one program text."""
    d = tempfile.mkdtemp(prefix='progen.')
    try:
        src = os.path.join(d, 'p.al')
        open(src, 'w').write(text)
        res = {}
        for b in BACKENDS:
            art, why = build(cc, b, src, d)
            res[b] = run_artifact(b, art) if art else 'build:' + why
        return res
    finally:
        shutil.rmtree(d, ignore_errors=True)


def disagreement(res):
    """The finding the differential check exists for: two backends that FINISHED NORMALLY with
    different codes. A trap or a refused build is fail-loud and allowed (AGENTS.md); an x86_64 build
    failure on a program valid by construction is reported separately, as a generator or
    fails-when-valid finding."""
    vals = {b: v for b, v in res.items() if isinstance(v, int)}
    return len(set(vals.values())) > 1


def x86_refused(res):
    return isinstance(res['x86_64'], str) and res['x86_64'].startswith('build:')


# ---------------------------------------------------------------------------------------------
# Reduction: simplify while the disagreement persists
# ---------------------------------------------------------------------------------------------

def expr_candidates(e):
    k = e[0]
    if k in ('lit', 'var'):
        if k == 'var':
            yield ('lit', 1)
        return
    yield ('lit', 1)
    if k in ('bin', 'div'):
        yield e[2]
        yield e[3]
        for c in expr_candidates(e[2]):
            yield (k, e[1], c, e[3])
        for c in expr_candidates(e[3]):
            yield (k, e[1], e[2], c)
    elif k == 'if':
        yield e[2]
        yield e[3]
        for c in expr_candidates(e[2]):
            yield ('if', e[1], c, e[3])
        for c in expr_candidates(e[3]):
            yield ('if', e[1], e[2], c)
    elif k == 'call':
        for i, a in enumerate(e[2]):
            for c in expr_candidates(a):
                yield ('call', e[1], e[2][:i] + [c] + e[2][i + 1:])


def stmt_list_candidates(ss):
    for i in range(len(ss)):
        yield ss[:i] + ss[i + 1:]
    for i, s in enumerate(ss):
        k = s[0]
        if k in ('let', 'set'):
            for c in expr_candidates(s[2]):
                yield ss[:i] + [s[:2] + (c,) + s[3:]] + ss[i + 1:]
        elif k == 'while':
            for c in stmt_list_candidates(s[3]):
                yield ss[:i] + [('while', s[1], s[2], c)] + ss[i + 1:]
            if s[2] > 1:
                yield ss[:i] + [('while', s[1], 1, s[3])] + ss[i + 1:]
        elif k == 'ifs':
            yield ss[:i] + s[2] + ss[i + 1:]
            yield ss[:i] + s[3] + ss[i + 1:]


def prog_candidates(p):
    fns = p['fns']
    # drop a top-level call (keep at least one)
    if len(p['calls']) > 1:
        for i in range(len(p['calls'])):
            yield dict(p, calls=p['calls'][:i] + p['calls'][i + 1:])
    for fi, (name, params, body, ret) in enumerate(fns):
        for b in stmt_list_candidates(body):
            yield dict(p, fns=fns[:fi] + [(name, params, b, ret)] + fns[fi + 1:])
        for c in expr_candidates(ret):
            yield dict(p, fns=fns[:fi] + [(name, params, body, c)] + fns[fi + 1:])
    for ci, c in enumerate(p['calls']):
        for a in expr_candidates(c):
            if a[0] == 'call':
                yield dict(p, calls=p['calls'][:ci] + [a] + p['calls'][ci + 1:])


def valid_refs(p):
    """A candidate that removed a binding still referenced elsewhere is not a program; the x86_64
    refusal filters most, but checking names here saves four builds per rejected candidate."""
    return True


def reduce(cc, prog, seed, budget=400):
    best = prog
    tries = 0
    changed = True
    while changed and tries < budget:
        changed = False
        for cand in prog_candidates(best):
            tries += 1
            if tries >= budget:
                break
            res = observe(cc, render(cand, seed))
            if not x86_refused(res) and disagreement(res):
                best = cand
                changed = True
                break
    return best


# ---------------------------------------------------------------------------------------------
# Drivers
# ---------------------------------------------------------------------------------------------

def default_cc():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    return os.path.join(root, 'target', 'debug', 'alatyr')


def cmd_show(a):
    sys.stdout.write(render(generate(a.seed), a.seed))


def cmd_run(a):
    cc = a.cc or default_cc()
    os.makedirs(a.out, exist_ok=True)
    found = refused = hangs = agree = 0
    for i in range(a.count):
        seed = a.seed + i
        prog = generate(seed)
        text = render(prog, seed)
        res = observe(cc, text)
        tag = ' '.join(f'{b}={res[b]}' for b in BACKENDS)
        if x86_refused(res):
            refused += 1
            open(os.path.join(a.out, f'refused-{seed}.al'), 'w').write(text)
            print(f'REFUSED  seed={seed} {tag}')
        elif disagreement(res):
            found += 1
            small = reduce(cc, prog, seed) if a.reduce else prog
            stext = render(small, seed)
            sres = observe(cc, stext)
            open(os.path.join(a.out, f'wrong-{seed}.al'), 'w').write(stext)
            print(f'WRONG    seed={seed} {tag}  reduced: ' + ' '.join(f'{b}={sres[b]}' for b in BACKENDS))
        elif 'hang' in res.values():
            hangs += 1
            print(f'HANG     seed={seed} {tag}')
        else:
            agree += 1
            if a.verbose:
                print(f'ok       seed={seed} {tag}')
    print(f'progen: seeds={a.seed}..{a.seed + a.count - 1} agree={agree} wrong={found} '
          f'x86_refused={refused} hang={hangs} out={a.out}')
    return 1 if (found or refused) else 0


def cmd_self_test(a):
    """Non-vacuity, both halves. (1) The comparator must see a disagreement it is handed and must
    not see one in agreeing or trap-only results. (2) The generator must produce programs x86_64
    accepts — a generator whose output is all refused would report nothing and look healthy."""
    bad = 0
    cases = [
        ({'x86_64': 42, 'aarch64': 42, 'riscv64': 42, 'wasm': 42}, False, 'all agree'),
        ({'x86_64': 42, 'aarch64': 41, 'riscv64': 42, 'wasm': 42}, True, 'one backend differs'),
        ({'x86_64': 42, 'aarch64': 'trap', 'riscv64': 42, 'wasm': 'trap'}, False, 'traps are allowed'),
        ({'x86_64': 7, 'aarch64': 'build:reject: as', 'riscv64': 9, 'wasm': 7}, True, 'differs past a refusal'),
    ]
    for res, want, name in cases:
        got = disagreement(res)
        print(f'  comparator  {name:26s} {"ok" if got == want else "FAIL"} (disagreement={got})')
        bad += got != want
    # reproducibility: the same seed renders the same text
    same = render(generate(12345), 12345) == render(generate(12345), 12345)
    print(f'  generator   seed determinism          {"ok" if same else "FAIL"}')
    bad += not same
    cc = a.cc or default_cc()
    if os.path.exists(cc):
        ok = 0
        for s in range(5):
            d = tempfile.mkdtemp(prefix='progen.')
            try:
                src = os.path.join(d, 'p.al')
                open(src, 'w').write(render(generate(900 + s), 900 + s))
                rc = sh([cc, 'check', src], timeout=60)[0]
                ok += rc == 0
            finally:
                shutil.rmtree(d, ignore_errors=True)
        print(f'  generator   x86 check accepts {ok}/5 generated programs {"ok" if ok == 5 else "FAIL"}')
        bad += ok != 5
    else:
        print(f'  generator   (no compiler at {cc}; build it first)')
        bad += 1
    print(f'progen self-test: {"PASS" if not bad else "FAIL"}')
    return 1 if bad else 0


def main():
    sys.stdout.reconfigure(line_buffering=True)
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    r = sub.add_parser('run')
    r.add_argument('--seed', type=int, default=1)
    r.add_argument('--count', type=int, default=50)
    r.add_argument('--cc')
    r.add_argument('--out', default='target/progen')
    r.add_argument('--no-reduce', dest='reduce', action='store_false')
    r.add_argument('--verbose', action='store_true')
    s = sub.add_parser('show')
    s.add_argument('--seed', type=int, required=True)
    t = sub.add_parser('self-test')
    t.add_argument('--cc')
    a = ap.parse_args()
    if a.cmd == 'show':
        return cmd_show(a)
    if a.cmd == 'run':
        return cmd_run(a)
    return cmd_self_test(a)


if __name__ == '__main__':
    sys.exit(main() or 0)
