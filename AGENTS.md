# AGENTS.md — the Alatyr compiler

This is the **canonical** Alatyr compiler: it is **written in Alatyr** and compiles itself to a
byte-for-byte reproducible binary (the TOOL-1 fixpoint). It has **no Rust** — the Rust ancestor that
bootstrapped the first self-host binary is frozen and not published; `seed/VERSION` records the
lineage and how the seed is replaced today (a self-promote, not a rebuild from that ancestor). The
language is defined by the **[specification](https://github.com/alatyr-programming-language/spec)**
— the source of truth for invariants, decisions and chapters. Authority runs one way: the toolchain
conforms to the spec, never the reverse.

**The pinned spec revision.** This tree implements spec revision **1.0.0** — tag `v1.0.0`,
`4e46f0489ffddb8060d87451ed3aa65c15646885` — with the post-tag editorial commits up to spec `main`
`5cf3af57efa1122f130465f5bb9ddcb22c6dc188` (one of which moved the standard library into THIS
repository, which is why `lib/` ships here). Cite that pin when a change turns on what the spec says;
if the spec has moved past it, the pin moves in its own commit, never silently inside a feature.

**How a spec citation is spelled, and three vocabularies that are NOT one.** The spec's citation
anchors are **theme-prefixed**: `FND-*`, `TYP-*`, `MOD-*`, `TOOL-*`, `CG-*`, `CF-*`, `CT-*`, `FN-*`,
`MEM-*`, `OP-*`, `SYN-*`, `STD-*`, `CC-*`, `PRIN-*`. Those resolve. Two other families appear all over
this tree's comments and resolve NOWHERE:

- **flat `D<N>`** (`D9`…`D99`, ~31 distinct) — the pre-1.0 numbering the spec replaced. It left no
  old→new map, so these are readable only as history. Three were recovered and are used in their new
  spelling here: `D75` → **TOOL-3** (the manifest is a single `Package` value), `D69` → **FND-1**
  (spec-first: decide, then write), `P1-CLAYOUT` → **TYP-3**/**TYP-7** (layout primitives + the closed
  per-site levers).
- **`ROADMAP §N` and `P1-*`** — anchors into an internal planning document that is not published, and
  internal priority IDs from it. They stay as historical markers in code comments; `seed/VERSION` is
  append-only and keeps them by rule.

So: a NEW comment cites a theme-prefixed spec ID or an issue number. An OLD comment citing `D42`,
`ROADMAP §8.2` or `P1-BYTES` is a historical note, not a pointer you can follow — do not add more.

## Layout

- **`package.al`** — the manifest (one `Package` value, TOOL-3): `source_dir = "src"`, `target_dir =
  "target"`, the x86_64 target (`output = "alatyr"`), and the root module's `_start`.
- **`src/`** — the compiler, one module per file (a module's name is its file stem; modules live by
  path under `source_dir`). Dependency tiers: `ast` → `rt`/`lexrt` → `comptime`/`sema`/`lower_layout`
  → `parser` → `lower` → `driver` → `cli` → `main`. That spine is not the whole set: alongside it sit
  `iface`, `regalloc`, `lower_asm`, `lower_attrs`, `lower_ctx`, the ten modules under `src/lower/`
  (`abi_c`, `assign`, `collect_slots`, `ctfold`, `decl_index`, `enum_match`, `fnval`, `ir`, `mono`,
  `place`), the `fmt` renderer, and the three non-x86 backends `aarch64`, `riscv64`, `wat` — 30
  modules in all. Read `ls src src/lower` rather than this list when it matters.
- **`lib/`** — the standard library (`.al`), shipped WITH the compiler and injected ambiently (the
  `std`/`alloc` roots + prelude; STD-1). Not a dependency, not vendored — like Rust's `library/std`.
- **`seed/`** — `alatyr`, a FROZEN **static** self-host binary (the bootstrap; honors
  `source_dir`, raw syscalls so it links static → portable for CI). `VERSION` records the
  provenance of each promotion — the ancestor commit the lineage began from, and every self-promote
  since, with its three-stage hashes.
- **`target/`** — build artifacts (gitignored; the spec `target_dir`).
- **`test/`** — the fixture corpus: 1663 tracked `.al` files (flat programs plus multi-file
  package fixtures under `test/package/`), driven by `scripts/e2e.sh` and hashed by
  `scripts/corpus.manifest`. The reproducibility gate is `scripts/fixpoint.sh`.
- **`scripts/fixpoint.sh`** — the TOOL-1 reproducible-build check (seed == Stage1 == Stage2).
- **`scripts/e2e_fast.sh`** — fast iteration runner over the e2e table (parallel, optional name
  filter, Stage1 rebuilt only when stale); `scripts/e2e.sh` stays the authoritative gate.

## Building

Inside `nix develop` (provides `as`/`ld`):
- **Build the compiler:** `seed/alatyr build package.al` → `target/debug/alatyr` (Stage1). Then
  `target/debug/alatyr build package.al` rebuilds it with itself. The `debug` component is the
  default build profile (`--release` selects `release`); `scripts/fixpoint.sh` accepts either that
  path or the legacy `target/alatyr`, so a stale doc reads as a missing file rather than a failure.
- **Reproducibility gate:** `./scripts/fixpoint.sh` — MUST print the fixpoint line after any `src/`
  edit. If it reports `seed != Stage1`, the committed seed is stale vs `src/`, and the recovery is a
  **self-promote**, not a rebuild from the frozen Rust ancestor (that ancestor can no longer parse the
  current `src/` — `seed/VERSION`'s 2026-08-19 entry records where it stopped being able to). Build
  Stage1, have it build Stage2 and Stage3, require `Stage1 == Stage2 == Stage3` in both the GAS and the
  binary, read the seed→Stage1 GAS delta line by line with the `.L<N>` and `.Lra<N>_<k>` label families
  normalized first, then copy Stage1 over `seed/alatyr` and append that evidence to `seed/VERSION`.
  Promoting is the **integrator's** act, never a lane's.
- **The compiler's CLI:** `alatyr <files>` (emit GAS) · `-o <out> <files>` · `run` · `check` ·
  `test` · `new <name>` · `build <pkg>/package.al` (manifest → `target_dir`/`output`).


## Working rules

- Decide language questions in the [specification](https://github.com/alatyr-programming-language/spec)
  FIRST (never invent semantics); implement here against the pinned spec revision. A `src/` change that
  isn't reproducible (`fixpoint.sh` red) is not done.
- The self-host lower has known idiom limits (bind a `deref(<call>)` field to a local where flagged,
  etc.); match the surrounding code.
- The **highest-conflict files** are `src/lower.al` (and now `src/lower/*.al`), `src/cli.al`,
  `src/driver.al`, `src/parser.al`, `src/sema.al`. Two changes editing one of these at the same time
  is the expensive case — not because merging is hard, but because re-establishing which measurement
  belongs to which state is.
- **`git stash` is forbidden.** It is a repo-wide ref: two lanes stashing at the same moment swap each
  other's uncommitted work (this happened). Need a clean tree to measure a baseline? Use a throwaway
  worktree at the base sha.
- **Fixed paths in `/tmp` are shared.** `scripts/full.sh` writes its logs into the checkout's own `target/`
  for this reason. Anything you add must do the same.
- **Run everything with `ulimit -c 0`** — fail-loud traps drop 8 MB core dumps.
- **Never run two target-producing gates in the same checkout**, and never move a built compiler out
  of a directory that has `../lib` beside it: `lib_dir` is `dirname(/proc/self/exe)/../lib`, so the
  stdlib injection silently disappears. When you need an isolated tree, derive its path rather than
  naming one (`git worktree add --detach "$(mktemp -d)" <base>`); budget ~150 MB per live tree.

## How work reaches `main`

One unit of work at a time, and the flow is ordinary GitHub:

**an issue → assign yourself → a branch → push → a pull request → the maintainer gates it locally and
lands it → the issue closes itself** (the merge commit carries `Closes #N`).

Assigning the issue *is* the claim: there is no separate register to update, and no announcement to
send afterwards, because the pull request exists from the first push. Two conventions and no more:

- **The oracle files are exclusive, and there are THREE of them.** At most one open pull request may
  touch `scripts/corpus.manifest`, `scripts/idiom.baseline` or `scripts/needle.baseline`, and it
  touches nothing else. For every other file a merge conflict is the signal, and it is a good one. For
  these three it is not: they are line-oriented, so two branches regenerating DISJOINT rows would merge
  clean into a file that is the output of neither compiler. `.gitattributes` marks all three `-merge` so
  git refuses instead — and even then, a second regeneration's rows can be semantically wrong while
  merging textually clean, which is why the exclusivity is a rule and not only an attribute.
  `scripts/land.sh` enforces the same three, both as a commit-shape check and as a post-gate assertion;
  `needle.baseline` is the one that used to be named in the script and nowhere else.
- **The gate runs on the merge, not on the branch.** The maintainer merges your branch locally, runs
  the authoritative gate on *that* object, and pushes exactly what was gated. So the GitHub merge
  button is not used, an approval is not a landing, and you may be asked to rebase when `main` moves.
  There is no CI: nothing reports a status, and the numbers that decide anything come from the gate,
  never from a pull-request body.

The step-by-step procedures — taking a unit of work, and landing one — are the `alatyr-lane` and
`alatyr-integrate` skills in `.agents/skills/`. Everything below this line holds whatever you are
doing, which is why it is here and not there.

## Measurement traps

Two ways a green gate has lied, both worth reading before you trust one.

**A fixture for the NEW form does not test the OLD one.** When a lane widens a set — a new operator, a
new place form, a new type — its fixtures naturally exercise the new members, in isolation, and pass. The
break lives at the SEAM: the compound-assignment lane added `%= &= |= ^=` and every fixture using them
alone was green, while `x &= 58` followed by `x = 1` on the same local was REJECTED as a type mismatch,
because `Stmt.Assign` erases declaration-vs-reassignment and the three source-scan recoveries that
reconstruct it still listed only the four old operators. Probe the new member next to an old one, in both
orders, before believing a green gate. The same reasoning names the general hazard: when one fact is
recovered by scanning the source in more than one place, widening the language widens every copy, and
`grep` for the other copies is part of the fix, not a follow-up.

**Verify, do not trust.** A lane's report is evidence, not proof — re-run its repro yourself and probe a
form it skipped, because a lane reports to whoever briefed it and that may not be you. One lane's `reject_`
fixture failed on the pre-fix compiler for an unrelated reason ("unbound name"), so registering it as a bare
`build_reject` would have passed before the fix and proved nothing; it went in as `build_reject_has` with the
real diagnostic instead. That check exists only if the integrator does it.

## What each gate can and cannot see

Treat the gates as a hierarchy with known blind spots, not as one verdict:

- `scripts/fixpoint.sh` proves the seed reproduces the tree. It is **blind** to any defect whose shape does
  not occur in `src/` — it stayed green while the compiler miscompiled array-of-tuple code.
- A tree-level `cmp` of the emitted GAS proves a refactor changed no output **for this one input**. Same
  blind spot.
- The **per-file corpus manifest** (sha of stdout+stderr+exit for every `test/*.al` × 4 backends) is what
  catches that class. For any refactor of a large emitter it is mandatory, not a second opinion. It is now
  a committed baseline — `scripts/corpus.manifest`, checked by `scripts/corpus_manifest.sh --check` on
  every `scripts/full.sh` run: an INTENTIONAL behaviour change owns a reviewed `--write` regeneration in
  its own commit (a mismatch is otherwise a regression, and blessing one unreviewed erases the oracle).
- `scripts/fmt_corpus.sh` is the only gate that can see a **silent source rewrite**: `alatyr fmt` has no
  fail-loud channel for a wrong rendering, so it exits 0 and writes the wrong program. It runs TWO walks,
  both in `scripts/full.sh` — `test/*.al` as PROGRAMS (`run(fmt(x)) == run(x)` and `fmt(fmt(x)) == fmt(x)`)
  and `src/*.al`+`lib/*.al` as MODULES (idempotence only; a module has no `_start`, so there is nothing to
  run). The module walk exists because the program walk was blind to it: `fmt` was non-idempotent on six of
  the compiler's own modules while every gate stayed green, and on the `deref(p) = v` shape the reparse
  dropped the STORE. Each walk has its own reasoned ALLOW table and prints its own coverage line; an ALLOW
  entry that stops occurring is reported `allow-unused` and does NOT fail, so fixing one is not punished.
- `scripts/idiom_gate.sh` is the **duplicate-DECISION** detector — `fmt` settles spelling and structurally
  cannot see "three copies of one table", which is the class that actually produced defects here (the `op=`
  source scan in three copies rejected a valid program; `return 0`-after-flush in three-plus copies became
  two defects). REPORTING ONLY, never rewriting — automatic rewriting is exactly how `fmt` dropped stores —
  and it fails only on a finding absent from the reviewed `scripts/idiom.baseline`. Regenerating that
  baseline is an INTENTIONAL act owed its own commit, like `scripts/corpus.manifest`; expect an extraction
  lane to need one, because a new shared helper is an (N+1)th copy until the copies it replaces are gone.
  It ships a gate-of-the-gate (five planted defects, one per rule, plus a clean twin) and needs no compiler.
  Its `stale` report means **safe to delete** — which for TABLE/SCAN is a repair, not a given. The NEW rule
  is monotonic (a reviewed score of 6 suppresses an observed 4 for the same pair, because it reads the
  MAXIMUM per pair), so a reviewed CEILING used to be reported stale while it was the only thing keeping a
  live lower-score observation out of NEW — and repaying that "debt" turned the gate red. Measured here:
  dropping all 16 reported entries unmasked one finding. The report now withholds a load-bearing ceiling,
  and the gate-of-the-gate asserts that it does.
- `scripts/callee_module_check.sh` and `scripts/type_module_check.sh` are whole-program invariants over the
  emitted GAS. Each ships with a gate-of-the-gate (a synthetic input that must fail) because an invariant
  nobody has seen fail is decoration. One of them silently inspected 18 of 25 instances until a non-vacuity
  assertion was added.
- `build_reject` only asks for a nonzero exit — a fail-loud **accident** satisfies it. When the intent is a
  specific diagnostic, use `build_reject_has <name> <needle>`.
- The **vacuous-needle check** inside `scripts/e2e.sh` is the gate on the gate above: a `*_has` needle that
  appears in its OWN fixture's `##` header cannot fail, because the helpers grep the whole artifact and
  `fmt_test` separately asserts comments survive a reformat. It refuses a NEW one at record time; the 20
  pre-existing rows are the reviewed debt in `scripts/needle.baseline` (the third oracle), reported as a
  banner on every run. An entry that stops occurring is reported and does NOT fail, so repaying one is not
  punished. Read the banner's count: if it grew, a lane grandfathered an assertion that proves nothing.
- The sweeps forbid a silent miscompile; they do **not** assert that a `reject_*` fixture is rejected.

## Evidence, per commit

- A focused regression that **fails first**. Read the fixture's own source for its expected value — the
  corpus convention is 42 but it is not a rule, and treating a correct 10 or 142 as a failure wastes a cycle.
- For a refactor: byte-identical emission with the **input tree held fixed** (build the baseline in a
  throwaway worktree and run both compilers over *that* tree), compared with `cmp`, plus the corpus manifest.
  Never move a built compiler out of its directory — `lib_dir` is `dirname(/proc/self/exe)/../lib` and the
  stdlib injection silently disappears.
- A trap is acceptable; a wrong value never is. Where correctness is unreachable, leave a **located** reject.
- **Verify that your measurement measures what you named it.** Four times in one session a conclusion was
  wrong not in substance but in method: a function-size scan whose pattern silently skipped every `pub`
  declaration (so a 2 971-line function read as "already decomposed"); a package test handed a RELATIVE
  compiler path, which failed inside a fixture's own directory and looked like a regression; an exit code
  eaten by a pipeline (`| tr`), reported as the program's; and `fmt`'s output counted in the *input* file
  because the run had redirected stdout to `/dev/null`. When a number decides something, get it a second,
  independent way before acting on it.
- Verify **behaviour, not the presence of a symbol.** Twice in one session a branch was judged live or dead
  by grepping for a function name, and twice the judgement was wrong — once nearly restoring a guard that
  would have rejected working programs.
- Before creating a file, `git log -- <path>`: a lane overwrote a stronger existing fixture that way.

## Cross-cutting rules learned the hard way

- **A trap is acceptable; a wrong value is not.** Where a fix cannot be completed, stop LOUD.
- **Narrow the gate, then widen.** A broad lowering fix regressed ~90 stdlib tests once; the fix that shipped
  fired only on the exact new shape.
- **Cross-backend agreement is the real proof.** A fixture returning the same value on two independent backends
  is worth more than any single-backend green.
- **Cross-backend fixtures must return < 126** — WASI `proc_exit` rejects anything else and wasmtime's host
  abort is indistinguishable from a failure.
- **Exit codes truncate mod 256, which both false-alarms AND masks bugs.** When a value can exceed a byte,
  verify it a second way (a comparison inside the program), not only by exit code.
- **When a tool offers two paths to the same answer, test that they AGREE** (`alatyr run` vs build+execute).
- **A fixture can encode a bug**; when a fix breaks a test, first ask whether the test was locking in the bug.
- **A "package bug" was a language bug.** The symptom was "declaring a dependency breaks the build"; the cause
  was that a bare CALL as the last statement of ANY nested block (`while`/`for`/`loop` body, `if` branch,
  `match` arm, `unchecked`, `alloc::with`) was emitted as the enclosing function's RETURN — `cx.tail` was set
  per function but `nx == 0` is true at the end of every statement list. A void callee's call vanished
  entirely and the function silently jumped to its epilogue: measured, a void call last in a `while` body made
  a function return 255 instead of 31, compiling clean. The compiler contained **37** such sites in its own
  emission, two of which swallowed real diagnostics. Chase the narrowest reproducer to its lowering arm before
  believing a defect belongs to the subsystem that reported it.
- **Bugs cluster around ONE dropped piece of type information.** The fix is usually "recover it where it was
  discarded", not a patch per call site.

## Reseed discipline

A change the frozen seed cannot reproduce byte-for-byte needs a **self-promote** (see `seed/VERSION`), NOT a
Rust-ancestor rebuild. Inside `nix develop -c`, with `ulimit -c 0`: land the `src/` change → seed builds Stage1
→ Stage1 builds Stage2 → Stage2 builds Stage3 → verify **Stage1 == Stage2 == Stage3** byte-identical GAS + full
`scripts/e2e.sh` + all 3 sweeps → `cp target/stage2 seed/alatyr` + append a `seed/VERSION` note → confirm the
**post-reseed fixpoint** with the NEW seed. A fixpoint-NEUTRAL change needs no reseed.

**A reseed's GAS delta is the best place to find the compiler miscompiling ITSELF** — read every changed line
and ask whether that site was wrong before. The one reseed of the last arc surfaced four such latent bugs.

## Gates

**Two-tier cycle:** `nix develop -c bash scripts/dev.sh [test…]` is the FAST loop (one self-build + a corruption
guard + focused tests, ~1.5 min). `nix develop -c bash scripts/full.sh` is the AUTHORITATIVE gate —
`fixpoint.sh` + full `e2e.sh` + the corpus manifest + the `fmt` arbiter (`fmt_corpus.sh`, both walks) +
the idiom gate (`idiom_gate.sh`) + `scripts/sweeps.sh` (which runs the a64/rv64/wasm
sweeps only when a non-x86-emit file changed; `--force-sweeps` overrides). Iterate with `dev.sh`;
`full.sh` green before any merge.

Per slice: (1) confirm the behavior is decided in the specification — stop on a gap (FND-1), get it recorded, then
implement. (2) A focused regression test that fails first. (3) One coherent change. (4) Run the focused test and
the relevant public CLI/package path. (5) Full e2e + fixpoint in the worktree. (6) If the old seed cannot
reproduce it, report "reseed required" and let the integration owner self-promote. (7) For a non-x86 change,
verify the test MATCHES under qemu/wasmtime, then run the sweeps. (8) Commit only a complete, verified unit;
push only when explicitly requested.
