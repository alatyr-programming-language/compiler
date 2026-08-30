---
name: alatyr-probe
description: >-
  Search the Alatyr compiler for defects that no issue describes yet, by building it and
  measuring its behaviour across a chosen class of language shapes. Probe never edits `src/`,
  `lib/`, `test/` or the oracles, never commits, pushes, or opens a pull request, and never claims
  an issue for implementation. Its only output is evidence: new issues, corrections to existing
  ones, and reports of where the gate is blind.
---

# Probing for what no issue names yet

`AGENTS.md` is the authority for repository invariants, safety, the pinned specification, and the
same-account model. Read it before acting. This skill is the *search* side of the workflow. The other
three operations all start from an issue that already exists:

- `alatyr-lane` implements one selected issue,
- `alatyr-research` removes the hold from one `needs-info` issue,
- `alatyr-integrate` lands one pull request.

None of them has a mandate to find a defect nobody has written down. That is this operation, and it
matters because a fully green gate is not the same as a correct compiler: the gate proves the shapes its
fixtures happen to cover. Every defect this skill has found so far was found while every gate was green.

## What probe produces

- a **new issue** with a reproducer, the mechanism, an explanation of why the gate did not see it, and
  acceptance criteria a lane can take without rework;
- a **correction** to an existing issue whose measurements have gone stale or whose claim does not
  reproduce;
- a **gate-blindness report** — the fixture that should have caught the class, and the reason it did not.

It produces no code. If a fix seems obvious, it still belongs to a lane; write the issue.

## 1 · Choose a class, not an issue

Probe selects a **class of shapes**, not a queue entry. Good classes are narrow enough that a matrix of
ten to twenty forms covers them:

- a language feature and its neighbours (narrow struct fields; enum payloads; multi-dimensional arrays)
- an operation across positions (read, write, return, pass by value, through a pointer, as an array
  element, across an FFI boundary)
- a surface that just changed — after any `chore(seed): self-promote`, the classes that promotion touched
- a claim in the specification that no fixture asserts

Prefer a class where the compiler recently changed, or where the corpus has few fixtures. Say which class
was chosen and why before measuring; a probe run that wanders is not reproducible.

## 2 · Isolate

Use a derived detached worktree at the current repository base. Never probe in the main checkout: other
operations use it, and two target-producing gates in one checkout corrupt each other's evidence.

```sh
W=$(mktemp -d)
git worktree add --detach "$W" origin/main
cd "$W" && nix develop -c bash scripts/dev.sh      # one self-build, ~1 min
```

Keep **two** compilers available:

- the one built from the tree under test, and
- a compiler from before the change you suspect — `git show <ref>:seed/alatyr` extracted with its
  matching `lib/` alongside it, since the standard-library lookup is relative to the executable.

The second one is what separates "regression" from "always been broken", and that distinction changes
who owns the fix and how urgent it is.

Probe fixtures and logs live in the scratch directory, never in `test/`.

## 3 · Measure, with the discipline the mistakes taught

Each rule below exists because ignoring it produced a wrong conclusion.

- **Keep every expected value below 126.** Exit codes are modulo 256. A probe expecting 723 reads back as
  211 and looks like a defect; two such probes were misread before this rule was written.
- **Read the exit status outside any pipeline.** `cmd | head` reports the status of `head`. This rule is
  in `AGENTS.md` and was still violated in practice.
- **Put a control beside every failing probe.** The same shape with a working type, or the correct
  spelling of the name. A failure with no passing twin cannot distinguish a defect from an unsupported
  form.
- **Use non-zero neighbours.** A zero-initialised array hides a stride disagreement completely, because
  both paths agree on zero. Two defects hid behind exactly this.
- **Check the field that is not the target.** Writing field 0 and reading field 0 passes under a word-wide
  store that destroys field 1.
- **Do not trust a first-position field to prove anything about width.** Offset 0 is the same under a byte
  model and a word model.
- **Confirm the emitted code, not only the answer.** Read the GAS for the shape. "The store is missing"
  and "the store went to the wrong offset with the wrong width" are different defects with different fixes.
- **Verify the harness before believing a refusal.** A rejection may come from a probe written in a form
  the language does not have. Find the corpus fixture that exercises the same construct and copy its
  spelling.
- **Cross-backend verdicts follow the sweeps' rule.** For aarch64/riscv64/wasm: matching x86 is fine, a
  clean trap (>= 128) is fine, an assembler or linker refusal is fine. A valid binary with a normal exit
  code that differs from x86 is the forbidden outcome. Compare against x86 only when x86 itself is correct.

## 4 · Classify before reporting

Answer these before opening anything:

1. **Is it a wrong value, a rejection of a valid program, or a missing diagnostic?** A clean compile
   producing a wrong answer outranks everything. A trap is an acceptable outcome and is not this class.
2. **Is it a regression?** Measure the same probe with the older compiler. Say which object each number
   came from.
3. **What is the boundary?** Vary one dimension at a time until the answer flips. "`[u8; N]` works for
   N <= 8" is a finding; "byte arrays are broken" is not.
4. **Why did the gate not see it?** Find the fixture that owns the class and state what it does
   differently — a wider type, a zero initialiser, a value never read back. If an oracle records the wrong
   answer as expected, say so explicitly: that is a finding in its own right and it changes how the fix
   must land.
5. **Does the compiler itself use the broken path?** If yes, the seed may be affected and the report must
   say how that was checked.

## 5 · Report

One issue per mechanism, not per symptom. Four symptoms sharing one broken store are one issue; two
symptoms with different root causes are two, even if they look alike.

Every issue carries: the reproducer, the measured table with both compilers, the mechanism (GAS or the
source line), the gate-blindness explanation, acceptance criteria including the controls that must keep
passing, and an explicit out-of-scope list. Label by class (`wrong-value`, `fails-when-valid`,
`diagnostic`), and add `priority-0` only for a clean compile that returns a wrong answer.

Do not add `needs-info`: a probe report that cannot be implemented from what it contains is not finished.

When a measurement in an existing issue no longer reproduces, post the correction there rather than
opening a duplicate. When your own earlier report turns out to be wrong, correct it publicly and rename
the issue if its title carries the error.

## 6 · What probe may not touch

- `src/`, `lib/`, `test/`, and the three oracles (`scripts/corpus.manifest`, `scripts/idiom.baseline`,
  `scripts/needle.baseline`) — probe reads them and never writes them.
- Commits, pushes, branches, pull requests, and merges.
- The `in-progress` label. Probe does not claim issues; it has nothing to claim. An issue already carrying
  a claim may still be *measured*, but the finding goes in a comment, never in a competing issue.
- `needs-info` on someone else's hold. Probe reports evidence; routing is research's job.
- Any issue where the required next step is an owner decision. State the decision needed and stop.

## 7 · Coordinate

Before acting: fetch, then check open pull requests and `in-progress` issues. If a probe finding overlaps
work already in flight, comment on that work instead of opening an issue.

After a self-promote lands, re-run the classes that promotion touched. The layout wave produced three
regressions that a green gate did not catch, and they were found by exactly this: probing the classes the
wave changed, against the pre-wave seed.

A probe run ends with a short summary: the class chosen, how many forms were measured, what was found,
and what was measured and found correct. The second half matters — recording that a class is sound is
what stops the next probe re-measuring it.
