# Contributing to the Alatyr compiler

The short version: **the specification decides, this repository implements, and the gate is the
referee.** A change that the gate cannot vouch for is not finished, however obviously correct it
looks.

## The sources of truth, in priority order

1. **The [specification](https://github.com/alatyr-programming-language/spec)** — invariants,
   decisions, chapters. Authority runs one way and does not reverse: the toolchain conforms to the
   spec, never the other way round.
2. **`scripts/full.sh`** — what the implementation actually does today. When the code and a comment
   disagree, the gate says which one is lying.
3. **The open [issues](https://github.com/alatyr-programming-language/compiler/issues)** — what
   remains, with the measurements behind it. Larger multi-stage plans live in Discussions.
4. **`AGENTS.md`** — how to work here: what each gate can and cannot see, what counts as evidence,
   and the traps that have already cost somebody a day.

If you find that the spec does not answer a question you need answered, **stop**. Do not invent
semantics and do not infer them from the current behaviour: open an issue against the specification,
get it decided there, then implement. That rule is why this compiler can claim conformance at all.

**Which revision, and how to cite it.** This tree implements spec revision **1.1.0** (tag `v1.1.0`,
`65a0c9be0ad27c3e2b9ed622634ded38d3ddf7e9`). The pin names a **tagged release**, never a moving branch
head; `AGENTS.md` carries the full pin and moves it in its own commit, `src/spec_revision.al` is the
constant the compiler bakes, and `alatyr version` prints both numbers (Tooling §4 / TOOL-21, #1000). The
spec's citation anchors are theme-prefixed — `FND-*`,
`TYP-*`, `MOD-*`, `TOOL-*`, `CG-*`, `CF-*`, `CT-*`, `FN-*`, `MEM-*`, `OP-*`, `SYN-*`, `STD-*`, `CC-*`,
`PRIN-*` — and a new comment or issue cites one of those, or an issue number.

Nothing in this tree cites anything else. The flat `D`-number scheme the spec retired and the section
anchors into an unpublished planning document have both been removed, not annotated — `AGENTS.md` says
which three were recovered by meaning. What looks similar and is NOT a citation is `CLAYOUT S3(b)` and
its siblings: in-code tags that group the sites of one sub-problem so a single `grep` finds them all.

## Spec decisions awaiting implementation

Nothing in this list is an open question. Each contract is **decided** in the specification; what
remains is implementation, and it is tracked in the issues. The list exists so that a contributor does
not reopen a settled design, and so that "the spec is silent here" is not assumed when it is not.

| contract | what is settled | where the spec says it |
|---|---|---|
| `TYP-13` | a float-spelled literal never initialises an integer type; an integer literal in a float context is accepted exactly when exactly representable | Types |
| `TYP-3` / `TYP-7` | the default `struct` layout already coincides with the platform's C layout; the closed levers are the only departure, and a `[T]`/`str` view is the two-word pair **wherever** it appears | Types §6.1/§8, §7 |
| `MOD-10` / `MOD-11` / `TOOL-8` / `TOOL-9` | the dependency graph, lockfile format, lock modes, workspaces | Modules, Tooling |
| `MOD-13` | the executable/object/library/source emission table; library artifacts exclude the package entry | Modules |
| `MOD-14` | `Dependency.name` is the sole required local namespace name — there is no `alias` field or fallback, and the name never participates in source identity or the lockfile | Modules |
| `TOOL-6` | the incremental-build contract: a module is the unit of separate compilation, one interface hash, an output-neutral cache | Tooling |
| `TOOL-12` / `FN-12` | `Target.entry` is an Alatyr path whose derived or exact-export symbol is passed to the linker; a missing declaration is a Codegen diagnostic | Tooling, Functions |
| `TOOL-17` | manifest-only structures are not source names; configuration enums are ordinary prelude names; `check` stops after semantic analysis and emits no artifact | Tooling |
| `TOOL-18` / `TOOL-19` | platform shape is stated by `Machine`, not a flat triple; non-ISA backend facets are additive and cannot be inferred | Tooling, appendix — per-arch |
| `TOOL-20` | `plan` / `--plan` emits deterministic TSV records as output only; install paths are derived | Tooling |

Three contracts that were once divergences are **implemented and gated**, and should not be reopened:
`TOOL-14` manifest selection, the `TOOL-16` withdrawal of vendoring (there is no `vendor_dir` field and no
`--vendor-dir` flag — the implementation must *reject* the withdrawn surface, not accept and ignore it), and
`MOD-8` root-module duplicate checking.

Deliberately **post-v1**, and therefore not tracked as work here: a registry with version constraints
(`MOD-7` — v1 selects by path or git revision only), vendoring (`TOOL-16`), multi-package workspaces
(`TOOL-9`'s `members` field is removed from v1), `async`/`await` and fibers (`CC-5`/`6`/`7`), and the general
newline-continuation surface (`SYN-4`).

## The one invariant that outranks everything

**Correct, or loudly wrong. Never quietly wrong.** A trap is acceptable. A located reject is
acceptable. A missing feature is acceptable. A program that compiles cleanly, runs to a normal exit
and produces the wrong answer is the single forbidden outcome, and most of the machinery in
`scripts/` exists to hunt exactly that.

This is why several fixtures in `test/` assert a *trap* or a *rejection* rather than a result: they
are not aspirational, they pin the loud failure in place so it cannot decay into a silent one.

## Before you change anything

```sh
nix develop
./scripts/full.sh --force-sweeps
```

Roughly 6 minutes. If it is red before you start, say so in your issue or PR rather than working on
top of it — a red baseline makes every later measurement meaningless.

## What makes a good issue

The best issues here are **measurements**, not impressions. A defect report that lands well has:

- **A minimal program.** Not the file you were writing — the smallest thing that still misbehaves.
  Ten lines beats two hundred, and the act of shrinking it usually identifies the real axis.
- **What you expected, what you got, and how you know.** Exit codes truncate mod 256, so if the
  answer matters, put the comparison *inside* the program (`if v != 42 { return 1 }`) rather than
  reading the exit code and trusting it.
- **Which backend.** `x86_64` is the sound one; `aarch64`, `riscv64` and `wat` are narrower by
  design, and "it traps on wasm" is often expected rather than a bug. Say what all four do if you
  can — one of them disagreeing with the others is itself the finding.
- **Whether `check` agrees with `build`.** They are supposed to answer the same question; when they
  do not, that gap is usually more interesting than the symptom that led you to it.

A wrong value on a clean compile goes to the top of the queue regardless of how obscure the shape
looks. Everything else is triaged by what it blocks.

## Working on a change

- **One unit of work per branch**, and the flow is the ordinary one: an issue → assign yourself →
  a branch → a pull request. Assigning the issue is how everyone else knows the work is taken; there
  is nothing else to declare. For ordinary files a merge conflict is a perfectly good signal, and the
  reason to avoid one anyway is not that merging is hard — it is that re-establishing which
  measurement belongs to which state is.
- **The three oracle files are the exception**: `scripts/corpus.manifest`, `scripts/idiom.baseline`
  and `scripts/needle.baseline` are line-oriented, so two branches regenerating *different* rows would
  merge clean into a file that is the output of neither compiler. `.gitattributes` marks all three
  `-merge` so git refuses instead, and by convention at most one open PR touches them, in a commit
  that touches nothing else. `scripts/land.sh` refuses a PR that mixes one with anything else. A
  feature PR that moves the corpus manifest does not touch it at all: it declares the shift instead
  (see "An intentional behaviour change" below).
- **The fixture comes first, and it must fail.** A test that passes before your fix proves nothing
  about your fix. Put the measured pre-fix outcome in the fixture's header, in words: `built rc 0 and
  ran to 0 where 42 was due` is evidence; `was broken` is not.
- **Keep needle strings out of fixture comments.** The gate's `*_has` helpers grep the whole file, so
  a header that quotes the string its own assertion searches for makes that assertion pass on an
  unfixed compiler. This has happened twice.
- **A user-visible change carries its `## Unreleased` line in the same commit.** Same reasoning as the
  fixture: written while you still know what you measured, not reconstructed at release time from a
  log. Whether yours is user-visible is already decided by the PR's **Kind** block — the first four
  boxes are, the last two (`gate or tooling only`, `refactor with no behaviour change`) are not, and
  `CHANGELOG.md`'s own policy says why a change under `scripts/` moves nothing. Do not restate the
  Kind in the entry; write the one sentence a person deciding whether to upgrade would want, and let
  the version bump follow from the policy at the top of `CHANGELOG.md`.

## What the gate consists of, and why each part exists

| stage | what it can see that nothing else can |
|---|---|
| `fixpoint.sh` | the compiler still reproduces itself byte for byte — `seed == Stage1 == Stage2` |
| `e2e.sh` | ~1750 rows of behaviour, x86_64 and the three cross backends |
| `corpus_manifest.sh` | a committed oracle: every tracked fixture × 4 backends, exit + stdout + stderr. **The only gate that sees a backend behaviour change**, because the fixpoint compares the compiler against itself |
| `fmt_corpus.sh` | a silent source rewrite — `alatyr fmt` has no fail-loud channel, so a wrong rendering exits 0 and hands back the wrong program |
| `idiom_gate.sh` | one decision living in N copies, which is how most defects here were born |
| the vacuous-needle check | a `*_has` assertion whose needle sits in its own fixture's header, so it cannot fail. The reviewed debt is `scripts/needle.baseline`; the banner's count must not grow |
| the sweeps | a program that compiles and runs to a normal exit with the wrong answer on a cross backend |

Two rules about the oracle, and they are not negotiable:

- `scripts/corpus.manifest` is regenerated **only** by a human who has read the diff, in its **own
  commit**, with the row transitions accounted for in the message. Blessing an unreviewed
  regeneration destroys the only thing that makes it an oracle. The same holds for
  `scripts/idiom.baseline` and `scripts/needle.baseline`.
- Compare it by joining on `(backend, path)`, not by reading the diff top to bottom. Added and
  removed rows do not pair up, and a positional read misaligns and invents transitions that are not
  there.

## An intentional behaviour change

If your change is *meant* to move `scripts/corpus.manifest` (a fixture now runs, an exit code is
now the right one), the PR declares that move in `scripts/corpus.expected-delta`, and the manifest
itself stays untouched. The gate then checks that the fresh manifest differs from the committed one
by **exactly** the declared rows. No undeclared pair, no unrealised one, and every value matches
down to the stream hashes. That single green gate is enough to land the feature together with its
oracle commit.

1. Get a fresh manifest from a **native x86_64** walk of your branch: run
   `scripts/corpus_manifest.sh --check` there (it leaves `target/corpus-manifest/corpus.manifest`), or
   download the `corpus.manifest` artifact of a `.github/workflows/gate.yml` run. An emulated x86_64
   gives different values, and they will not match the maintainer's gate.
2. Write the delta with the helper. Do not write it by hand:

   ```sh
   scripts/corpus_manifest.sh --emit-expected scripts/corpus.manifest \
     target/corpus-manifest/corpus.manifest > scripts/corpus.expected-delta
   ```

   It refuses a `TIMED-OUT` row and an empty delta. Its comment lines count the rows per class.

   **A `TIMED-OUT` row is never a declaration of intended behaviour.** A timeout is a measurement
   that did not finish, not a result: on a contended machine a program that runs fine can be recorded
   as timing out, and blessing that row would write a machine's slowness into the oracle as if it were
   the language's behaviour. Re-run on an unloaded native x86_64 until the walk is clean, then emit.
3. **Never write or edit a class by hand — the generator derives it, and it will disagree with you.**
   Measured on the first real run: an author declared `NOW-RUNS` for three pairs whose twins had
   *already been running* and stopped at `brk #0`; a trap is a run, so the transition is
   `EXIT-CHANGED` — "ran before and after, different exit", not "refused → runs". The pairs and the
   exit codes were predicted correctly; the class was not, and care cannot fix that: a class is a
   function of the before/after pair, so it must come from the diff. This is why `--emit-expected` is
   the only writer of this file, and it is a correctness rule, not a style preference.

   Read every row before you commit. They are `--explain`'s joined transitions. A `NO-LONGER-RUNS`
   or a `run → assemble/*` row is a regression you are about to bless, even when it sits among
   twenty wins. Commit the file in the feature PR and list the transitions in the PR description.
4. Check the result yourself. A delta that does not match its own walk is a red gate:
   `scripts/corpus_manifest.sh --check-delta scripts/corpus.manifest target/corpus-manifest/corpus.manifest scripts/corpus.expected-delta`
   must exit 0.

Three things follow from how the delta is checked:

- **A stale delta is rebased for you when nothing you predict moved.** The delta names the manifest
  it was computed against (`base_sha256`). Once `main`'s manifest moves, your delta is *inert*, and
  the gate would want a plain match again. `scripts/land.sh` therefore rebases it at PHASE 2 with
  `scripts/corpus_manifest.sh --rebase-delta` (#1264): when every pair you declare still starts from
  the row `main` now holds, the same rows are carried over and only the two hashes move. The merge
  commit carries that copy; your branch is left alone. When another change moved a row you predict,
  or your change also moves a header line, the rebase refuses and names why: then rebase your branch
  and re-emit. `.gitattributes` marks the file `-merge`, so two feature PRs that both declare one
  conflict instead of merging into a prediction neither of them made; that conflict, alone, is the
  one the landing settles, with the rebased copy.
- **Leave `scripts/xbackend_diff.baseline` alone in the feature PR.** The gate's ratchet reads the
  committed (old) manifest. `scripts/land.sh` runs the ratchet on the new manifest when it writes
  the oracle commit, and a lowered baseline follows in its own commit after that.
- **`scripts/idiom.baseline` and `scripts/needle.baseline` need no delta, and no second gate.** They
  are static text walks — neither runs the compiler — so regenerate them **in your branch, as their
  own commit, before you ask for the gate**, and that one gate covers code and baseline together. The
  delta exists only for `scripts/corpus.manifest`, whose content is produced *by compiling*: you
  cannot know the fresh manifest without doing the walk, and that is the whole of the two-gate cost.

## Pull-request checklist

- [ ] `./scripts/full.sh --force-sweeps` is green, and `git diff --exit-code` is clean **afterwards**
      — the tree the gate ran on did not move. (A clean `git status` alone proves nothing here: if a
      `--write` regeneration was committed on the branch, the status is clean too. What separates the
      two is the commit shape — see the oracle rule above.)
- [ ] A fixture that failed before the change and passes after, registered in `scripts/e2e.sh`.
- [ ] Every number in the description says how it was obtained. "Verify that your measurement
      measures what you named it" is the local proverb, and it was earned the hard way.
- [ ] Emission changed? The GAS delta was measured with the **input tree held fixed**, in both
      directions — otherwise you compared a longer source against a shorter one and proved nothing.
      Normalize the `.L<N>` **and** `.Lra<N>_<k>` label families first.
- [ ] Fixpoint still green. If it is not, a reseed may be owed — that is the maintainer's call, never
      a contributor's, and it needs three-stage evidence.
- [ ] The manifest either matches, or the PR carries a `scripts/corpus.expected-delta` emitted
      against the current `main` and `--check-delta` exits 0 on it (never the manifest itself).
- [ ] User-visible? Then `CHANGELOG.md`'s `## Unreleased` gained its line, in this same commit.

## How your change lands

**There is no CI.** Nothing on GitHub runs the gate, so nothing reports a status, and the merge
button is not used. The maintainer merges your branch locally, runs `./scripts/full.sh
--force-sweeps` on **that merge** — not on your branch — and pushes exactly the object that was
gated. Three consequences worth knowing in advance:

- Your PR may sit while a ~6-minute gate runs on something else. Silence after a green PR is not
  neglect.
- You may be asked to rebase when `main` moves, because a gate result belongs to one specific tree.
- An approval is not a landing, and the gate output you paste is a claim the maintainer re-derives.
  That is not distrust: two independently green changes can merge cleanly into a tree whose corpus
  manifest matches neither, and only a gate on the merge can see it.

**If you are opening a PR from a fork**, expect the `scripts/` and `test/` parts of your diff to be
read line by line before anything is executed. The gate compiles and *runs* fixtures — freestanding
programs making raw syscalls, under qemu and wasmtime — and it invokes whatever `scripts/e2e.sh` the
checkout contains. That review is about the execution, not about your intentions.

## Style

Match the file you are in. Concretely: comments explain **why**, and especially why the obvious
alternative is wrong — several of them exist because somebody tried the obvious thing and it silently
broke. Fixture headers record measurements. Commit messages carry the evidence, because the commit is
where a future reader will look for it.

## Licensing of contributions

By contributing you agree that your contribution is licensed under **Apache-2.0**, the licence of
this repository. (The specification repository is dual-licensed because it is prose; this one is
code.)
