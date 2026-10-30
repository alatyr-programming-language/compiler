# Commits, oracles and landing — rationale

Commit message form, the attribution prohibition and its enforcement, and the oracle and landing rules in full.

Moved verbatim from `AGENTS.md` (#1130). `AGENTS.md` states each rule briefly; this file is the full
text, with the reasons, measurements and history. Line citations are as of the move.

## Commit messages

Every authored non-merge commit uses Conventional Commits and has a complete body:

```text
<type>(<optional scope>): <short imperative description>

What changed and why.
Verification and relevant compatibility, oracle, or reseed notes.
```

Use lowercase types from `feat`, `fix`, `docs`, `refactor`, `test`, `build`, `ci`, `perf`, `chore`, or
`revert`; keep the scope short and meaningful, and omit it when no scope helps. Use `!` after the type
or scope, and a `BREAKING CHANGE:` footer, for a breaking change. The body is mandatory, must explain
what and why rather than repeat the subject, and must state the relevant verification. Keep one coherent
change per commit.

Examples: `fix(lower): preserve nested field places`, `docs: tighten agent workflow rules`,
`chore(oracle): regenerate corpus manifest`. Oracle regeneration and reseed evidence are separate
commits that touch no unrelated files. Integration-generated merge commits may use Git's merge format;
their PR evidence and acceptance record still provide the full description.

**No attribution trailer. Ever.** A commit message carries no `Co-Authored-By:`, `Assisted-by:`,
`Generated with:` or similar trailer, naming anyone or anything. Every commit here is authored and
committed under the owner's identity, and GitHub renders such a trailer as a **second author of
record** — a permanent, unauditable claim about who wrote the code. An agent's contribution is recorded
where it is true and reviewable: in the PR discussion, the review, and the gate evidence. Nine commits
naming an AI model reached main before this rule was written down; the prohibition had been given in
conversation and never written where the next session reads it.

The pattern and the decider live in `scripts/attribution.sh`, read by both `scripts/land.sh` PHASE 2
(every commit message in `BASE..HEAD`, plus the PR body) and `scripts/hooks/commit-msg`; there is no
second copy to drift. `scripts/land.sh --self-test` holds the rule in both directions, including the
eraser control (an ordinary body must pass) and prose that merely mentions the words. Install the local
hook once per clone or worktree with `bash scripts/install-hooks.sh` — git does not clone
`.git/hooks/`, so the hook is an earlier trip, not the guarantee; `land.sh` is. The message check goes
in `commit-msg`, not `pre-commit`: git passes the message file only to `commit-msg`, so the same rule
placed in `pre-commit` installs cleanly and never fires (measured). In prose and bodies write
"co-author trailer" without the colon — the colon is what makes it a trailer.

## Oracle and landing rules

- **The stated expectation and the known deviations (#1126 S3).** A fixture states what the
  specification requires of it once, as `## expect:` (`scripts/fixture_oracle.sh`). The gate's
  FIXTURE EXPECT stage judges every backend of the fresh corpus walk against it: the walk meets the
  directive, or the pair is a row of `scripts/known-deviations.tsv` whose `observed` is exactly what the
  walk saw, under an issue of `scripts/known-deviations.issues.tsv` (the published list `alatyr version`
  names: per issue, the rule not met and the observable difference). Anything else is red, including a
  row that no longer reproduces. So a behaviour fix lands as one PR with its code, its fixture and the
  deletion of its own deviation rows, on one gate, with no oracle commit; a change that introduces a
  deviation adds its row under an issue. The list is not an oracle: rows are sorted, one per pair, and
  merge with `merge=union`, because each fix deletes disjoint lines and a row a union merge restores no
  longer reproduces and fails. `land.sh` PHASE 2 checks that every issue in the table is open (the gate
  has no credentials). A new fixture states its expectation: one with neither a directive nor a
  committed manifest row is red.
- **What `scripts/corpus.manifest` still holds.** Recording a directive fixture's rows too would make
  every fix an oracle change again, so the committed manifest holds (a) every pair of a source with no
  directive yet — the review list of `scripts/fixture_expect.sh --review`, which only shrinks — and (b)
  every pair of a directive source that writes to stdout on some backend, because a directive states
  phase and exit, not the bytes printed (the output sidecar; 39 sources, measured at S3). The walk
  itself is kept whole at `target/corpus-manifest/observed.manifest`, and the gate's readers of what
  each backend did (FIXTURE EXPECT, the xbackend ratchet) read that, never the committed scope.
- The three oracle files are exclusive: `scripts/corpus.manifest`, `scripts/idiom.baseline`, and
  `scripts/needle.baseline`. At most one open PR may touch an oracle, and such a PR touches no other
  file. The repository marks them `-merge`; `scripts/land.sh` enforces the same rule. An intentional
  oracle change is reviewed and committed separately.
- A worker never changes an oracle. For an intentional oracle transition, the worker PR is feature-only
  and may carry only the reviewed pre-oracle mismatch as evidence; the maintainer owns the oracle
  regeneration after the local merge. Each regeneration is one commit touching that oracle alone,
  followed by a complete green gate on the resulting object.
- Since #1127, landing runs in the merge queue (`scripts/queue.sh`, a systemd timer on omen; its header
  is the protocol). The integrator's act is `scripts/queue.sh --enqueue N=SHA` after review, which records
  the reviewed head. The queue composes up to four queued PRs onto `origin/main`, gates the composed
  object once with `full.sh`, pushes exactly that object with `--force-with-lease` on its base, comments
  on each member and deletes each member's remote branch; on red it bisects and marks the culprit
  `queue-failed`. A PR carrying an oracle or a predicted delta is gated alone through `land.sh N`. The
  rules below are what the queue enforces, and what a hand landing (a seed promotion, or the queue down)
  must follow itself. The queue does not touch any lane's local worktree: that cleanup stays with whoever
  owns it, after any landing.
- Verification runs on the locally merged result, not the contributor branch. Re-derive the evidence,
  check that merge with the gate appropriate to its independently reviewed change class, and push exactly
  the object that passed. Never re-merge or modify it between verification and push.
- Pull-request status is not authoritative, and neither is any hosted check other than the one below.
  The full gate is the verdict for every executable, generated, compiler, fixture, build,
  workflow-control, release, security, permission, or uncertain change, run either on the
  integrator's own native x86_64 machine or by `.github/workflows/gate.yml` on a GitHub-hosted runner
  (a push to a `gate/**` branch). The workflow is a remote gate machine, not a landing bot: it holds no
  write token, and its verdict is the `*** FULL GATE` line of its `gate.log` artifact for the exact
  pushed commit, read by the integrator — not the check's colour. The corpus manifest it generated is
  published as an artifact, and an oracle commit may take it byte for byte, exactly as `--write` would.
  Only independently classified inert prose may use the docs-only gate below.
- After a successful landing, the remote feature branch is removed (by the queue, or by the integrator
  after a hand landing) and, only when its local tip exactly equals the landed PR head and its dedicated worktree is
  clean, removes the matching local worktree and branch too. A dirty, diverged, or ambiguous local
  checkout is retained and reported; never force-delete it. A fork-owned branch is not deleted through
  the upstream repository, and its name is not used to clean local state.
