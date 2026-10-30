# Reproducibility — rationale

Why the seed is promoted the way it is: Stage2, bump first, a one-sentence delta.

Moved verbatim from `AGENTS.md` (#1130). `AGENTS.md` states each rule briefly; this file is the full
text, with the reasons, measurements and history. Line citations are as of the move.

## Reproducibility

- A source change is not complete until the authoritative gate is green and the compiler remains
  reproducible.
- `seed/alatyr` is a frozen static bootstrap. The unpublished Rust ancestor is not a build input and is
  never a recovery path.
- If the frozen seed cannot reproduce a source change, the integrator owes a self-promotion: the
  version bump comes **first**, then Stage1 → Stage2 → Stage3 are built from that tree and must emit
  byte-identical GAS once the `.L<N>` and `.Lra<N>_<k>` label families are normalized, with the
  Stage2 and Stage3 **binaries** matching, and full e2e and sweeps; read the normalized
  seed-to-Stage1 delta, promote **Stage2**, append evidence to `seed/VERSION`, and re-run the
  post-promotion fixpoint. A lane never promotes the seed.
- Stage1's binary is expected to differ, and requiring all three of them to match asks for something
  no version-releasing promotion can deliver: the 0.1.0 → 0.2.0 promotion left `seed/alatyr`
  differing from the Stage1 it then builds by exactly 35 bytes, every one of them `'1' → '2'` — the
  version digit compiled into the binary. Read literally, that criterion scores a successful
  promotion as a failed one. Stage2 is the artifact to freeze because it is assembled from the *new*
  emission and therefore carries the change in its own code, which Stage1, assembled from the stale
  seed's emission, does not. Only the stale-emission half of that is permanent: those 35 bytes were a
  symptom of the old ordering, and with the bump ahead of the build (below) the promoted seed and the
  Stage1 it builds from that same tree carry the same version string. The binary clause still stops
  at `Stage2 == Stage3`, for the stale-emission reason alone.
- Reading the delta has a pass condition of its own: the delta must be describable in one sentence.
  That promotion's was 822 hunks, 3288 lines added and none removed — four lines per hunk, four
  distinguishable line shapes, every insertion immediately before a byte load whose index, length
  and pointer the three preceding lines set up. One recognizable pattern, repeated, is a reviewable
  delta. A delta that resists a one-sentence characterization is the signal to stop, not to promote
  and hope the next reseed explains it.
- A promotion is also a version release. `package.al`'s `version` moves on a seed promotion and only on
  one, `seed/VERSION`'s CURRENT SEED block records the promoted hash and that version, and
  `scripts/fixpoint.sh` refuses a tree where the two disagree — in either direction. The complete file
  set and the annotated `v<version>` tag are defined by `CHANGELOG.md`'s versioning order and by
  `alatyr-integrate`. The specification pin is a separate number and never moves with it.
- **The bump precedes the build, and the order is load-bearing.** `src/cli.al`'s `cli_version`
  answers `app.version`, which TOOL-15 injects as a compile-time constant, so a compiler reports the
  version of the tree it was **compiled from** — not the tree it is committed into. Move
  `package.al`'s `version`, `seed/VERSION`'s `current-seed-version` and
  `scripts/package_cli_test.sh`'s expected `alatyr <version>` line before building the stages, and
  the frozen Stage2 answers the number it is released under. Bumping inside the promotion commit
  freezes a Stage2 compiled from the previous tree instead, and that seed answers the previous
  version for the rest of its life. That is measured, not hypothetical: `seed/alatyr` on `main` is
  recorded, released and tagged `v0.2.0`, answers `alatyr 0.1.0` with rc 0, and contains **zero
  occurrences of the string `0.2.0`** where the Stage1 it builds from that tree contains 35 — the
  version constant's 35 embedded copies (#586).
- The bump-first order is fixpoint-safe, and that was measured rather than reasoned: on a throwaway
  worktree with `package.al` and `current-seed-version` at a test `0.2.1` over the untouched
  0.1.0-answering seed, `scripts/fixpoint.sh` printed `seed == Stage1 == Stage2` at 1 224 447 GAS
  lines, with Stage1 and Stage2 byte-identical and both answering `alatyr 0.2.1`. The version
  constant is 35 embedded copies of the string, one differing byte each — exactly the 35-byte Stage1
  binary delta recorded above — and the fixpoint compares two compilations of the *same* tree, so
  they move in both emissions at once and are invisible there. `current-seed-version` moves in the
  **same** step as `package.al`: the seed-identity check compares the two before anything is built
  and exits 6 on a disagreement, so a lone `package.al` bump cannot even reach a build.
- The intermediate state is real, and today only the atomic commit keeps it out of `main`. Between
  the bump and the seed replacement the working copy carries a version the committed seed does not
  answer, and `seed/VERSION`'s two CURRENT SEED lines describe two different compilers — the digest
  the old one, the version the one about to be frozen. The same measurement shows the gate cannot see
  that split: both fields agreed at `0.2.1` over a seed answering `0.1.0` and the seed-identity check
  passed, because only its digest side is checked against the artifact while its version side
  compares one claim to another. So the promotion commit stays atomic — bump,
  `scripts/package_cli_test.sh`, seed, `current-seed-sha256`, the appended entry, `CHANGELOG.md` —
  and the intermediate state is never committed on its own. #586's next step closed the hole by
  comparing `./seed/alatyr --version`, and it landed after the first promotion built in this order: the
  seed answers `alatyr 0.2.16` and `current-seed-version` records `0.2.16`, so the claim is now checked
  against the artifact rather than against another claim. On a host that cannot execute the seed (it is a
  static x86_64 ELF) the check skips and says so in its verdict line — a skipped check is not a passed
  one — and it runs for real on x86_64 Linux.

## Workspace invariants

- Work inside `nix develop` and run commands with `ulimit -c 0`.
- `git stash` is forbidden: it is a repository-wide ref and concurrent lanes can exchange one another's
  work. Use a derived throwaway worktree for a clean baseline.
- Never run two target-producing gates in one checkout. Derive worktree paths; do not use fixed shared
  paths for concurrent work.
- Never move a built compiler away from the repository layout: its standard-library lookup is relative
  to the executable and silently fails without the adjacent `lib/`.
- Follow the existing self-hosting idioms. A language feature that is valid in principle may still be
  unavailable to the frozen seed until the integrator promotes it.
