#!/usr/bin/env bash
# scripts/corpus_enum_check.sh — the gate's INPUT-SET check: the index and the worktree must name
# the same `.al` corpus (issue #645).
#
# Why this exists. The stages of scripts/full.sh do not enumerate their input the same way:
#
#   scripts/corpus_manifest.sh   `git ls-files 'test/*.al'`            — the INDEX
#   scripts/fmt_corpus.sh walk 1 `git ls-files 'test/*.al'`            — the INDEX
#   scripts/fmt_corpus.sh walk 2 `git ls-files 'src/*.al' 'lib/*.al'`  — the INDEX
#   scripts/idiom_gate.sh        `git ls-files 'src/*.al' 'lib/*.al'`  — the INDEX
#   scripts/e2e.sh               `$E2E_TEST/<name>.al` per registered row — the WORKTREE
#   a64/rv64/wasm sweeps         `grep -cE '^run [a-z]' scripts/e2e.sh`, then `test/<name>.al`
#                                                                       — the WORKTREE
#   scripts/fixpoint.sh          the compiler's own imports off `package.al` — the WORKTREE
#
# A fixture that is WRITTEN but not `git add`ed therefore exists for e2e, for all three sweeps and
# for the compiler build, and does not exist for the two stages that decide whether the corpus
# oracle still describes the tree. Measured by the #422 lane: its first complete `scripts/full.sh`
# run printed GREEN at `rows=8208` — the parent's row count — because its new fixture was untracked.
#
# The reason no other stage can catch that is worth stating, because it is the whole point of this
# file: `check_body_shape` (issue #639) asserts `rows == source_count × 4 − excluded_pairs`, and
# `source_count` is derived from the SAME `git ls-files` enumeration as the rows. An untracked file
# is absent from both sides of that identity, so the identity still holds and the stage that exists
# to notice a truncated corpus is exactly blind to this truncation. The row-count check is
# self-consistent under the defect; only a comparison against the OTHER enumeration can see it.
#
# WHICH ENUMERATION IS CORRECT, and why this check points the way it does.
#
#   The INDEX is authoritative. `scripts/corpus.manifest` is an oracle: a committed file that
#   describes a committed tree. A row for a file that no reviewer can fetch is not reviewable
#   evidence, and `git ls-files` is also the only enumeration that is stable across runs — an e2e or
#   package run leaves GENERATED, gitignored `.al` files under `test/` (`test/link/statstub/
#   package.al`), and `find` would make the corpus size depend on what ran before it. Both oracle
#   stages already say this in their own headers, and they are right.
#
#   So the defect is on the other side: e2e, the sweeps and the compiler build will happily execute
#   a file the oracles cannot describe. The fix is therefore NOT to make the oracles follow the
#   worktree. It is to refuse the divergence: every `.al` file the gate can execute must be a file
#   the oracles can describe, and every file they describe must exist.
#
# The check, stated as the containment it is: the worktree's non-ignored `.al` set under `test/`,
# `src/` and `lib/` must EQUAL the index's. Then, for free, every fixture an e2e row or a sweep row
# names and finds on disk is a file `git ls-files` also returns — no parser of `scripts/e2e.sh` is
# needed, and none is used, because a parser of that registry would be a second enumeration to keep
# in step and would reintroduce the very class it is meant to close.
#
# Both sides are enumerated INDEPENDENTLY and then joined with `comm`, rather than asking git for
# the difference directly. `git ls-files --others` would be one command reporting on its own view of
# both sets; the executing stages do not use it — they `open()` a path — so the worktree side here
# is a real `find`, the same walk `alatyr` itself performs, and the two lists are compared as sets:
#
#   extra   — on disk, not in the index, not ignored. This is the #422 shape: a written-but-
#             unstaged fixture. e2e and the sweeps run it; the two oracle stages never see it.
#   missing — in the index, not on disk. The mirror image: the oracle stages would enumerate a
#             file they then cannot read, while e2e and the sweeps would never look for it.
#
# IGNORED `.al` files are counted and reported, never judged. They are the deliberate exclusion the
# two oracle headers name, and after any e2e run there is at least one; failing on them would make
# the gate depend on what ran before it, which is the thing `git ls-files` was chosen to avoid.
#
# A refusal, not a warning: the failure mode this closes is a GREEN gate, so anything short of a
# nonzero exit reproduces the problem in a new place. scripts/full.sh runs this FIRST and stops
# there, because every later stage would be measuring an input set nobody chose.
#
# scripts/dev.sh deliberately does NOT run this. Mid-iteration an unstaged fixture is the normal
# state of a working tree; refusing it in the fast loop would only teach people to skip the fast
# loop. The rule is "staged before the AUTHORITATIVE gate", and this is the authoritative gate's
# check.
#
# Usage (inside `nix develop`):  bash scripts/corpus_enum_check.sh [<root>]
#                                bash scripts/corpus_enum_check.sh --self-test
# Exit 0 = the two enumerations agree.  1 = they diverge (the offending paths are named).
#       2 = the check could not be performed (not a git work tree, or an EMPTY corpus — a check
#           that walked nothing must not read as a pass).
set -u

## The roots, and the pathspecs, EXACTLY as the oracle stages spell them. Read `test/*.al` as the
## git pathspec it is and not as a shell glob: git's `*` matches `/`, so the one pattern also selects
## the multi-file package fixtures under `test/package/**`. corpus_manifest.sh depends on that, and
## the self-test below plants a nested file to prove this file depends on it the same way.
ENUM_PATHSPECS=('test/*.al' 'src/*.al' 'lib/*.al')
## The same three roots for the worktree walk. Keeping them beside the pathspecs is the point: the
## two sides of this comparison must cover the same ground, or the check has a blind spot of its own.
ENUM_ROOTS=(test src lib)

## THE DECIDER. Prints its findings and a proof-of-work line; returns 0 / 1 / 2 as documented above.
## The self-test drives THIS function against planted trees — a stage whose failure verdict is only
## ever reached by the real corpus is a verdict nobody has ever seen fail.
enum_check() { # root
  local root="$1" w extra missing tracked worktree ignored bad=0

  git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    echo "corpus enum: FAIL — '$root' is not a git work tree, so the index enumeration the corpus" >&2
    echo "  and fmt oracles use does not exist here and cannot be compared. Refusing to report." >&2
    return 2
  }

  w="$(mktemp -d)" || return 2

  ## SIDE A — the INDEX, spelled exactly as corpus_manifest.sh / fmt_corpus.sh / idiom_gate.sh spell it.
  git -C "$root" ls-files -- "${ENUM_PATHSPECS[@]}" | sort > "$w/index"
  ## SIDE B — the WORKTREE, walked the way a stage that RUNS a fixture reaches it: a path on disk.
  ## `-type l` as well as `-type f`: a symlinked fixture is a file the compiler can open and one the
  ## index records, so silently dropping it here would invent a `missing` that is not one.
  ( cd "$root" && find "${ENUM_ROOTS[@]}" \( -type f -o -type l \) -name '*.al' -print 2>/dev/null ) |
    sed 's|^\./||' | sort > "$w/disk"
  ## The deliberate exclusion, subtracted from side B only: generated `.al` files an e2e or package
  ## run leaves behind (test/link/statstub/package.al). They are the reason the oracle stages chose
  ## the index in the first place, and judging them here would make this gate depend on what ran
  ## before it.
  git -C "$root" ls-files --others --ignored --exclude-standard -- "${ENUM_PATHSPECS[@]}" | sort > "$w/ignored"
  comm -23 "$w/disk" "$w/ignored" > "$w/disk_live"

  tracked="$(wc -l < "$w/index")"
  worktree="$(wc -l < "$w/disk_live")"
  ignored="$(wc -l < "$w/ignored")"
  extra="$(comm -13 "$w/index" "$w/disk_live")"
  missing="$(comm -23 "$w/index" "$w/disk_live")"

  ## A path holding whitespace would make the line-oriented join above quietly wrong rather than
  ## loud, and corpus_manifest.sh already refuses one for its own TAB-separated job list.
  if grep -qE '[[:space:]]' "$w/index" "$w/disk_live" 2>/dev/null; then
    echo "corpus enum: FAIL — a .al path contains whitespace; this line-oriented comparison cannot" >&2
    echo "  carry it (scripts/corpus_manifest.sh refuses the same path for the same reason)." >&2
    grep -hE '[[:space:]]' "$w/index" "$w/disk_live" | sort -u | sed 's/^/    ? /' >&2
    rm -rf "$w"
    return 2
  fi

  rm -rf "$w"

  if [ "$tracked" -lt 1 ]; then
    echo "corpus enum: FAIL — the index holds ZERO .al files under ${ENUM_PATHSPECS[*]}; there is no" >&2
    echo "  corpus to compare and this check proved nothing. Refusing to report a result." >&2
    return 2
  fi

  if [ -n "$extra" ]; then
    echo "corpus enum: FAIL — $(printf '%s\n' "$extra" | wc -l) .al file(s) exist in the worktree and NOT in the index:" >&2
    printf '%s\n' "$extra" | sed 's/^/    + /' >&2
    echo "  scripts/e2e.sh, the three sweeps and the compiler build read the WORKTREE and would run" >&2
    echo "  these; scripts/corpus_manifest.sh and scripts/fmt_corpus.sh read the INDEX and would not." >&2
    echo "  The corpus oracle's row-count identity stays self-consistent either way (issue #639), so" >&2
    echo "  the gate would have gone GREEN describing a corpus it never saw (issue #645, lane #422)." >&2
    echo "  Fix: 'git add' the file(s) — or delete them — and re-run the gate." >&2
    bad=1
  fi

  if [ -n "$missing" ]; then
    echo "corpus enum: FAIL — $(printf '%s\n' "$missing" | wc -l) .al file(s) are in the index and NOT in the worktree:" >&2
    printf '%s\n' "$missing" | sed 's/^/    - /' >&2
    echo "  scripts/corpus_manifest.sh and scripts/fmt_corpus.sh would enumerate these and fail to" >&2
    echo "  read them; scripts/e2e.sh and the sweeps would not look for them at all." >&2
    echo "  Fix: restore the file(s) — or 'git rm' them — and re-run the gate." >&2
    bad=1
  fi

  ## Proof of work on the SAME line as the verdict: a green line with no counts cannot be told apart
  ## from a check that enumerated nothing, and "the gate reports a completeness it does not have" is
  ## the defect this file exists for. `ignored=` is reported because it is the one deliberate
  ## difference between the two enumerations, and a silent exclusion is not an exclusion anyone can
  ## review.
  echo "corpus enum: index=$tracked worktree=$worktree extra=$(printf '%s' "$extra" | grep -c .) missing=$(printf '%s' "$missing" | grep -c .) ignored=$ignored pathspecs=${ENUM_PATHSPECS[*]}"
  if [ "$bad" = 0 ]; then
    echo "*** corpus enum: the index and the worktree name the same .al corpus ***"
  else
    echo "*** corpus enum: the index and the worktree name DIFFERENT .al corpora — the oracle stages"
    echo "    and the executing stages would not describe the same tree ***"
  fi
  return "$bad"
}

# ======================================================================================================
# THE GATE-OF-THE-GATE. Eleven planted trees, 4 + 4 + 3: FOUR controls that must stay green (a clean
# tree, a generated+gitignored `.al`, a staged-not-committed fixture, a tracked symlink), FOUR
# divergences that must each be refused BY NAME, and THREE refusals that must not read as a pass (an
# empty corpus, a non-git directory, a whitespace path). The controls are not padding: without them a
# decider that simply always failed would score full marks here, and the two `git add`-related
# controls are the ones that pin down WHICH act — staging, not committing — this check demands.
# ======================================================================================================
_ce_repo() { # dir
  local d="$1"
  mkdir -p "$d/test/package/dep" "$d/src" "$d/lib"
  git -C "$d" init -q 2>/dev/null || return 1
  git -C "$d" config user.email ce@example.invalid
  git -C "$d" config user.name  "corpus enum self-test"
  printf 'main := fn() -> u64 { 42 }\n'  > "$d/test/keep.al"
  printf 'answer := fn() -> u64 { 42 }\n' > "$d/test/package/dep/mod.al"
  printf 'drive := fn() -> u64 { 1 }\n'  > "$d/src/driver.al"
  printf 'rt := fn() -> u64 { 1 }\n'     > "$d/lib/rt.al"
  ## The real repository ignores exactly one generated `.al` (test/link/.gitignore, written by
  ## scripts/e2e.sh run_link_static). Mirror that shape, not a made-up one.
  mkdir -p "$d/test/link/statstub"
  printf 'statstub/package.al\n' > "$d/test/link/.gitignore"
  git -C "$d" add -A >/dev/null 2>&1
  git -C "$d" commit -qm base >/dev/null 2>&1
}

_ce_case() { # label root want-rc needle…
  local label="$1" root="$2" want="$3"; shift 3
  local out rc n
  out="$(enum_check "$root" 2>&1)"; rc=$?
  if [ "$rc" != "$want" ]; then
    echo "FAIL corpus enum self-test [$label]: rc=$rc want $want" >&2
    printf '%s\n' "$out" | sed 's/^/      /' >&2
    return 1
  fi
  for n in "$@"; do
    case "$out" in
      *"$n"*) ;;
      *) echo "FAIL corpus enum self-test [$label]: verdict never mentioned '$n'" >&2
         printf '%s\n' "$out" | sed 's/^/      /' >&2
         return 1 ;;
    esac
  done
  echo "ok   corpus enum self-test [$label]: rc=$rc"
}

ce_self_test() {
  local st bad=0
  st="$(mktemp -d)" || return 1
  # shellcheck disable=SC2064
  trap "rm -rf '$st'" RETURN

  ## 1 — the CONTROL. A committed tree with a nested package fixture and an unrelated non-.al file
  ##     must be green, or every refusal below is just a decider that always fails.
  _ce_repo "$st/clean" || { echo "FAIL corpus enum self-test: could not build the control repo" >&2; return 1; }
  printf 'not alatyr\n' > "$st/clean/test/notes.txt"
  _ce_case clean "$st/clean" 0 "index=4" "extra=0" "missing=0" "same .al corpus" || bad=1

  ## 2 — the #422 shape: a fixture written into test/ and never staged.
  _ce_repo "$st/untracked"
  printf 'main := fn() -> u64 { 7 }\n' > "$st/untracked/test/planted.al"
  _ce_case untracked-test "$st/untracked" 1 "test/planted.al" "DIFFERENT .al corpora" "git add" || bad=1

  ## 3 — the same shape one directory down. This is not redundant with case 2: it is what proves
  ##     this file reads `test/*.al` as a git PATHSPEC (git's `*` crosses `/`) and therefore covers
  ##     exactly the set corpus_manifest.sh calls its corpus. A shell-glob reading would pass here.
  _ce_repo "$st/nested"
  printf 'answer := fn() -> u64 { 7 }\n' > "$st/nested/test/package/dep/planted.al"
  _ce_case untracked-nested "$st/nested" 1 "test/package/dep/planted.al" || bad=1

  ## 4 — an untracked compiler module. fmt_corpus.sh walk 2 enumerates src/+lib/ from the index while
  ##     the build resolves imports off the worktree, so this is the same divergence, one stage over.
  _ce_repo "$st/srcmod"
  printf 'helper := fn() -> u64 { 7 }\n' > "$st/srcmod/src/planted.al"
  printf 'helper := fn() -> u64 { 7 }\n' > "$st/srcmod/lib/planted.al"
  _ce_case untracked-src "$st/srcmod" 1 "src/planted.al" "lib/planted.al" || bad=1

  ## 5 — the mirror image: tracked, deleted from the worktree. The oracle stages would enumerate it.
  _ce_repo "$st/deleted"
  rm -f "$st/deleted/test/keep.al"
  _ce_case deleted "$st/deleted" 1 "test/keep.al" "in the index and NOT in the worktree" || bad=1

  ## 6 — the deliberate exclusion. A GENERATED, gitignored `.al` (what scripts/e2e.sh leaves behind)
  ##     must stay green and must be COUNTED, so the exclusion is reviewable rather than silent. If
  ##     this case ever goes red the gate has become order-dependent on what ran before it.
  _ce_repo "$st/ignored"
  printf 'main := fn() -> u64 { 1 }\n' > "$st/ignored/test/link/statstub/package.al"
  _ce_case ignored-generated "$st/ignored" 0 "ignored=1" "same .al corpus" || bad=1

  ## 7 — STAGED but not committed is GREEN, and that is the point of the whole design: `git ls-files`
  ##     reads the index, so staging is what makes a fixture visible to the oracles. If this case
  ##     failed, the check would be demanding a commit and the rule it teaches would be the wrong one.
  _ce_repo "$st/staged"
  printf 'main := fn() -> u64 { 9 }\n' > "$st/staged/test/staged.al"
  git -C "$st/staged" add test/staged.al >/dev/null 2>&1
  _ce_case staged "$st/staged" 0 "index=5" "extra=0" || bad=1

  ## 8 — a repository with no `.al` at all must refuse as VACUOUS (2), never pass. A check that
  ##     compares an empty set to an empty set agrees with itself, which is the exact failure of
  ##     `check_body_shape` this file was written to cover.
  mkdir -p "$st/empty"
  git -C "$st/empty" init -q
  git -C "$st/empty" config user.email ce@example.invalid
  git -C "$st/empty" config user.name "corpus enum self-test"
  printf 'x\n' > "$st/empty/README.md"
  git -C "$st/empty" add -A >/dev/null 2>&1
  git -C "$st/empty" commit -qm base >/dev/null 2>&1
  _ce_case empty-corpus "$st/empty" 2 "ZERO .al files" || bad=1

  ## 9 — not a git work tree at all: refuse (2), do not silently pass.
  mkdir -p "$st/nogit"
  _ce_case no-git "$st/nogit" 2 "not a git work tree" || bad=1

  ## 10 — a TRACKED SYMLINK to a fixture must be green. This is the control on the worktree walk's
  ##      `-type f -o -type l`: git records mode 120000 and lists the path, the compiler can open
  ##      it, and a `-type f`-only walk would invent a `missing` for a file that is right there.
  _ce_repo "$st/symlink"
  ( cd "$st/symlink/test" && ln -s keep.al alias.al )
  git -C "$st/symlink" add test/alias.al >/dev/null 2>&1
  _ce_case tracked-symlink "$st/symlink" 0 "index=5" "missing=0" || bad=1

  ## 11 — a whitespace path makes the line-oriented join unsound, so it is refused (2) rather than
  ##      silently mis-joined. corpus_manifest.sh refuses the same path for the same reason.
  _ce_repo "$st/space"
  printf 'main := fn() -> u64 { 1 }\n' > "$st/space/test/two words.al"
  git -C "$st/space" add "test/two words.al" >/dev/null 2>&1
  _ce_case whitespace-path "$st/space" 2 "contains whitespace" || bad=1

  if [ "$bad" = 0 ]; then
    echo "corpus enum: gate-of-the-gate OK — 11 planted trees (4 controls green, 4 divergences named, 3 refusals)"
  else
    echo "*** corpus enum: gate-of-the-gate FAILED — the divergence decider is not doing what it claims ***" >&2
  fi
  return "$bad"
}

if [ "${1:-}" = "--self-test" ]; then
  ce_self_test
  exit $?
fi

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
enum_check "$ROOT"
exit $?
