---
name: alatyr-lane
description: >-
  Take ONE unit of work on the Alatyr compiler and deliver it as a pull request.
  Use when the task is to implement, fix or extend something in this repository —
  a wrong value, a rejected valid program, a bad diagnostic, a new construct, a
  gate improvement. Covers claiming an issue, isolating a working tree, writing a
  fixture that provably fails first, running the authoritative gate, and opening a
  PR whose evidence an integrator can re-derive. Does NOT cover landing: only the
  maintainer moves `main` (see the alatyr-integrate skill).
---

# Taking one unit of work

`AGENTS.md` holds what is true whatever you are doing — the gate blind spots, the measurement traps,
the reseed rule. Read it. This file is only the procedure.

**One unit of work at a time.** Not "while I'm here". A slice that grows while being implemented
produces a measurement nobody can attribute, and that is the expensive failure here, not the merge.

## 1 · Claim it

```sh
R=alatyr-programming-language/compiler
gh issue list -R $R --state open --json number,title,assignees,labels     # what is already taken
gh pr list   -R $R --state open --label oracle --json number --jq 'length' # MUST be 0 before §6
                                                                          # (the label is applied in §7)
gh issue edit <N> -R $R --add-assignee @me
```

Assigning the issue **is** the claim. There is no register to update and no announcement to send
later: the pull request exists from your first push, so "finished" is a state change on an object the
maintainer is already looking at, not a second act you can forget.

If no issue describes the work, open one first. An issue is where the *measurement* lives; a PR is
where the *change* lives, and mixing them loses the before-state the moment the fix lands.

**Spec first, always.** If the specification does not answer a question you need answered, stop. Do
not infer semantics from current behaviour — open an issue against the
[specification](https://github.com/alatyr-programming-language/spec), get it decided there, then
implement. That rule is the only reason this compiler can claim conformance.

## 2 · Isolate

Derive the path; never name one. Two gates in one checkout collide over `target/`.

```sh
W="$(mktemp -d)"
git worktree add --detach "$W" origin/main    # or: git clone --no-local . "$W"
cd "$W" && git switch -c <branch>
```

Budget ~150 MB of build artifacts. Drop it with `git worktree remove` when done — deleting the
directory leaves a broken registry entry. **Never `git stash`**: it is one ref for the whole
repository and two trees stashing at the same moment swap each other's uncommitted work.

Never move a built compiler out of a directory with `../lib` beside it — `lib_dir` is
`dirname(/proc/self/exe)/../lib`, and the stdlib injection disappears silently.

## 3 · The fixture, and it must fail FIRST

A test that passes before your change proves nothing about your change. Prove the failure on the
**parent** compiler, in the fixture's own header, in words and numbers:

```sh
git stash list                                      # must be empty; see §2
B="$(mktemp -d)"; git worktree add --detach "$B" "$(git merge-base origin/main HEAD)"
cd "$B" && git checkout HEAD@{0} -- test/ scripts/e2e.sh   # NEW fixtures, OLD src/
seed/alatyr build package.al && ALATYR_E2E_FILTER=<name> bash scripts/e2e.sh
```

`built rc 0 and ran to 0 where 42 was due` is evidence. `was broken` is not.

Three traps that have each cost a cycle:

- **The needle must not appear in its own fixture's comments.** The `*_has` helpers grep the whole
  artifact, so a header quoting the string its own assertion searches for passes on an unfixed
  compiler. `scripts/e2e.sh` now refuses this at record time; 20 pre-existing rows are grandfathered
  in `scripts/needle.baseline` and reported on every run. Do not add the 21st.
- **A bare `build_reject` only asks for a nonzero exit** — a fail-loud accident satisfies it. Use
  `build_reject_has <name> <needle>` with the real diagnostic, and check the needle is not already in
  the OLD compiler's stderr, or the fixture fails for the old reason and proves nothing.
- **A fixture for the NEW form does not test the OLD one.** Probe the new member next to an old one,
  in both orders. The compound-assignment lane was green on every new-operator fixture while
  `x &= 58` followed by `x = 1` was rejected, because three source-scan recoveries still listed only
  the four old operators.

Cross-backend fixtures must return **< 126**: WASI `proc_exit` rejects anything else and wasmtime's
host abort is indistinguishable from a failure.

## 4 · Change it, narrowly

Fire on the exact new shape. A broad lowering fix once regressed ~90 stdlib tests; the version that
shipped fired only on the shape that was broken. When one fact is recovered by scanning the source in
more than one place, `grep` for the other copies — that is part of the fix, not a follow-up.

## 5 · Gate it, in your own tree

```sh
ulimit -c 0
nix develop -c bash scripts/full.sh --force-sweeps    # ~6 min; must print GREEN (sweeps RAN)
git diff --exit-code && git diff --cached --exit-code # the manifest ran --check, not --write
```

Run the **full** table, not just your fixtures. A red branch must never reach a pull request.

Emission changed? Measure the GAS delta with the **input tree held fixed, in both directions**, with
the `.L<N>` and `.Lra<N>_<k>` label families normalized. Comparing your tree against the old one
compares a longer source with a shorter one and proves nothing.

## 6 · What you may not touch

- **`seed/alatyr`** — a reseed is the maintainer's act and needs three-stage evidence
  (`Stage1 == Stage2 == Stage3`). If the fixpoint reports `seed != Stage1`, say "reseed owed" in the
  PR and stop. Do not commit a seed binary: the evidence is not a property of the diff, so nobody
  can verify it from your PR.
- **`seed/VERSION`** — append-only. Never rewrite entries to make old hashes resolve.
- **`scripts/corpus.manifest`, `scripts/idiom.baseline`, `scripts/needle.baseline`** — the THREE
  oracles, all three marked `-merge` in `.gitattributes` and all three enforced by `scripts/land.sh`.
  Regenerated only by someone who read the diff, in their **own commit that touches nothing else**,
  with every row transition accounted for by joining on `(backend, path)`
  (`scripts/corpus_manifest.sh --explain` prints exactly that). At most one such PR is open at a time;
  check §1 before you start, and **label that PR `oracle`** — §1's count is what enforces the rule, and
  an unlabelled oracle PR is invisible to it.
- **Before creating any file**, `git log -- <path>`. A lane once overwrote a stronger existing
  fixture that way.

## 7 · Open the pull request

```sh
gh pr create -R $R --base main --fill --body-file - <<EOF
$(cat .github/PULL_REQUEST_TEMPLATE.md)
EOF
```

If this PR touches one of the three oracle files, label it so §1's count can see it — the rule is
enforced by that count, not by memory:

```sh
gh pr edit <N> -R $R --add-label oracle
```

Fill the template's Evidence section with numbers that say **how they were obtained**. Your numbers
are a claim: the integrator re-derives every one of them on the merged result, which is why an
approval is not a landing and why your PR may sit while a ~6-minute gate runs. There is no CI.

Then stop. You do not merge, and you do not push to `main`.
