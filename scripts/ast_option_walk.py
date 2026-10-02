#!/usr/bin/env python3
"""Mechanical half of the AST-list migration to `Option(ptr(T))` (docs/ast-option-migration.md).

Two rewrites, each applied in place and reported per file. Review every hunk afterwards: the tool
handles the shapes the migration met in Bind/FInit/FieldDecl, and SKIPS (and reports) anything else.

  walk  <head-regex> <file>...
      A walk variable V is any `mut V := <head>` / `V = <head>` whose right-hand side matches
      <head-regex> (e.g. '[^\\n]*?fields_head'). Each later
          while V != 0 [and C] { BODY }        or   while unchecked bitcast(usize, V) != 0 [and C] { BODY }
      becomes
          loop { match V { Some(Vq) => { [if not (C) { break }] BODY' }; None => { break } } }
      where BODY' uses `Vq` for every use of V except an advance target `V = …`.
      A body that never advances V, or that already uses the name `Vq`, is skipped and reported.

  ifsome <file> <var>...
      `if V != 0 { BODY }` (no `else`) becomes `match V { Some(Vq) => { BODY' }; None => {} }`, for each
      listed variable V (BODY' as above). An `if … else` is skipped and reported.

Neither rewrite changes declarations: retype the list head / link field / locals / parameters by hand
(see the doc), and run the census + fixpoint measurements before and after.
"""
import re
import sys


def find_close(s, i):
    """Index of the `}` matching the `{` at s[i]; skips strings and `##` comments."""
    depth = 0
    j = i
    n = len(s)
    while j < n:
        c = s[j]
        if c == '"':
            j += 1
            while j < n and s[j] != '"':
                if s[j] == '\\':
                    j += 1
                j += 1
        elif c == '#' and s.startswith('##', j):
            while j < n and s[j] != '\n':
                j += 1
            continue
        elif c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0:
                return j
        j += 1
    raise ValueError('unbalanced braces')


def _code_spans(text):
    """Split `text` into (is_code, chunk) pieces: string literals and `##` comments are not code."""
    out, i, n, start = [], 0, len(text), 0
    while i < n:
        c = text[i]
        if c == '"' or (c == '#' and text.startswith('##', i)):
            if i > start:
                out.append((True, text[start:i]))
            j = i + 1
            if c == '"':
                while j < n and text[j] != '"':
                    j += 2 if text[j] == '\\' else 1
                j += 1
            else:
                while j < n and text[j] != '\n':
                    j += 1
            out.append((False, text[i:j]))
            i = start = j
            continue
        i += 1
    if start < n:
        out.append((True, text[start:]))
    return out


def _rename_uses(body, v, q):
    """Use `q` for every CODE use of `v` (never inside a string literal or a comment), except an
    advance target `v = …`. Returns (new body, whether the body advances `v`)."""
    adv = re.compile(r'(^|[;{]\s*|\n\s*)' + re.escape(v) + r'( = )')
    parts = []
    for is_code, chunk in _code_spans(body):
        if is_code:
            chunk = adv.sub(lambda mm: mm.group(1) + '\x00' + mm.group(2), chunk)
            chunk = re.sub(r'\b' + re.escape(v) + r'\b', q, chunk).replace('\x00', v)
        parts.append(chunk)
    return ''.join(parts), bool(adv.search(body))


WHILE = re.compile(r'while (?:unchecked bitcast\(usize, ([a-z_][a-z_0-9]*)\)|([a-z_][a-z_0-9]*)) != 0( and [^{]*)? \{')


def walk(head_re, files):
    tot = 0
    for f in files:
        s = open(f).read()
        vars_ = set(m.group(1) for m in re.finditer(
            r'(?:mut )?([a-z_][a-z_0-9]*)(?: : [^=\n]+)? :?= (?:' + head_re + r')(?![a-z_0-9(])', s))
        out, pos, cnt, skipped = [], 0, 0, []
        for m in WHILE.finditer(s):
            if m.start() < pos:
                continue
            v = m.group(1) or m.group(2)
            if v not in vars_:
                continue
            cond = (m.group(3) or '')[5:].strip()
            ob = m.end() - 1
            cb = find_close(s, ob)
            body = s[ob + 1:cb]
            q = v + 'q'
            line = s.count('\n', 0, m.start()) + 1
            if re.search(r'\b' + q + r'\b', body):
                skipped.append((line, v, 'name ' + q + ' taken'))
                continue
            nb, advances = _rename_uses(body, v, q)
            if not advances:
                skipped.append((line, v, 'no advance'))
                continue
            ls = s.rfind('\n', 0, m.start()) + 1
            ind = re.match(r'[ ]*', s[ls:]).group(0)
            if '\n' in body:
                nb_ind = nb.replace('\n', '\n    ')
                guard = (f'\n{ind}      if not ({cond}) {{ break }}' if cond else '')
                rep = (f'loop {{\n{ind}  match {v} {{\n{ind}    Some({q}) => {{' + guard + nb_ind.rstrip(' ') +
                       f'{ind}    }}\n{ind}    None => {{ break }}\n{ind}  }}\n{ind}}}')
            else:
                guard = (f' if not ({cond}) {{ break }};' if cond else '')
                rep = f'loop {{ match {v} {{ Some({q}) => {{{guard}{nb}}}; None => {{ break }} }} }}'
            out += [s[pos:m.start()], rep]
            pos = cb + 1
            cnt += 1
        out.append(s[pos:])
        open(f, 'w').write(''.join(out))
        tot += cnt
        if cnt or skipped:
            print(f'{f}: {cnt} walks rewritten' + (f'; SKIPPED {skipped}' if skipped else ''))
    print('walk: total', tot)


def ifsome(f, vs):
    s = open(f).read()
    tot = 0
    for v in vs:
        pat = re.compile(r'if (?:unchecked bitcast\(usize, ' + re.escape(v) + r'\)|' + re.escape(v) + r') != 0 \{')
        out, pos = [], 0
        for m in pat.finditer(s):
            if m.start() < pos:
                continue
            ob = m.end() - 1
            cb = find_close(s, ob)
            if re.match(r'\s*else', s[cb + 1:cb + 12]):
                print('SKIPPED (if … else)', f, v, 'line', s.count('\n', 0, m.start()) + 1)
                continue
            body = s[ob + 1:cb]
            q = v + 'q'
            nb, _ = _rename_uses(body, v, q)
            ls = s.rfind('\n', 0, m.start()) + 1
            ind = re.match(r'[ ]*', s[ls:]).group(0)
            if '\n' in body:
                nb_ind = nb.replace('\n', '\n  ')
                rep = (f'match {v} {{\n{ind}  Some({q}) => {{' + nb_ind.rstrip(' ') +
                       f'{ind}  }}\n{ind}  None => {{}}\n{ind}}}')
            else:
                rep = f'match {v} {{ Some({q}) => {{{nb}}}; None => {{}} }}'
            out += [s[pos:m.start()], rep]
            pos = cb + 1
            tot += 1
        out.append(s[pos:])
        s = ''.join(out)
    open(f, 'w').write(s)
    print(f'{f}: ifsome rewrites', tot)


if __name__ == '__main__':
    if len(sys.argv) < 3 or sys.argv[1] not in ('walk', 'ifsome'):
        print(__doc__)
        sys.exit(2)
    if sys.argv[1] == 'walk':
        walk(sys.argv[2], sys.argv[3:])
    else:
        ifsome(sys.argv[2], sys.argv[3:])
