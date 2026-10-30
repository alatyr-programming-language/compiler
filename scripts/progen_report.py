#!/usr/bin/env python3
"""progen_report.py: turn a red progen nightly into issues, one per (verdict, seed, backend) (#1128).

## Why

`progen-nightly.yml` ran every night and failed loudly, but a red run opened nothing: the 2026-10-14..22
red streak was found by someone reading logs. This script is the hook. It reads every `findings.tsv`
under the downloaded artifacts and, for each finding that fails the night (WRONG, REFUSED, CRASH),
makes sure exactly one issue tracks each backend the finding blames:

- no issue yet: open one, with the reproduce command, the per-backend exits as generated and as
  reduced, the reduced program when the artifact holds it, and the run's URL;
- an open issue: add one comment naming the run (so a finding that keeps recurring is visible);
- a closed issue: the finding came back after a fix. Reopen it with a comment, and do not open a
  duplicate.

An issue is found by its marker line, `<!-- progen-finding: VERDICT seed=S backend=B -->`, among the
issues labelled `progen`. The marker, not the title, is the key, so an issue may be retitled freely.

## Which backend a finding blames

- REFUSED: x86_64, by definition (the build of a program valid by construction failed there).
- CRASH: every backend whose compiler crashed (`build:crash...`).
- WRONG: every backend whose integer exit differs from progen's model, when the model is an integer;
  otherwise every backend outside the largest group of agreeing exits (all of them on a tie).

## The regression list

The issue tells the fixer to add the seed to `scripts/progen_regress.tsv` in the fix PR. The full gate
replays every seed in that list, so a fixed finding cannot come back unseen. The nightly holds no
`contents: write` token, so it cannot commit the seed itself, by design.

## Usage

  progen_report.py --dir DIR --run-url URL [--dry]   DIR is searched for findings.tsv files
  progen_report.py --self-test                       the deciders, and a dry run on planted rows

`--dry` prints what it would do instead of calling `gh`.
"""
import argparse
import glob
import json
import os
import re
import subprocess
import sys

BACKENDS = ['x86_64', 'aarch64', 'riscv64', 'wasm']
FAILING = ('WRONG', 'REFUSED', 'CRASH')
LABEL = 'progen'
MARK = re.compile(r'<!-- progen-finding: (\S+) seed=(-?\d+) backend=(\S+) -->')


def parse_tag(tag):
    """`x86_64=3 aarch64=build:crash: x y wasm=7` -> {backend: int | str}. A value runs up to the next
    `<backend>=`, because a refusal or crash text may itself contain spaces."""
    out = {}
    if tag in ('', '-'):
        return out
    pat = re.compile(r'(?:^| )(' + '|'.join(BACKENDS) + r')=')
    hits = list(pat.finditer(tag))
    for i, m in enumerate(hits):
        end = hits[i + 1].start() if i + 1 < len(hits) else len(tag)
        v = tag[m.end():end].strip()
        out[m.group(1)] = int(v) if re.fullmatch(r'-?\d+', v) else v
    return out


def blamed(verdict, res, model):
    """The backends a finding blames, in BACKENDS order (see the module docstring)."""
    if verdict == 'REFUSED':
        return ['x86_64']
    if verdict == 'CRASH':
        return [b for b in BACKENDS if isinstance(res.get(b), str) and res[b].startswith('build:crash')]
    if verdict != 'WRONG':
        return []
    ints = {b: v for b, v in res.items() if isinstance(v, int)}
    if re.fullmatch(r'-?\d+', str(model)):
        return [b for b in BACKENDS if b in ints and ints[b] != int(model)]
    groups = {}
    for b, v in ints.items():
        groups.setdefault(v, []).append(b)
    sizes = sorted((len(g) for g in groups.values()), reverse=True)
    if len(sizes) > 1 and sizes[0] == sizes[1]:
        return [b for b in BACKENDS if b in ints]
    big = max(groups.values(), key=len)
    return [b for b in BACKENDS if b in ints and b not in big]


def findings(root):
    """Every failing finding under ROOT: dicts with verdict, seed, res, model, sres, smodel, dir."""
    out, seen = [], set()
    for tsv in sorted(glob.glob(os.path.join(root, '**', 'findings.tsv'), recursive=True)):
        for line in open(tsv, encoding='utf-8', errors='replace'):
            f = line.rstrip('\n').split('\t')
            if len(f) < 6 or f[0] not in FAILING:
                continue
            key = (f[0], f[1])
            if key in seen:
                continue
            seen.add(key)
            out.append({'verdict': f[0], 'seed': int(f[1]), 'res': parse_tag(f[2]), 'tag': f[2],
                        'model': f[3], 'stag': f[4], 'smodel': f[5], 'dir': os.path.dirname(tsv)})
    return out


def marker(verdict, seed, backend):
    return f'<!-- progen-finding: {verdict} seed={seed} backend={backend} -->'


def body_of(f, backend, run_url):
    prog = os.path.join(f['dir'], f"{f['verdict'].lower()}-{f['seed']}.al")
    text = open(prog, encoding='utf-8', errors='replace').read() if os.path.exists(prog) else None
    lines = [
        f"The progen nightly found a {f['verdict']} on **{backend}** for seed {f['seed']}.",
        '',
        f'- run: {run_url}',
        f"- as generated: `{f['tag']}`, model `{f['model']}`",
        f"- as reduced: `{f['stag']}`, model `{f['smodel']}`",
        f"- reproduce: `python3 scripts/progen.py show --seed {f['seed']}` (the program), "
        f"`python3 scripts/progen.py model --seed {f['seed']}` (its due exit), "
        f"`python3 scripts/progen.py run --seed {f['seed']} --count 1` (the verdict)",
        '',
        'Triage: decide whether it reproduces on x86_64 and set the milestone and labels. The fix PR '
        'adds a fixture that fails on its parent and adds this seed to `scripts/progen_regress.tsv`, '
        'which the full gate replays.',
    ]
    if text is not None:
        lines += ['', '<details><summary>reduced program (from the run artifact)</summary>', '',
                  '```', text.rstrip('\n'), '```', '', '</details>']
    lines += ['', marker(f['verdict'], f['seed'], backend)]
    return '\n'.join(lines) + '\n'


def plan(fs, issues, run_url):
    """What to do: a list of (action, number_or_None, title, body, labels). `issues` is a list of
    {number, state, body}. Pure, so the self-test holds it."""
    known = {}
    for i in issues:
        for m in MARK.finditer(i.get('body') or ''):
            known.setdefault(m.groups(), i)
    acts = []
    for f in fs:
        for b in blamed(f['verdict'], f['res'], f['model']):
            key = (f['verdict'], str(f['seed']), b)
            i = known.get(key)
            note = f"The progen nightly found this again: {run_url}"
            if i is None:
                labels = [LABEL] + (['wrong-value'] if f['verdict'] == 'WRONG' else [])
                title = f"progen: {f['verdict']} on {b}, seed {f['seed']}"
                acts.append(('open', None, title, body_of(f, b, run_url), labels))
            elif i['state'].upper() == 'OPEN':
                acts.append(('comment', i['number'], None, note, []))
            else:
                acts.append(('reopen', i['number'], None,
                             note + '\n\nIt was closed, so the finding came back after a fix: reopened.', []))
    return acts


def gh(*args, inp=None):
    return subprocess.run(['gh', *args], input=inp, text=True, capture_output=True, check=True).stdout


def run(a):
    fs = findings(a.dir)
    print(f'progen_report: {len(fs)} failing finding(s) under {a.dir}')
    if not fs:
        return 0
    issues = [] if a.dry else json.loads(gh('issue', 'list', '--label', LABEL, '--state', 'all',
                                            '--limit', '1000', '--json', 'number,state,body'))
    acts = plan(fs, issues, a.run_url)
    for act, num, title, body, labels in acts:
        if a.dry:
            print(f'  {act} {num or ""} {title or ""} labels={",".join(labels)}')
            continue
        if act == 'open':
            args = ['issue', 'create', '--title', title, '--body-file', '-']
            for l in labels:
                args += ['--label', l]
            print('  opened ' + gh(*args, inp=body).strip())
        elif act == 'comment':
            gh('issue', 'comment', str(num), '--body-file', '-', inp=body)
            print(f'  commented on #{num}')
        else:
            gh('issue', 'reopen', str(num))
            gh('issue', 'comment', str(num), '--body-file', '-', inp=body)
            print(f'  reopened #{num}')
    return 0


def self_test():
    bad = 0

    def check(name, got, want):
        nonlocal bad
        ok = got == want
        bad += not ok
        print(f"  {'ok  ' if ok else 'FAIL'} {name}" + ('' if ok else f': got {got!r}, want {want!r}'))

    check('tag parse keeps spaces in a crash text',
          parse_tag('x86_64=3 aarch64=build:crash: sig 11 wasm=7'),
          {'x86_64': 3, 'aarch64': 'build:crash: sig 11', 'wasm': 7})
    check('tag parse: no tag', parse_tag('-'), {})
    check('REFUSED blames x86_64', blamed('REFUSED', {'x86_64': 'build: x'}, '3'), ['x86_64'])
    check('CRASH blames each crashed compiler, not a trap or a refusal',
          blamed('CRASH', {'x86_64': 3, 'aarch64': 'trap', 'riscv64': 'build:crash: a',
                           'wasm': 'build:crash: b'}, '3'),
          ['riscv64', 'wasm'])
    check('tag parse needs a space or the start before a backend name',
          parse_tag('x86_64=build: no xwasm=1 wasm=2'), {'x86_64': 'build: no xwasm=1', 'wasm': 2})
    check('WRONG blames the backends off the model',
          blamed('WRONG', {'x86_64': 4, 'aarch64': 2, 'riscv64': 2, 'wasm': 'trap'}, '2'), ['x86_64'])
    check('WRONG without a model blames the minority',
          blamed('WRONG', {'x86_64': 2, 'aarch64': 2, 'riscv64': 5, 'wasm': 2}, '?'), ['riscv64'])
    check('WRONG on a tie blames every answering backend',
          blamed('WRONG', {'x86_64': 2, 'aarch64': 5}, '?'), ['x86_64', 'aarch64'])
    check('HANG and MODEL blame nothing', blamed('HANG', {'x86_64': 'hang'}, '1'), [])

    f = {'verdict': 'WRONG', 'seed': 77, 'res': {'x86_64': 9, 'aarch64': 2, 'riscv64': 2, 'wasm': 2},
         'tag': 'x86_64=9 aarch64=2 riscv64=2 wasm=2', 'model': '2', 'stag': '-', 'smodel': '-',
         'dir': '/nonexistent'}
    acts = plan([f], [], 'RUN')
    check('a new finding opens one issue', [(a[0], a[4]) for a in acts], [('open', ['progen', 'wrong-value'])])
    check('the new issue carries its marker', marker('WRONG', 77, 'x86_64') in acts[0][3], True)
    open_i = [{'number': 5, 'state': 'OPEN', 'body': 'x\n' + marker('WRONG', 77, 'x86_64')}]
    check('a known open finding gets a comment, no duplicate',
          [(a[0], a[1]) for a in plan([f], open_i, 'RUN')], [('comment', 5)])
    closed_i = [{'number': 6, 'state': 'CLOSED', 'body': marker('WRONG', 77, 'x86_64')}]
    check('a closed finding that recurs is reopened',
          [(a[0], a[1]) for a in plan([f], closed_i, 'RUN')], [('reopen', 6)])
    other = [{'number': 7, 'state': 'OPEN', 'body': marker('WRONG', 77, 'wasm')}]
    check('the marker keys on the backend too',
          [a[0] for a in plan([f], other, 'RUN')], ['open'])

    # findings() and body_of() over a planted artifact directory, as the nightly lays it out.
    import tempfile
    with tempfile.TemporaryDirectory() as d:
        sd = os.path.join(d, 'progen-1-shard0')
        os.makedirs(sd)
        with open(os.path.join(sd, 'findings.tsv'), 'w') as t:
            t.write('WRONG\t11\tx86_64=4 aarch64=2\t2\tx86_64=4 aarch64=2\t2\n'
                    'WRONG\t11\tx86_64=4 aarch64=2\t2\tx86_64=4 aarch64=2\t2\n'
                    'MODEL\t12\tx86_64=1 aarch64=1\t2\t-\t-\n'
                    'HANG\t13\tx86_64=hang\t2\t-\t-\n'
                    'REFUSED\t14\tx86_64=build: x\t5\t-\t-\n')
        with open(os.path.join(sd, 'wrong-11.al'), 'w') as t:
            t.write('PLANTED-PROGRAM-TEXT\n')
        fs = findings(d)
        check('findings: failing verdicts only, each (verdict, seed) once',
              [(f['verdict'], f['seed']) for f in fs], [('WRONG', 11), ('REFUSED', 14)])
        check('findings: the model is the fourth column', fs[0]['model'], '2')
        b = body_of(fs[0], 'x86_64', 'RUN')
        check('body: the reduced program from the artifact', 'PLANTED-PROGRAM-TEXT' in b, True)
        check('body: both outputs and the run', all(x in b for x in ('x86_64=4 aarch64=2', 'RUN')), True)

    print(f"progen_report self-test: {'PASS' if not bad else 'FAIL'}")
    return 1 if bad else 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--dir')
    ap.add_argument('--run-url', default='(no run url)')
    ap.add_argument('--dry', action='store_true')
    ap.add_argument('--self-test', action='store_true')
    a = ap.parse_args()
    if a.self_test:
        return self_test()
    if not a.dir:
        ap.error('--dir is required')
    return run(a)


if __name__ == '__main__':
    sys.exit(main())
