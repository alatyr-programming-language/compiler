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
One package-less file over ONE scalar type, `i64` or `u64` (the program's `ty`): a handful of
functions, each a body of typed locals, bounded `while` loops, `if` statements and expressions over
literals (negative ones included, #444), parameters, calls to earlier functions, the glyph operators
`+ - * / % & | ^` and the six comparisons.

On top of that scalar core a program switches on, independently and per seed, any of four FORMS
(`--forms` narrows the set; `self-test` forces each one alone):
  * struct  — `S1 := struct { k1 : ty, ... }` with one to four fields (multi-word ones included);
              literals `S1(k1 = e, ...)`, immutable and `mut` locals, field reads `s.k1`, field
              writes `s.k1 = e`, by-value struct parameters, struct copies, and functions returning a
              struct whose field is read straight off the call (`mk(..).k2`);
  * enum    — `E1 := enum { V1(ty, ty), V2, ... }` with zero to three payload words per variant;
              constructions `E1.V1(a, b)`, enum locals and parameters, enum-returning functions
              matched straight off the call, and EXHAUSTIVE `match` — every variant spelled, no
              wildcard — both as an expression and as a statement;
  * result  — functions returning `Result(T, ty)` (T is `ty` or, with structs on, a struct), an early
              `Err` under a generated condition, `x := f(..)?` bindings (the ONLY position a
              multi-word `?` value is used in: elsewhere the compiler refuses it by design, #758),
              and `match f(..) { Result::Ok(q) => {..} Result::Err(q) => {..} }` everywhere else;
  * brand   — `B1 := brand(ty)`, brand locals and parameters, brand-returning functions, and only the
              EXPLICIT conversions Types §4.2/§5.4 prescribe: `B1(e)` in, `ty(b)` out, a sibling via
              `B2(ty(b1))`. Arithmetic on a brand goes through its block: `B1(unchecked (ty(a) + ty(b)))`.
A program with no form switched on is the original scalar program, so the scalar differential keeps
its full strength.

It is kept well-defined on purpose, so that a disagreement can only be a compiler's:
  * every arithmetic operator is wrapped in `unchecked (...)`, so overflow is two's-complement wrap,
    specified (CG-7) and identical on every backend — never a trap one backend takes and another not;
  * every divisor is nonzero by construction (`(d % 7) + 8` for i64, `(d % 7) + 1` for u64), and a
    signed division never meets `MIN / -1` because the divisor is at least 2 in magnitude;
  * every loop runs a literal number of iterations (a counter against a small bound);
  * no function calls itself or a later one, so every program terminates;
  * `main` folds the results into an exit code in 1..113 — below 126, as WASI requires.
Every program also carries an ambient `checked_add` trigger in an uncalled function: a single file that
spells no prelude trigger gets NO prelude, so all four backends take the built-in operator path and a
defect in the library path is invisible (#532).

WHAT THE NON-x86 BACKENDS DO WITH THE FORMS (measured on `main` b8cf45d)
-----------------------------------------------------------------------
aarch64, riscv64 and wasm implement a scalar core plus struct locals, by-value struct parameters and
enum locals with `match`; a function RETURNING a struct, an enum or a `Result`, and any brand
construction, is lowered to a deliberate trap there (`brk`/`unreachable`, exit 133/134). A trap is
fail-loud and is not a disagreement, so on those shapes the check compares nothing beyond x86_64 until
the backend grows the shape — at which point the same seeds start comparing, with no change here.

THE MODEL
---------
`model_exit` evaluates the generated AST with the specified semantics of the one scalar type and
answers the exit code the program MUST produce. It turns a disagreement into a verdict on which side
is wrong, and it sees what the differential cannot: a program on which every backend that finishes
agrees on the same wrong answer. Such a program is reported as MODEL — informational, never a failure
of the run, because the model is a second implementation and can itself be wrong; `model --seed S`
prints its answer for a seed. Its first 5000 seeds found the class it was built for: a signed `/` or
`%` whose dividend is not a bare typed name (`unchecked (v - w) / 2`, an `if` expression, a
literal-only `(0 - 7)`) divides unsigned on all four backends.

DETERMINISM, TIMEOUTS, REDUCTION
--------------------------------
`--seed S` makes the whole run reproducible; every finding prints its own program seed. `--jobs N`
changes only how many programs run at once, never which programs. A run that breaches the wall-clock
ceiling is re-run ALONE before it is believed (#537): "the machine was busy" and "this program hangs"
are different findings. A disagreement is REDUCED — statements dropped, expressions replaced by one of
their operands or a literal — while the disagreement persists, so the report is something a person can
read. Each finding is written to `--out` as `wrong-<seed>.al` (the reduced program, its per-backend
exits and the model's answer in its header) plus `wrong-<seed>.orig.al` (the program as generated);
`refused-`, `hang-` and `model-<seed>.al` likewise, and one line per finding in `findings.tsv`.
A run exits 1 on any WRONG or REFUSED; HANG and MODEL are reported and do not fail it.

NOT IN THE AUTHORITATIVE GATE (#582 item 7): its input is random by design, and the landing verdict
must be reproducible. It runs nightly instead (`.github/workflows/progen-nightly.yml`), and its findings
become issues and then ordinary fixtures. `self-test` is deterministic and proves the comparator can
see a disagreement at all and that every form is generated, accepted and run.

Usage (inside `nix develop`, from the repository root, after `seed/alatyr build package.al`):
    python3 scripts/progen.py run [--seed S] [--count N] [--jobs J] [--forms F,..] [--cc PATH] [--out DIR]
    python3 scripts/progen.py show --seed S [--forms F,..]   # print the program a seed generates
    python3 scripts/progen.py model --seed S [--forms F,..]  # print the exit the model computes
    python3 scripts/progen.py self-test [--cc PATH]
"""
import argparse
import concurrent.futures
import os
import random
import re
import resource
import shutil
import subprocess
import sys
import tempfile
import threading
import time

CEILING = 10.0          # seconds per guest run, as the sweeps use
TRAP_MIN = 128          # an exit code at or above this is a signal/trap, not a value
FORMS = ['struct', 'enum', 'result', 'brand']
FORM_P = 0.4            # each form is switched on for a program with this probability

# ---------------------------------------------------------------------------------------------
# The AST. Small tuples, so the reducer can rewrite them structurally.
#
# KINDS (the type of a value):  'v' the scalar `ty` · ('s', S) struct · ('e', E) enum ·
#                               ('b', B) brand · ('r', ok) Result(ok, ty) with ok 'v' or ('s', S)
#
# Scalar-valued expressions:
#   ('lit', v)                         integer literal (v may be negative for i64)
#   ('var', name)                      any kind — the kind is the binding's
#   ('bin', op, l, r)                  op in + - * & | ^
#   ('div', op, l, r)                  op in / % ; r is wrapped nonzero at render time
#   ('cmp', op, l, r)                  bool-valued, only as an `if` condition
#   ('if', c, t, f)
#   ('call', fname, [args])            kind = the callee's return kind
#   ('field', obj, fname)              obj: a struct-kind expression (a var or a call)
#   ('unbrand', b)                     `ty(b)`, b a brand-kind expression
#   ('match', scrut, E, [(V, [binds], expr)])       exhaustive; scrut a var of kind ('e', E)
#   ('rmatch', call, okname, okexpr, errname, errexpr)   `match call { Result::Ok .. Result::Err .. }`
# Non-scalar constructors:
#   ('slit', S, [exprs])  ('elit', E, V, [exprs])  ('bmk', B, expr)
# Statements:
#   ('let', name, expr, mutable)       scalar local
#   ('set', name, expr)
#   ('while', counter, bound, [stmts]) `counter` is declared by the loop itself
#   ('ifs', c, [then], [else])
#   ('slet', name, S, value, mutable)  struct local
#   ('fset', name, fname, expr)        field write on a `mut` struct local
#   ('elet', name, E, value)           enum local
#   ('blet', name, B, value)           brand local
#   ('mstmt', scrut, E, [(V, [binds], [stmts])])   exhaustive `match` statement
#   ('try', name, call)                `name := call?` — only inside a Result-returning function
# A function: {'name', 'params': [(p, kind)], 'ret': kind, 'body': [stmts], 'tail': ...}; the tail is
# the returned value, except for a Result function where it is ('rtail', cond, errexpr, okvalue).
# ---------------------------------------------------------------------------------------------

ARITH = ['+', '-', '*', '&', '|', '^']
DIVS = ['/', '%']
CMPS = ['==', '!=', '<', '<=', '>', '>=']


class Scope:
    """What a point in a body can see: every binding's kind, the mutable scalars, the mutable structs."""

    def __init__(self):
        self.kinds = {}
        self.muts = []
        self.smuts = []

    def copy(self):
        s = Scope()
        s.kinds = dict(self.kinds)
        s.muts = list(self.muts)
        s.smuts = list(self.smuts)
        return s

    def of(self, kind):
        return [n for n, k in self.kinds.items() if k == kind]


class Gen:
    def __init__(self, seed, ty, forms):
        self.r = random.Random(seed)
        self.ty = ty                    # 'i64' or 'u64'
        self.forms = set(forms)
        self.fns = []                   # (name, [param kinds], ret kind) generated so far
        self.structs = {}               # S -> [field names]
        self.enums = {}                 # E -> [(V, npayload)]
        self.brands = []
        self.n = 0
        self.in_result = False

    def fresh(self, p):
        self.n += 1
        return f'{p}{self.n}'

    def lit(self):
        k = self.r.choice([0, 1, 2, 3, 7, 10, 42, 100, 255, 1000, 65535, 1 << 31, (1 << 62) + 3])
        if self.ty == 'i64' and self.r.random() < 0.4:
            k = -k
        return ('lit', k)

    # --- declarations ------------------------------------------------------------------------

    def declare(self):
        if 'struct' in self.forms:
            for _ in range(self.r.randint(1, 2)):
                s = self.fresh('S')
                self.structs[s] = [f'k{i + 1}' for i in range(self.r.randint(1, 4))]
        if 'enum' in self.forms:
            for _ in range(self.r.randint(1, 2)):
                e = self.fresh('E')
                nv = self.r.randint(2, 4)
                self.enums[e] = [(f'V{i + 1}', self.r.choice([0, 1, 1, 2, 3])) for i in range(nv)]
        if 'brand' in self.forms:
            self.brands = [self.fresh('B') for _ in range(self.r.randint(1, 2))]

    def kinds_available(self):
        ks = [('s', s) for s in self.structs] + [('e', e) for e in self.enums] + [('b', b) for b in self.brands]
        return ks

    # --- values of a given kind --------------------------------------------------------------

    def calls_returning(self, kind):
        return [(f, ps) for f, ps, rk in self.fns if rk == kind]

    def call(self, f, pkinds, sc, depth):
        return ('call', f, [self.value(sc, k, depth) for k in pkinds])

    def value(self, sc, kind, depth):
        """An expression of `kind`. With depth <= 0 and an empty scope it is literal-only, which is
        what `main`'s argument lists use."""
        if kind == 'v':
            return self.expr(sc, depth)
        vars_ = sc.of(kind) if sc else []
        r = self.r.random()
        if vars_ and r < 0.45:
            return ('var', self.r.choice(vars_))
        makers = self.calls_returning(kind)
        if makers and depth > 0 and r < 0.65:
            f, ps = self.r.choice(makers)
            return self.call(f, ps, sc, depth - 1)
        return self.construct(sc, kind, depth)

    def construct(self, sc, kind, depth):
        t, name = kind
        d = max(depth - 1, 0)
        if t == 's':
            return ('slit', name, [self.expr(sc, d) for _ in self.structs[name]])
        if t == 'e':
            v, k = self.r.choice(self.enums[name])
            return ('elit', name, v, [self.expr(sc, d) for _ in range(k)])
        if t == 'b':
            if self.r.random() < 0.3 and len(self.brands) > 1:
                # a sibling brand, crossed explicitly through the block both share (§5.4)
                other = self.r.choice([b for b in self.brands if b != name])
                return ('bmk', name, ('unbrand', self.value(sc, ('b', other), d)))
            if self.r.random() < 0.3 and sc and sc.of(kind):
                a, b = self.r.choice(sc.of(kind)), self.r.choice(sc.of(kind))
                op = self.r.choice(ARITH)
                return ('bmk', name, ('bin', op, ('unbrand', ('var', a)), ('unbrand', ('var', b))))
            return ('bmk', name, self.expr(sc, d))
        raise ValueError(kind)

    # --- scalar expressions ------------------------------------------------------------------

    def leaf(self, sc):
        if sc:
            r = self.r.random()
            structs = [(n, k) for n, k in sc.kinds.items() if k[0] == 's']
            brands = [n for n, k in sc.kinds.items() if k[0] == 'b']
            scal = sc.of('v')
            if structs and r < 0.2:
                n, k = self.r.choice(structs)
                return ('field', ('var', n), self.r.choice(self.structs[k[1]]))
            if brands and r < 0.3:
                return ('unbrand', ('var', self.r.choice(brands)))
            if scal and r < 0.8:
                return ('var', self.r.choice(scal))
        return self.lit()

    def expr(self, sc, depth):
        r = self.r.random()
        if depth <= 0 or r < 0.25:
            return self.leaf(sc)
        if r < 0.55:
            return ('bin', self.r.choice(ARITH), self.expr(sc, depth - 1), self.expr(sc, depth - 1))
        if r < 0.64:
            return ('div', self.r.choice(DIVS), self.expr(sc, depth - 1), self.expr(sc, depth - 1))
        if r < 0.72:
            return ('if', self.cond(sc, depth - 1), self.expr(sc, depth - 1), self.expr(sc, depth - 1))
        if r < 0.80 and sc:
            enums = [(n, k[1]) for n, k in sc.kinds.items() if k[0] == 'e']
            if enums:
                n, e = self.r.choice(enums)
                return self.match_expr(sc, ('var', n), e, depth - 1)
        if r < 0.86:
            res = [(f, ps, rk) for f, ps, rk in self.fns if rk[0] == 'r']
            if res:
                f, ps, rk = self.r.choice(res)
                return self.rmatch(sc, f, ps, rk, depth - 1)
        return self.scalar_call(sc, depth - 1)

    def scalar_call(self, sc, depth):
        """A call yielding a scalar: a scalar function, a field off a struct-returning one, or the
        block of a brand-returning one."""
        if not self.fns:
            return self.lit()
        f, ps, rk = self.r.choice(self.fns)
        c = self.call(f, ps, sc, depth)
        if rk == 'v':
            return c
        if rk[0] == 's':
            return ('field', c, self.r.choice(self.structs[rk[1]]))
        if rk[0] == 'b':
            return ('unbrand', c)
        if rk[0] == 'e':
            return self.match_expr(sc, c, rk[1], depth)
        if rk[0] == 'r':
            return self.rmatch(sc, f, ps, rk, depth, c)
        return self.lit()

    def match_expr(self, sc, scrut, e, depth):
        arms = []
        for v, k in self.enums[e]:
            binds = [self.fresh('m') for _ in range(k)]
            inner = sc.copy() if sc else Scope()
            for b in binds:
                inner.kinds[b] = 'v'
            arms.append((v, binds, self.expr(inner, depth)))
        return ('match', scrut, e, arms)

    def rmatch(self, sc, f, ps, rk, depth, c=None):
        c = c or self.call(f, ps, sc, depth)
        ok, er = self.fresh('q'), self.fresh('q')
        inner = (sc.copy() if sc else Scope())
        inner.kinds[ok] = rk[1]
        inner.kinds[er] = 'v'
        if rk[1] == 'v':
            oke = ('bin', self.r.choice(ARITH), ('var', ok), self.expr(sc, 0)) if self.r.random() < 0.5 else ('var', ok)
        else:
            oke = ('field', ('var', ok), self.r.choice(self.structs[rk[1][1]]))
        erre = ('bin', self.r.choice(ARITH), ('var', er), self.lit()) if self.r.random() < 0.5 else ('var', er)
        return ('rmatch', c, ok, oke, er, erre)

    def cond(self, sc, depth):
        return ('cmp', self.r.choice(CMPS), self.expr(sc, depth), self.expr(sc, depth))

    # --- statements ----------------------------------------------------------------------------

    def simple_sets(self, sc, depth):
        out = []
        if sc.muts:
            out.append(('set', self.r.choice(sc.muts), self.expr(sc, depth)))
        if sc.smuts and self.r.random() < 0.3:
            s = self.r.choice(sc.smuts)
            out.append(('fset', s, self.r.choice(self.structs[sc.kinds[s][1]]), self.expr(sc, depth)))
        return out

    def stmts(self, sc, depth, n):
        out = []
        sc = sc.copy()
        for _ in range(n):
            r = self.r.random()
            if r < 0.35 or not sc.muts:
                name = self.fresh('v')
                out.append(('let', name, self.expr(sc, depth), True))
                sc.kinds[name] = 'v'
                sc.muts.append(name)
            elif r < 0.5:
                out.append(('set', self.r.choice(sc.muts), self.expr(sc, depth)))
            elif r < 0.6 and depth > 0:
                c = self.fresh('c')
                inner = sc.copy()
                inner.kinds[c] = 'v'
                out.append(('while', c, self.r.randint(1, 5), self.simple_sets(inner, depth - 1)))
            elif r < 0.68:
                out.append(('ifs', self.cond(sc, depth - 1), self.simple_sets(sc, depth - 1),
                            self.simple_sets(sc, depth - 1)))
            elif r < 0.8 and self.kinds_available():
                kind = self.r.choice(self.kinds_available())
                name = self.fresh({'s': 's', 'e': 'e', 'b': 'b'}[kind[0]])
                val = self.value(sc, kind, depth)
                if kind[0] == 's':
                    mut = self.r.random() < 0.5
                    out.append(('slet', name, kind[1], val, mut))
                    if mut:
                        sc.smuts.append(name)
                elif kind[0] == 'e':
                    out.append(('elet', name, kind[1], val))
                else:
                    out.append(('blet', name, kind[1], val))
                sc.kinds[name] = kind
            elif r < 0.86 and sc.smuts:
                s = self.r.choice(sc.smuts)
                out.append(('fset', s, self.r.choice(self.structs[sc.kinds[s][1]]), self.expr(sc, depth)))
            elif r < 0.93 and any(k[0] == 'e' for k in sc.kinds.values() if k != 'v'):
                n_, e = self.r.choice([(n_, k[1]) for n_, k in sc.kinds.items() if k != 'v' and k[0] == 'e'])
                arms = []
                for v, k in self.enums[e]:
                    binds = [self.fresh('m') for _ in range(k)]
                    inner = sc.copy()
                    for b in binds:
                        inner.kinds[b] = 'v'
                    arms.append((v, binds, self.simple_sets(inner, depth - 1)))
                out.append(('mstmt', ('var', n_), e, arms))
            elif self.in_result and any(rk[0] == 'r' for _, _, rk in self.fns):
                f, ps, rk = self.r.choice([x for x in self.fns if x[2][0] == 'r'])
                name = self.fresh('t')
                out.append(('try', name, self.call(f, ps, sc, depth - 1)))
                sc.kinds[name] = rk[1]
            else:
                out.append(('set', self.r.choice(sc.muts), self.expr(sc, depth)))
        return out, sc

    # --- functions -----------------------------------------------------------------------------

    def function(self):
        # the return kind: scalar mostly; a struct, a brand or a Result when the form is on
        rets = ['v', 'v']
        rets += [('s', s) for s in self.structs]
        rets += [('b', b) for b in self.brands]
        rets += [('e', e) for e in self.enums]
        if 'result' in self.forms:
            rets += [('r', 'v'), ('r', 'v')] + [('r', ('s', s)) for s in self.structs]
        ret = self.r.choice(rets)
        if 'result' in self.forms and not any(rk[0] == 'r' for _, _, rk in self.fns) and self.r.random() < 0.5:
            ret = ('r', 'v')
        name = self.fresh({'v': 'g', 's': 'mk', 'b': 'bf', 'e': 'ef', 'r': 'rf'}[ret[0] if ret != 'v' else 'v'])
        params = []
        for _ in range(self.r.randint(1, 3)):
            kinds = ['v', 'v', 'v'] + self.kinds_available()
            params.append((self.fresh('p'), self.r.choice(kinds)))
        sc = Scope()
        for p, k in params:
            sc.kinds[p] = k
        self.in_result = ret != 'v' and ret[0] == 'r'
        lead = []
        earlier = [x for x in self.fns if x[2][0] == 'r']
        if self.in_result and earlier and self.r.random() < 0.7:
            # a `?` binding up front, so a Result chain propagates an `Err` more often than not
            f, ps, rk = self.r.choice(earlier)
            t = self.fresh('t')
            lead.append(('try', t, self.call(f, ps, sc, 1)))
            sc.kinds[t] = rk[1]
        body, sc = self.stmts(sc, 3, self.r.randint(1, 5))
        body = lead + body
        self.in_result = False
        if ret == 'v':
            tail = self.expr(sc, 3)
        elif ret[0] == 'r':
            cond = self.cond(sc, 1) if self.r.random() < 0.7 else None
            tail = ('rtail', cond, self.expr(sc, 2), self.value(sc, ret[1], 2))
        else:
            tail = self.value(sc, ret, 2)
            if tail[0] == 'call':           # keep a maker from simply forwarding an earlier one
                tail = self.construct(sc, ret, 2)
        fn = {'name': name, 'params': params, 'ret': ret, 'body': body, 'tail': tail}
        self.fns.append((name, [k for _, k in params], ret))
        return fn

    def program(self, nfns):
        self.declare()
        fns = [self.function() for _ in range(nfns)]
        calls = []
        for f, ps, rk in self.fns:
            c = self.call(f, ps, None, 0)
            if rk == 'v':
                calls.append(c)
            elif rk[0] == 's':
                calls.append(('field', c, self.r.choice(self.structs[rk[1]])))
            elif rk[0] == 'b':
                calls.append(('unbrand', c))
            elif rk[0] == 'e':
                calls.append(self.match_expr(None, c, rk[1], 0))
            else:
                calls.append(self.rmatch(None, f, ps, rk, 0, c))
        return {'ty': self.ty, 'forms': sorted(self.forms), 'structs': self.structs, 'enums': self.enums,
                'brands': self.brands, 'fns': fns, 'calls': calls}


# ---------------------------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------------------------

def rlit(v, ty):
    if v < 0:
        return f'(0 - {-v})'
    return str(v)


def rkind(k, P):
    ty = P['ty']
    if k == 'v':
        return ty
    if k[0] in ('s', 'e', 'b'):
        return k[1]
    if k[0] == 'r':
        return f'Result({rkind(k[1], P)}, {ty})'
    raise ValueError(k)


def rexpr(e, P):
    ty = P['ty']
    k = e[0]
    if k == 'lit':
        return rlit(e[1], ty)
    if k == 'var':
        return e[1]
    if k == 'bin':
        return f'unchecked ({rexpr(e[2], P)} {e[1]} {rexpr(e[3], P)})'
    if k == 'div':
        # nonzero, and at least 2 in magnitude for i64 so MIN / -1 cannot arise
        d = rexpr(e[3], P)
        guard = f'unchecked (({d} % 7) + 8)' if ty == 'i64' else f'unchecked (({d} % 7) + 1)'
        return f'unchecked ({rexpr(e[2], P)} {e[1]} {guard})'
    if k == 'cmp':
        return f'{rexpr(e[2], P)} {e[1]} {rexpr(e[3], P)}'
    if k == 'if':
        return f'(if {rexpr(e[1], P)} {{ {rexpr(e[2], P)} }} else {{ {rexpr(e[3], P)} }})'
    if k == 'call':
        return f'{e[1]}(' + ', '.join(rexpr(a, P) for a in e[2]) + ')'
    if k == 'field':
        return f'{rexpr(e[1], P)}.{e[2]}'
    if k == 'unbrand':
        return f'{ty}({rexpr(e[1], P)})'
    if k == 'match':
        arms = ' '.join(f'{pat(e[2], v, bs)} => {{ {rexpr(x, P)} }}' for v, bs, x in e[3])
        return f'(match {rexpr(e[1], P)} {{ {arms} }})'
    if k == 'rmatch':
        return (f'(match {rexpr(e[1], P)} {{ Result::Ok({e[2]}) => {{ {rexpr(e[3], P)} }} '
                f'Result::Err({e[4]}) => {{ {rexpr(e[5], P)} }} }})')
    if k == 'slit':
        fields = P['structs'][e[1]]
        return f'{e[1]}(' + ', '.join(f'{f} = {rexpr(x, P)}' for f, x in zip(fields, e[2])) + ')'
    if k == 'elit':
        return f'{e[1]}.{e[2]}' + (('(' + ', '.join(rexpr(x, P) for x in e[3]) + ')') if e[3] else '')
    if k == 'bmk':
        return f'{e[1]}({rexpr(e[2], P)})'
    raise ValueError(k)


def pat(E, V, binds):
    return f'{E}::{V}' + (f'({", ".join(binds)})' if binds else '')


def rstmts(ss, P, ind):
    ty = P['ty']
    out = []
    pad = '  ' * ind
    for s in ss:
        k = s[0]
        if k == 'let':
            out.append(f'{pad}mut {s[1]} : {ty} = {rexpr(s[2], P)}')
        elif k == 'set':
            out.append(f'{pad}{s[1]} = {rexpr(s[2], P)}')
        elif k == 'while':
            c = s[1]
            out.append(f'{pad}mut {c} : {ty} = 0')
            out.append(f'{pad}while {c} < {s[2]} {{')
            out += rstmts(s[3], P, ind + 1)
            out.append(f'{pad}  {c} = {c} + 1')
            out.append(f'{pad}}}')
        elif k == 'ifs':
            out.append(f'{pad}if {rexpr(s[1], P)} {{')
            out += rstmts(s[2], P, ind + 1)
            out.append(f'{pad}}} else {{')
            out += rstmts(s[3], P, ind + 1)
            out.append(f'{pad}}}')
        elif k == 'slet':
            if s[4]:
                out.append(f'{pad}mut {s[1]} : {s[2]} = {rexpr(s[3], P)}')
            else:
                out.append(f'{pad}{s[1]} := {rexpr(s[3], P)}')
        elif k == 'fset':
            out.append(f'{pad}{s[1]}.{s[2]} = {rexpr(s[3], P)}')
        elif k in ('elet', 'blet'):
            out.append(f'{pad}{s[1]} : {s[2]} = {rexpr(s[3], P)}')
        elif k == 'mstmt':
            out.append(f'{pad}match {rexpr(s[1], P)} {{')
            for v, bs, body in s[3]:
                out.append(f'{pad}  {pat(s[2], v, bs)} => {{')
                out += rstmts(body, P, ind + 2)
                out.append(f'{pad}  }}')
            out.append(f'{pad}}}')
        elif k == 'try':
            out.append(f'{pad}{s[1]} := {rexpr(s[2], P)}?')
        else:
            raise ValueError(k)
    return out


def render(prog, seed):
    P = prog
    ty = prog['ty']
    forms = ','.join(prog['forms']) or 'scalar'
    L = [f'## progen seed={seed} ty={ty} forms={forms} (scripts/progen.py) — a generated program; see #582.',
         '## The uncalled function below is the ambient prelude trigger (#532).',
         'progen_trigger := fn() -> u64 {',
         '  match checked_add(u8(1), u8(1)) { Some(v) => { u64(v) } None => { 0 } }',
         '}']
    for s, fields in prog['structs'].items():
        L.append(f'{s} := struct {{ ' + ', '.join(f'{f} : {ty}' for f in fields) + ' }')
    for e, vs in prog['enums'].items():
        L.append(f'{e} := enum {{ ' + ', '.join(v + (f'({", ".join([ty] * n)})' if n else '') for v, n in vs) + ' }')
    for b in prog['brands']:
        L.append(f'{b} := brand({ty})')
    for fn in prog['fns']:
        ps = ', '.join(f'{p} : {rkind(k, P)}' for p, k in fn['params'])
        L.append(f'{fn["name"]} := fn({ps}) -> {rkind(fn["ret"], P)} {{')
        L += rstmts(fn['body'], P, 1)
        t = fn['tail']
        if t[0] == 'rtail':
            rt = rkind(fn['ret'], P)
            if t[1] is not None:
                L.append(f'  if {rexpr(t[1], P)} {{ return {rt}.Err({rexpr(t[2], P)}) }}')
            L.append(f'  return {rt}.Ok({rexpr(t[3], P)})')
        else:
            L.append(f'  return {rexpr(t, P)}')
        L.append('}')
    L.append('main := fn() -> u64 {')
    L.append(f'  mut acc : {ty} = 0')
    for c in prog['calls']:
        L.append(f'  acc = unchecked ((acc * 31) ^ {rexpr(c, P)})')
    if ty == 'i64':
        L.append('  mut r : i64 = acc % 113')
        L.append('  if r < 0 { r = r + 113 }')
        L.append('  return u64(r) + 1')
    else:
        L.append('  return (acc % 113) + 1')
    L.append('}')
    return '\n'.join(L) + '\n'


def generate(seed, forms=None):
    """The program a seed denotes. `forms` restricts the forms a seed may switch on (None = all);
    the rolls are made whatever the restriction, so narrowing never reshuffles the scalar core."""
    r = random.Random(seed)
    ty = r.choice(['i64', 'u64'])
    nfns = r.randint(1, 4)
    rolls = {f: r.random() < FORM_P for f in FORMS}
    allowed = FORMS if forms is None else forms
    on = [f for f in FORMS if rolls[f] and f in allowed]
    g = Gen(seed * 7919 + 1, ty, on)
    return g.program(nfns)


def generate_forced(seed, forms):
    """Every form in `forms` switched on, whatever the seed rolls — `self-test` and `show --force`."""
    r = random.Random(seed)
    ty = r.choice(['i64', 'u64'])
    nfns = max(r.randint(1, 4), 3)
    g = Gen(seed * 7919 + 1, ty, forms)
    return g.program(nfns)


# ---------------------------------------------------------------------------------------------
# The model: what the program means, computed by reading it
# ---------------------------------------------------------------------------------------------
# The differential check needs no expected value, and a disagreement is reported on that alone. The
# model is what TRIAGE needs: which side of a disagreement is right, and — the case the differential
# cannot see — a program on which all four backends agree on the same wrong answer. It evaluates the
# AST with the specified semantics of the one scalar type: two's-complement wrap for every `unchecked`
# operator (CG-7), truncating signed division and a remainder with the dividend's sign, orderings
# signed for `i64` and unsigned for `u64`, structs and enums as values (a copy is a copy). It is a
# reading aid and is never a failure criterion: a run fails on a disagreement or a refusal only.

class _Err(Exception):
    """A `?` that met an `Err`: unwinds to the enclosing Result function."""

    def __init__(self, v):
        self.v = v


def model_exit(P):
    ty = P['ty']
    M = 1 << 64
    fns = {fn['name']: fn for fn in P['fns']}

    def w(v):
        v %= M
        return v - M if ty == 'i64' and v >= 1 << 63 else v

    def tdiv(a, b):
        q = abs(a) // abs(b)
        return q if (a >= 0) == (b >= 0) else -q

    def trem(a, b):
        return a - b * tdiv(a, b)

    def ex(e, env):
        k = e[0]
        if k == 'lit':
            return w(e[1])
        if k == 'var':
            return env[e[1]]
        if k == 'bin':
            a, b = ex(e[2], env), ex(e[3], env)
            return w({'+': a + b, '-': a - b, '*': a * b, '&': a & b, '|': a | b, '^': a ^ b}[e[1]])
        if k == 'div':
            a, d = ex(e[2], env), ex(e[3], env)
            g = w(trem(d, 7) + (8 if ty == 'i64' else 1))
            return w(tdiv(a, g) if e[1] == '/' else trem(a, g))
        if k == 'cmp':
            a, b = ex(e[2], env), ex(e[3], env)
            return {'==': a == b, '!=': a != b, '<': a < b, '<=': a <= b, '>': a > b, '>=': a >= b}[e[1]]
        if k == 'if':
            return ex(e[2], env) if ex(e[1], env) else ex(e[3], env)
        if k == 'call':
            return call(e[1], [ex(a, env) for a in e[2]])
        if k == 'field':
            return ex(e[1], env)[e[2]]
        if k == 'unbrand':
            return ex(e[1], env)
        if k == 'bmk':
            return ex(e[2], env)
        if k == 'slit':
            return dict(zip(P['structs'][e[1]], [ex(x, env) for x in e[2]]))
        if k == 'elit':
            return (e[2], [ex(x, env) for x in e[3]])
        if k == 'match':
            v, pay = ex(e[1], env)
            for arm, bs, x in e[3]:
                if arm == v:
                    return ex(x, dict(env, **dict(zip(bs, pay))))
            raise AssertionError('non-exhaustive match')
        if k == 'rmatch':
            tag, v = ex(e[1], env)
            return ex(e[3], dict(env, **{e[2]: v})) if tag == 'Ok' else ex(e[5], dict(env, **{e[4]: v}))
        raise ValueError(k)

    def copy(v):
        return dict(v) if isinstance(v, dict) else v

    def run(ss, env):
        for s in ss:
            k = s[0]
            if k in ('let', 'set'):
                env[s[1]] = ex(s[2], env)
            elif k == 'while':
                env[s[1]] = 0
                while env[s[1]] < s[2]:
                    run(s[3], env)
                    env[s[1]] = w(env[s[1]] + 1)
            elif k == 'ifs':
                run(s[2] if ex(s[1], env) else s[3], env)
            elif k in ('slet', 'elet', 'blet'):
                env[s[1]] = copy(ex(s[3], env))
            elif k == 'fset':
                env[s[1]][s[2]] = ex(s[3], env)
            elif k == 'mstmt':
                v, pay = ex(s[1], env)
                for arm, bs, body in s[3]:
                    if arm == v:
                        inner = dict(env, **dict(zip(bs, pay)))
                        run(body, inner)
                        for n in env:               # arms write the enclosing mutables
                            env[n] = inner[n]
                        break
            elif k == 'try':
                tag, v = ex(s[2], env)
                if tag == 'Err':
                    raise _Err(v)
                env[s[1]] = copy(v)

    def call(name, args):
        fn = fns[name]
        env = {p: copy(a) for (p, _), a in zip(fn['params'], args)}
        t = fn['tail']
        if t[0] == 'rtail':
            try:
                run(fn['body'], env)
            except _Err as err:
                return ('Err', err.v)
            if t[1] is not None and ex(t[1], env):
                return ('Err', ex(t[2], env))
            return ('Ok', copy(ex(t[3], env)))
        run(fn['body'], env)
        return copy(ex(t, env))

    acc = 0
    for c in P['calls']:
        acc = w(w(acc * 31) ^ ex(c, {}))
    if ty == 'i64':
        r = trem(acc, 113)
        return (r + 113 if r < 0 else r) + 1
    return acc % 113 + 1


def model_of(P):
    """The model's exit, or a string saying why there is none (a candidate the reducer made that no
    longer means anything is the usual one)."""
    try:
        return model_exit(P)
    except (KeyError, AssertionError, ValueError, TypeError) as e:
        return f'none({type(e).__name__})'


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


def run_artifact(backend, art, d):
    """Run once; on a ceiling breach, re-run ALONE once more before calling it a hang (#537)."""
    rc, _, _, _, to = sh(RUNNER[backend] + [art], timeout=CEILING, cwd=d)
    if to:
        rc, _, _, _, to = sh(RUNNER[backend] + [art], timeout=CEILING * 3, cwd=d)
        if to:
            return 'hang'
    if backend == 'wasm' and rc == 134:
        return 'trap'
    if rc >= TRAP_MIN or rc < 0:
        return 'trap'
    return rc


def observe(cc, text, backends=BACKENDS):
    """Return {backend: exit-code | 'trap' | 'hang' | 'build:<why>'} for one program text. A program
    x86_64 refuses is not built for the others: it is not a program, and the refusal is the finding."""
    d = tempfile.mkdtemp(prefix='progen.')
    try:
        src = os.path.join(d, 'p.al')
        open(src, 'w').write(text)
        res = {}
        for b in backends:
            art, why = build(cc, b, src, d)
            res[b] = run_artifact(b, art, d) if art else 'build:' + why
            if b == 'x86_64' and not art:
                for rest in backends[1:]:
                    res[rest] = 'build:skipped'
                break
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

# The kind of every binding and every function of the program being reduced, per reducing thread.
# Names are unique program-wide (`Gen.fresh`), so one flat map answers "is this a scalar?". A struct,
# enum or brand is never replaced by a literal: measured, x86_64 does NOT always refuse the result
# (`Result(S2, u64).Ok(1)` was kept by a refusal reduction), so an ill-kinded candidate could survive
# and the reduced program would no longer be valid by construction.
_KINDS = threading.local()


def collect_kinds(p):
    vk = {}
    fk = {fn['name']: fn['ret'] for fn in p['fns']}

    def ex(e):
        if not isinstance(e, tuple):
            return
        if e[0] == 'match':
            for _, bs, x in e[3]:
                for b in bs:
                    vk[b] = 'v'
                ex(x)
            ex(e[1])
            return
        if e[0] == 'rmatch':
            vk[e[2]] = fk[e[1][1]][1]
            vk[e[4]] = 'v'
        for x in e[1:]:
            if isinstance(x, tuple):
                ex(x)
            elif isinstance(x, list):
                for y in x:
                    ex(y)

    def st(ss):
        for s in ss:
            k = s[0]
            if k == 'let':
                vk[s[1]] = 'v'
                ex(s[2])
            elif k == 'set':
                ex(s[2])
            elif k == 'while':
                vk[s[1]] = 'v'
                st(s[3])
            elif k == 'ifs':
                ex(s[1])
                st(s[2])
                st(s[3])
            elif k == 'slet':
                vk[s[1]] = ('s', s[2])
                ex(s[3])
            elif k in ('elet', 'blet'):
                vk[s[1]] = ('e' if k == 'elet' else 'b', s[2])
                ex(s[3])
            elif k == 'fset':
                ex(s[3])
            elif k == 'mstmt':
                for _, bs, body in s[3]:
                    for b in bs:
                        vk[b] = 'v'
                    st(body)
            elif k == 'try':
                vk[s[1]] = fk[s[2][1]][1]
                ex(s[2])

    for fn in p['fns']:
        for n, k in fn['params']:
            vk[n] = k
        st(fn['body'])
        ex(fn['tail'])
    for c in p['calls']:
        ex(c)
    return vk, fk


def is_scalar(e):
    k = e[0]
    if k == 'var':
        return _KINDS.vk.get(e[1]) == 'v'
    if k == 'call':
        return _KINDS.fk.get(e[1]) == 'v'
    return k in ('lit', 'bin', 'div', 'if', 'field', 'unbrand', 'match', 'rmatch')


def expr_candidates(e):
    """Simpler variants of `e`: a scalar becomes a literal or one of its scalar operands, and the
    reduction recurses into operands, arguments, fields and arms."""
    k = e[0]
    if k == 'lit':
        return
    if is_scalar(e):
        yield ('lit', 1)
    if k == 'var':
        return
    if k in ('bin', 'div', 'cmp'):
        if k != 'cmp':              # an operand of a comparison is not a condition
            yield e[2]
            yield e[3]
        for c in expr_candidates(e[2]):
            yield (k, e[1], c, e[3])
        for c in expr_candidates(e[3]):
            yield (k, e[1], e[2], c)
    elif k == 'if':
        yield e[2]
        yield e[3]
        for c in expr_candidates(e[1]):
            yield ('if', c, e[2], e[3])
        for c in expr_candidates(e[2]):
            yield ('if', e[1], c, e[3])
        for c in expr_candidates(e[3]):
            yield ('if', e[1], e[2], c)
    elif k == 'call':
        for i, a in enumerate(e[2]):
            for c in expr_candidates(a):
                yield ('call', e[1], e[2][:i] + [c] + e[2][i + 1:])
    elif k == 'field':
        for c in expr_candidates(e[1]):
            if c[0] != 'lit':
                yield ('field', c, e[2])
    elif k == 'unbrand':
        if e[1][0] == 'bmk':
            yield e[1][2]
        for c in expr_candidates(e[1]):
            if c[0] != 'lit':
                yield ('unbrand', c)
    elif k == 'match':
        for i, (v, bs, x) in enumerate(e[3]):
            yield x
            for c in expr_candidates(x):
                yield ('match', e[1], e[2], e[3][:i] + [(v, bs, c)] + e[3][i + 1:])
    elif k == 'rmatch':
        yield e[3]
        yield e[5]
        for c in expr_candidates(e[1]):
            if c[0] == 'call':
                yield ('rmatch', c) + e[2:]
        for c in expr_candidates(e[3]):
            yield e[:3] + (c,) + e[4:]
        for c in expr_candidates(e[5]):
            yield e[:5] + (c,)
    elif k in ('slit', 'elit'):
        xs = e[-1]
        for i, x in enumerate(xs):
            for c in expr_candidates(x):
                yield e[:-1] + (xs[:i] + [c] + xs[i + 1:],)
    elif k == 'bmk':
        for c in expr_candidates(e[2]):
            yield ('bmk', e[1], c)


def stmt_list_candidates(ss):
    for i in range(len(ss)):
        yield ss[:i] + ss[i + 1:]
    for i, s in enumerate(ss):
        k = s[0]
        pre, post = ss[:i], ss[i + 1:]
        if k in ('let', 'set', 'try'):
            for c in expr_candidates(s[2]):
                yield pre + [s[:2] + (c,) + s[3:]] + post
        elif k in ('slet', 'elet', 'blet', 'fset'):
            for c in expr_candidates(s[3]):
                yield pre + [s[:3] + (c,) + s[4:]] + post
        elif k == 'while':
            for c in stmt_list_candidates(s[3]):
                yield pre + [('while', s[1], s[2], c)] + post
            if s[2] > 1:
                yield pre + [('while', s[1], 1, s[3])] + post
        elif k == 'ifs':
            yield pre + s[2] + post
            yield pre + s[3] + post
            for c in expr_candidates(s[1]):
                yield pre + [('ifs', c, s[2], s[3])] + post
        elif k == 'mstmt':
            for j, (v, bs, body) in enumerate(s[3]):
                for c in stmt_list_candidates(body):
                    yield pre + [('mstmt', s[1], s[2], s[3][:j] + [(v, bs, c)] + s[3][j + 1:])] + post


def tail_candidates(t):
    if t[0] == 'rtail':
        if t[1] is not None:
            yield ('rtail', None, t[2], t[3])
            for c in expr_candidates(t[1]):
                yield ('rtail', c, t[2], t[3])
        for c in expr_candidates(t[2]):
            yield ('rtail', t[1], c, t[3])
        for c in expr_candidates(t[3]):
            yield ('rtail', t[1], t[2], c)
    else:
        yield from expr_candidates(t)


def unreferenced(p, name, drop):
    """True when `name` no longer occurs in the program once `drop` (a candidate without its
    declaration) is rendered — a whole-word search over the text is exact because names are unique."""
    try:
        text = render(drop, 0)
    except KeyError:                # a struct literal still needs the dropped struct's fields
        return False
    return re.search(r'\b' + re.escape(name) + r'\b', text) is None


def prog_candidates(p):
    fns = p['fns']
    # drop a function, or a type declaration, nothing refers to any more
    for fi, fn in enumerate(fns):
        cand = dict(p, fns=fns[:fi] + fns[fi + 1:])
        if unreferenced(p, fn['name'], cand):
            yield cand
    for key in ('structs', 'enums'):
        for name in p[key]:
            cand = dict(p, **{key: {k: v for k, v in p[key].items() if k != name}})
            if unreferenced(p, name, cand):
                yield cand
    for name in p['brands']:
        cand = dict(p, brands=[b for b in p['brands'] if b != name])
        if unreferenced(p, name, cand):
            yield cand
    # drop a top-level call (keep at least one)
    if len(p['calls']) > 1:
        for i in range(len(p['calls'])):
            yield dict(p, calls=p['calls'][:i] + p['calls'][i + 1:])
    for fi, fn in enumerate(fns):
        for b in stmt_list_candidates(fn['body']):
            yield dict(p, fns=fns[:fi] + [dict(fn, body=b)] + fns[fi + 1:])
        for c in tail_candidates(fn['tail']):
            yield dict(p, fns=fns[:fi] + [dict(fn, tail=c)] + fns[fi + 1:])
    for ci, c in enumerate(p['calls']):
        for a in expr_candidates(c):
            if a[0] != 'lit':
                yield dict(p, calls=p['calls'][:ci] + [a] + p['calls'][ci + 1:])


def reduce(cc, prog, seed, budget=400, keep=None, backends=BACKENDS):
    """Shrink `prog` while `keep(result)` holds — by default, while two backends still disagree."""
    if keep is None:
        keep = lambda res: not x86_refused(res) and disagreement(res)
    _KINDS.vk, _KINDS.fk = collect_kinds(prog)
    best = prog
    tries = 0
    changed = True
    while changed and tries < budget:
        changed = False
        for cand in prog_candidates(best):
            tries += 1
            if tries >= budget:
                break
            res = observe(cc, render(cand, seed), backends)
            if keep(res):
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


def parse_forms(s):
    if s is None:
        return None
    fs = [f for f in s.split(',') if f]
    for f in fs:
        if f not in FORMS + ['scalar']:
            raise SystemExit(f'progen: unknown form {f!r} (known: {", ".join(FORMS)}, scalar)')
    return [f for f in fs if f != 'scalar']


def cmd_show(a):
    forms = parse_forms(a.forms)
    prog = generate_forced(a.seed, forms) if a.force else generate(a.seed, forms)
    sys.stdout.write(render(prog, a.seed))


def tagof(res):
    return ' '.join(f'{b}={res[b]}' for b in BACKENDS if b in res).replace('\n', ' ').replace('\t', ' ')


def refusal(res):
    """The first line of x86_64's refusal, less its location, so a shrunk program is kept only while
    it is refused for the SAME reason."""
    why = res['x86_64'].split('\n')[0]
    return why.split(' at line ')[0]


def one_seed(cc, seed, forms, do_reduce):
    """Generate, observe, and on a finding reduce, one seed. Returns a dict: verdict, seed, res,
    text, model, and for a reduced finding stext/sres/smodel."""
    prog = generate(seed, forms)
    text = render(prog, seed)
    res = observe(cc, text)
    out = {'seed': seed, 'res': res, 'text': text, 'model': model_of(prog),
           'stext': None, 'sres': None, 'smodel': None}
    small = None
    if x86_refused(res):
        out['verdict'] = 'REFUSED'
        if do_reduce:
            # a program valid by construction that x86_64 refuses is a generator bug or a
            # fails-when-valid defect; either way it is read by a person, so it is shrunk too
            want = refusal(res)
            small = reduce(cc, prog, seed, keep=lambda r: x86_refused(r) and refusal(r) == want,
                           backends=['x86_64'])
            out['sres'] = observe(cc, render(small, seed), ['x86_64'])
    elif disagreement(res):
        out['verdict'] = 'WRONG'
        small = reduce(cc, prog, seed) if do_reduce else prog
        out['sres'] = observe(cc, render(small, seed))
    elif 'hang' in res.values():
        out['verdict'] = 'HANG'
    else:
        vals = {v for v in res.values() if isinstance(v, int)}
        # every backend that finished agrees — and disagrees with the model: informational only
        out['verdict'] = 'MODEL' if isinstance(out['model'], int) and vals and vals != {out['model']} else 'ok'
    if small is not None:
        out['stext'] = render(small, seed)
        out['smodel'] = model_of(small)
    return out


def cmd_run(a):
    cc = a.cc or default_cc()
    forms = parse_forms(a.forms)
    os.makedirs(a.out, exist_ok=True)
    tsv = open(os.path.join(a.out, 'findings.tsv'), 'a')
    counts = {'ok': 0, 'WRONG': 0, 'REFUSED': 0, 'HANG': 0, 'MODEL': 0}
    seeds = range(a.seed, a.seed + a.count)
    with concurrent.futures.ThreadPoolExecutor(max_workers=max(a.jobs, 1)) as ex:
        futs = [ex.submit(one_seed, cc, s, forms, a.reduce) for s in seeds]
        for fu in concurrent.futures.as_completed(futs):
            o = fu.result()
            verdict, seed, res, sres = o['verdict'], o['seed'], o['res'], o['sres']
            counts[verdict] += 1
            if verdict == 'ok':
                if a.verbose:
                    print(f'ok       seed={seed} {tagof(res)} model={o["model"]}')
                continue
            print(f'{verdict:8s} seed={seed} {tagof(res)} model={o["model"]}'
                  + (f'  reduced: {tagof(sres)} model={o["smodel"]}' if sres else ''))
            base = os.path.join(a.out, f'{verdict.lower()}-{seed}')
            repro = (f'## reproduce: python3 scripts/progen.py show --seed {seed}'
                     + (f' --forms {a.forms}' if a.forms else '') + '\n')
            if o['stext'] is not None:
                head = (f'## generated: {tagof(res)} model={o["model"]}\n'
                        f'## reduced:   {tagof(sres)} model={o["smodel"]}\n' + repro)
                open(base + '.al', 'w').write(head + o['stext'])
                open(base + '.orig.al', 'w').write(o['text'])
            else:
                open(base + '.al', 'w').write(f'## {tagof(res)} model={o["model"]}\n' + repro + o['text'])
            tsv.write(f'{verdict}\t{seed}\t{tagof(res)}\t{o["model"]}\t'
                      f'{tagof(sres) if sres else "-"}\t{o["smodel"] if sres else "-"}\n')
            tsv.flush()
    print(f'progen: seeds={a.seed}..{a.seed + a.count - 1} agree={counts["ok"]} wrong={counts["WRONG"]} '
          f'x86_refused={counts["REFUSED"]} hang={counts["HANG"]} model_only={counts["MODEL"]} out={a.out}')
    return 1 if (counts['WRONG'] or counts['REFUSED']) else 0


# One planted marker per form: the rendered text of a program with that form forced on must contain
# every one of these, or the generator silently stopped producing the form.
FORM_MARKERS = {
    'struct': [':= struct {', '.k'],
    'enum': [':= enum {', 'match ', '::V'],
    'result': ['-> Result(', ')?', 'Result::Ok(', '.Err('],
    'brand': [':= brand(', ' : B'],
}


def cmd_self_test(a):
    """Non-vacuity, both halves. (1) The comparator must see a disagreement it is handed and must
    not see one in agreeing or trap-only results. (2) The generator must produce programs x86_64
    accepts — a generator whose output is all refused would report nothing and look healthy — and
    must actually produce each form: for every form, a program with that form alone forced on must
    spell it, pass `check`, and run on x86_64 to an exit inside the 1..113 contract."""
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
    # reproducibility: the same seed renders the same text, and --forms narrowing is a restriction
    same = render(generate(12345), 12345) == render(generate(12345), 12345)
    print(f'  generator   seed determinism          {"ok" if same else "FAIL"}')
    bad += not same
    # the model, on two planted programs whose meaning is fixed by the specification: a signed
    # remainder takes the dividend's sign (-9 % 8 = -1, so main answers 113), and a `u64` ordering
    # is unsigned (1 < 0 - 1 wrapped, so main answers 42)
    planted = [
        ({'ty': 'i64', 'forms': [], 'structs': {}, 'enums': {}, 'brands': [], 'calls': [('call', 'g1', [('lit', -9)])],
          'fns': [{'name': 'g1', 'params': [('p', 'v')], 'ret': 'v', 'body': [],
                   'tail': ('div', '%', ('var', 'p'), ('lit', 0))}]}, 113, 'signed remainder'),
        ({'ty': 'u64', 'forms': [], 'structs': {}, 'enums': {}, 'brands': [], 'calls': [('call', 'g1', [('lit', 1)])],
          'fns': [{'name': 'g1', 'params': [('p', 'v')], 'ret': 'v', 'body': [],
                   'tail': ('if', ('cmp', '<', ('var', 'p'), ('bin', '-', ('lit', 0), ('lit', 1))),
                            ('lit', 41), ('lit', 0))}]}, 42, 'unsigned ordering'),
    ]
    for prog, want, name in planted:
        got = model_of(prog)
        print(f'  model       {name:26s} {"ok" if got == want else "FAIL"} (model={got}, want {want})')
        bad += got != want
    scalar = render(generate(12345, []), 12345)
    plain = all(m not in scalar for m in (':= struct', ':= enum', ':= brand', 'Result('))
    print(f'  generator   --forms scalar is scalar  {"ok" if plain else "FAIL"}')
    bad += not plain
    cc = a.cc or default_cc()
    if not os.path.exists(cc):
        print(f'  generator   (no compiler at {cc}; build it first)')
        print('progen self-test: FAIL')
        return 1
    ok = 0
    for s in range(20):
        d = tempfile.mkdtemp(prefix='progen.')
        try:
            src = os.path.join(d, 'p.al')
            open(src, 'w').write(render(generate(900 + s), 900 + s))
            ok += sh([cc, 'check', src], timeout=60)[0] == 0
        finally:
            shutil.rmtree(d, ignore_errors=True)
    print(f'  generator   x86 check accepts {ok}/20 generated programs {"ok" if ok == 20 else "FAIL"}')
    bad += ok != 20
    for form in FORMS:
        # the first seed from a fixed base whose program spells every marker: deterministic, and it
        # does not silently pass when the generator stops producing a form (50 misses fail it)
        for seed in range(4242, 4292):
            text = render(generate_forced(seed, [form]), seed)
            missing = [m for m in FORM_MARKERS[form] if m not in text]
            if not missing:
                break
        res = observe(cc, text, ['x86_64'])
        x = res['x86_64']
        good = not missing and isinstance(x, int) and 1 <= x <= 113
        why = f'missing {missing}' if missing else f'x86_64={x}'
        print(f'  form        {form:8s} planted seed={seed:<6d} {"ok" if good else "FAIL"} ({why})')
        bad += not good
    print(f'progen self-test: {"PASS" if not bad else "FAIL"}')
    return 1 if bad else 0


def main():
    sys.stdout.reconfigure(line_buffering=True)
    # A trapping guest must not leave a core file: qemu-user writes one into the working directory
    # and a nightly run over a thousand seeds would fill the disk (AGENTS.md: `ulimit -c 0`).
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    r = sub.add_parser('run')
    r.add_argument('--seed', type=int, default=1)
    r.add_argument('--count', type=int, default=50)
    r.add_argument('--jobs', type=int, default=1)
    r.add_argument('--forms', help=f'comma list from {",".join(FORMS)},scalar (default: all)')
    r.add_argument('--cc')
    r.add_argument('--out', default='target/progen')
    r.add_argument('--no-reduce', dest='reduce', action='store_false')
    r.add_argument('--verbose', action='store_true')
    s = sub.add_parser('show')
    s.add_argument('--seed', type=int, required=True)
    s.add_argument('--forms')
    s.add_argument('--force', action='store_true', help='switch every --forms form on, as self-test does')
    m = sub.add_parser('model')
    m.add_argument('--seed', type=int, required=True)
    m.add_argument('--forms')
    m.add_argument('--force', action='store_true')
    t = sub.add_parser('self-test')
    t.add_argument('--cc')
    a = ap.parse_args()
    if a.cmd == 'show':
        return cmd_show(a)
    if a.cmd == 'model':
        forms = parse_forms(a.forms)
        print(model_of(generate_forced(a.seed, forms) if a.force else generate(a.seed, forms)))
        return 0
    if a.cmd == 'run':
        return cmd_run(a)
    return cmd_self_test(a)


if __name__ == '__main__':
    sys.exit(main() or 0)
