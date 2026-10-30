# Gates — what they prove

What each check proves and does not, the evidence rules, and the docs-only gate in full.

Moved verbatim from `AGENTS.md` (#1130). `AGENTS.md` states each rule briefly; this file is the full
text, with the reasons, measurements and history. Line citations are as of the move.

## What the gates prove

No single check is sufficient:

- Fixpoint and one-input GAS comparison do not prove behavior for shapes absent from the input tree;
  the per-file corpus manifest catches that class.
- `fmt_corpus.sh` is required because formatting can silently rewrite source; it checks both programs
  and compiler/library modules and must not rewrite them automatically.
- `idiom_gate.sh` reports duplicated decisions and is reporting-only; its reviewed baseline is an oracle,
  not permission to ignore a new finding.
- `wildcard_arm_check.sh` refuses a new unacknowledged `_ =>` arm over an **enumerable** scrutinee,
  and it is an addition rule rather than a limit because the two directions were measured and are not
  symmetric. Over a project `enum` the variant list is something a later commit extends, and a
  spelled-out group arm turns that extension into a located `check` error where a `_` absorbs it
  silently. Deleting an existing `_` is the expensive half: #544's census measured that in **249 of
  727** cases the deletion is invisible — `check` 0, `build` 0, and a `match` with no arm taken
  returns −1 at run time (`run rc=255`) with no diagnostic — so the tree's existing arms are removed
  by hand, one file at a time, by `.agents/skills/alatyr-lane/wildcard_enumeration.md`. Preventing a
  new one costs the author nothing; that asymmetry is the whole design. Over an integer or a byte `_`
  is legitimate and exempt (the census found **4** tree-wide), as is a `comptime match typeinfo(T)`
  kind dispatch; both exemptions are decided from the scrutinee's resolved type, never from the arm's
  text, and both are counted in the verdict line rather than silently dropped. The check holds **no
  oracle file**: like `corpus_enum_check.sh` it compares two things the repository already contains —
  the merge base and the head — so there is no fourth committed number to regenerate or drift. It is
  also the reason the count is parsed rather than grepped, and the error runs in both directions:
  `src/parser.al` holds 24 real arms against 27 `grep -c '_ =>'` hits — three are band comments
  quoting the token in prose — while `grep -cE '^\s+_ =>'` answered 4 for `src/lower_ctx.al`'s 24,
  because twenty sat inline in one-line accessors. The scanner reproduces #544's independent census
  to the unit: 727 over `src/` at `6759a95` and 731 at `6fe1e1d`.
- `strict_forms_check.sh` holds the "Strict forms" above with the wildcard check's design: a merge-base
  delta, per rule, with no oracle file, refusing only an unacknowledged addition. Its lexical half
  (`unchecked`, `kind-literal`, `try-inline`) is a tokenizer run before the build. Its typed half
  (`ptrint`, `null`) runs after the build and reads the #529 checker instrument on fd 98, because only
  the checker knows `p` in `p == 0` is a pointer. `null` is decided on explicit plus implicit forms
  together, so #529's conversion of one into the other is never refused. If the head compiler refuses
  the *base* tree (a checker-tightening change can do that), the implicit half is reported as
  SKIPPED, never counted as zero.
- `seed_forms_check.sh` runs the seed-forms registry after the build. A `seed` row needs the tree
  compiler to answer the due value and the frozen seed not to. So a promotion that fixes a form turns
  the gate red and names the workaround sites to remove, and the registry retires itself. A `tree`
  row is a tree defect that was blamed on the seed; it fails once fixed, until it moves to `seed`.
- The whole-program invariant checks and cross-target sweeps need non-vacuity tests; a green gate that
  never fails its own planted defect is not evidence.
- `build_reject` proves only a nonzero exit. Use `build_reject_has` for an intended diagnostic, and do
  not put a searched needle in its own fixture header. Reject fixtures do not by themselves prove that
  every non-x86 surface rejects.

## Evidence rules

- Every behavior or executable-workflow change owns a focused regression that fails on the parent
  before the fix. Inert prose has no runtime behavior to make fail first; it instead owns complete
  diff, mode, reference, and formatting evidence under the docs-only gate.
- For a refactor, compare byte-identical output with the input tree held fixed and use the corpus oracle.
- Verify the measurement method independently: check exit status outside pipelines, use absolute compiler
  paths where fixtures change directory, and verify behavior rather than a symbol's presence.
- A trap is acceptable; a wrong value is not. If correctness cannot be completed, leave a located reject.
- Cross-backend fixtures return below 126; exit codes are modulo 256, so large values need a second check.
  When two commands claim the same result, make them agree (`alatyr run` versus build and execute).
- Before creating a file, inspect `git log -- <path>` so an existing stronger fixture is not overwritten.

## Gates

- `nix develop -c bash scripts/dev.sh` is the fast loop. `nix develop -c bash scripts/full.sh` is the
  authoritative compiler gate and must be green before publish for every change outside the narrow
  docs-only class, whether it runs on a native x86_64 machine or as `.github/workflows/gate.yml`
  (above). An emulated x86_64 (Rosetta, QEMU user mode) is not a gate machine: measured on the
  2026-09-29 integration, the same object that matched on native hardware showed 89 `NO-LONGER-RUNS`
  and 48 `OUTPUT-CHANGED` x86_64 rows under QEMU — timeouts and emulation artifacts, not behavior. A feature-only PR with an intentional oracle
  transition may use the first non-green run only to document the expected oracle mismatch; the final
  merge plus maintainer oracle commit must pass the complete gate before publish.
- The full gate covers fixpoint, e2e, corpus, formatter, duplicate-decision, wildcard-arm, strict-form,
  seed-form, invariant, and cross-target checks; an individual green check is never sufficient.
- The docs-only gate is available only when
  `.agents/skills/alatyr-lane/classify_docs_only.sh <base> <head>` accepts the complete committed range
  and both worker and integrator independently inspect every hunk. Its allowlist is regular,
  non-executable `README.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, and `docs/**/*.md|txt`.
  Changes to `AGENTS.md`, `.agents/**`, `.github/**`, source/library/tests/scripts/seed/package
  files, modes, symlinks, submodules, deletions, generated or tool-consumed text, executable examples,
  or normative language/build/release/security/permission behavior require the full gate. Uncertainty
  means full gate.
- A docs-only pass requires the raw diff and modes, every hunk, local references and cited anchors,
  `git diff --check`, and clean tracked and staged trees. Integration reclassifies the merged range
  using the classifier from the trusted base and preserves the same snapshot, lease, exact-object,
  claim-release, and acceptance-record rules. A mixed batch always uses the full gate.
- A non-x86 emission change runs the cross-target sweeps; `--force-sweeps` overrides the change filter.
- The detailed execution order, safety review, branch cleanup, and acceptance comment are defined by
  `alatyr-lane` and `alatyr-integrate`.
