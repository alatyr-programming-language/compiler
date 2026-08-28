## What this changes

<!-- One paragraph. What behaviour differs after this, for someone using the compiler. -->

## Kind

- [ ] A **wrong value** fixed — a clean compile that produced the wrong answer now does not
- [ ] A valid program that used to fail now works
- [ ] A failure made **loud and located** where it was silent or unplaced (the program was already
      refused, or should have been)
- [ ] New surface: a construct, a backend shape, a CLI verb or flag
- [ ] Gate or tooling only — no change to what the compiler emits
- [ ] Refactor with **no** behaviour change (the GAS delta is empty, see below)

If you ticked one of the first four, `CHANGELOG.md`'s `## Unreleased` gained its line in the same
commit — the last two are the boxes that deliberately change nothing a user would notice.

- [ ] Changelog line added, or this change is one of the last two kinds

## Evidence

<!--
Every number states how it was obtained. "Verify that your measurement measures what you named it"
is the local proverb and it was earned expensively: measurements here have been wrong because a
fixture header quoted the very string its own assertion searched for, because `$?` was read after an
intervening command substitution, and because a file had moved between the two trees being compared.
-->

> Your numbers are a claim, not a verdict. There is no CI: the maintainer merges this branch
> locally, runs the gate on **that merge**, and re-derives every number below. Say how each one was
> obtained so that re-deriving it is possible.

- **The fixture failed first.** How it failed before, in words and numbers:
- **Per backend, after:** x86_64 · aarch64 · riscv64 · wasm
- `./scripts/full.sh --force-sweeps`:

```
paste the fixpoint line, the e2e proof-of-work line, the manifest verdict and the three sweep triples
```

For an intentional behavior change whose expected result updates an oracle, this feature-only PR must
not contain an oracle file. Instead, state the joined expected transitions or reviewed baseline
findings here and say that the maintainer will create the separate one-file oracle commit after the
local merge; the final complete gate is run on that merge plus oracle commit.

## Checklist

- [ ] For an ordinary change, the gate is green, and `git diff --exit-code` is clean **after** it — the
      tree the gate ran on did not move. For an intentional oracle transition, this feature-only PR
      contains no oracle file, the only expected pre-landing failure is the reviewed oracle mismatch,
      and the maintainer will make the separate oracle commit and run the final green gate after merge.
      (A clean `git status` alone does not prove `--check` rather than `--write`: a committed `--write`
      regeneration leaves the status clean too.)
- [ ] A fixture registered in `scripts/e2e.sh` that **fails on the parent commit**. Not a fixture
      that merely passes now.
- [ ] `scripts/e2e.sh`'s vacuous-needle banner did not grow. (The check is mechanical now — this
      box is here so you read the banner, not so you assert it.)
- [ ] Emission changed? The GAS delta was measured with the **input tree held fixed, in both
      directions**, with `.L<N>` and `.Lra<N>_<k>` normalized. Comparing your tree against the old
      one compares a longer source with a shorter one and proves nothing.
- [ ] Fixpoint green. A reseed, if one is owed, is the maintainer's act and needs three-stage
      evidence — say so rather than doing it.
- [ ] The corpus manifest matches for an ordinary PR, or the expected transition is explained here and
      the maintainer will regenerate it in a separate one-file commit after the local merge. The
      message for that commit carries the `scripts/corpus_manifest.sh --explain` output verbatim (it
      joins on `(backend, path)` and separates severity classes; reading the raw diff positionally
      invents transitions that are not there). The same separate-commit rule covers
      `scripts/idiom.baseline` and `scripts/needle.baseline` — three oracle files, all `-merge`; no
      feature PR mixes an oracle.
- [ ] A spec question was answered in the specification first, not inferred from current behaviour.

## Related issue

<!--
Use `Closes #…`, `Fixes #…`, or `Resolves #…` when this PR completes the whole issue.
For an explicitly bounded slice of a larger issue, use `Refs #…` and state in the PR body what this
PR completes, what remains, and why the issue stays open.
-->
