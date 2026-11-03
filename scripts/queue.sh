#!/usr/bin/env bash
# scripts/queue.sh — the merge queue: gates batches of reviewed PRs on omen and lands them with no
# agent session attached (#1127).
#
# ## Why
#
# Landing used to live inside one agent session. When that session hit a usage limit, `main` stopped
# (2026-10-15 → 10-22: zero landings). The mechanical part — merge, full gate, push exactly the gated
# object with a lease, acceptance, cleanup — needs no judgement, so it runs here, from a systemd timer.
# The judgement stays with the reviewing integrator, whose one act is `--enqueue`.
#
# ## The protocol
#
# - Entry is the label `queue` plus a marker comment `queue-head: <sha>`, both written by `--enqueue N=SHA`
#   after the alatyr-integrate §2 review. Only the integrator enqueues (alatyr-integrate, alatyr-lane);
#   every panel posts as the same GitHub account, so the marker records WHICH object was reviewed, not
#   who reviewed it. A PR whose head moved past its marker is dropped with a comment, never gated.
# - A pass (`--once`) takes up to ALATYR_QUEUE_MAX (4) queued PRs in PR-number order. Each must target
#   `main`, be ready (not draft, no `hold`), carry exactly one line-initial relation marker, and pass
#   `land.sh N --screen` (preconditions, provenance, PR shape; forks refused) on its reviewed head.
# - A PR that carries an oracle file or a predicted delta is gated alone by `land.sh N` (its PHASE 6a
#   owns that path, and its PHASE 6c the baseline commit on it), as alatyr-integrate §3 requires.
#   A delta made stale by another landing is rebased by land.sh itself (#1264), at the screen and
#   again in the solo landing, whose gate runs on the merge that carries the rebased copy. That solo
#   landing walks the corpus alone first (land.sh PHASE 3b), and a rebased delta the walk does not realise is `red` without a full gate; the queue needs nothing
#   else of its own for it. So is a PR that conflicts with main only in CHANGELOG.md (and the delta):
#   the screen says solo=yes, and land.sh PHASE 3 settles that file (#1312). So, too, is a PR whose
#   clean merge would file a CHANGELOG.md line under a release heading: PHASE 3 moves it (#1319). The
#   others are composed
#   onto origin/main one merge at a time and never resolved: a PR that conflicts with main is sent
#   back; one that conflicts only with an earlier member waits for the next pass, where a CHANGELOG-only
#   conflict with the member that landed takes the solo path.
# - The composed object is gated once by `full.sh`. Green: it is pushed exactly, with
#   `--force-with-lease` on the base it was built on, and every member gets an acceptance comment.
#   When the gate's `xbackend diff:` line reports `new-paths=N new-rows=M` above zero, the pushed object
#   is the gated one plus ONE commit moving scripts/xbackend_diff.baseline by exactly N and M, made and
#   checked by the base's `land.sh --xbackend-follow` (its PHASE 6c, #1383) and naming every member;
#   without it every next gate on main would be red on the ratchet alone. Zero coverage, no commit.
#   A refused baseline commit pushes nothing and labels every member `queue-failed` (#1386).
#   Red: the set is bisected — its first half is gated alone, recursively — so a red PR is isolated
#   and marked `queue-failed` with its log tail, while the PRs that are green land. Every refusal and
#   `queue-failed` relabel also writes one `#N refused at <stage> on <sha8>: <reason>` line to queue.log
#   (#1368).
# - A failure that is not the PR's (provenance of main, a fetch, the tree moving, a busy box) ends the
#   pass and changes no label: the PRs stay queued for the next one.
#
# ## Trust
#
# The boundary is the §2 review that precedes `--enqueue`: the gate compiles and runs the PR's code as
# the queue's own user, which can read that user's files (~/.ssh, ~/.config/gh) and write the
# checkout's .git. What the script adds is defence in depth only: the timer runs main's copy of this
# script and main's land.sh, never a batch's; the batch gate runs without GH_TOKEN/GITHUB_TOKEN, global
# git config or gh config; every push is the queue's own `--no-verify` step after the gate exited.
#
# ## Usage
#
#   scripts/queue.sh --enqueue N=SHA ...  (the integrator, after reviewing head SHA) label + marker;
#                                         refused when the PR's head is no longer SHA
#   scripts/queue.sh --status             the queue, and whether each PR's last verdict names its head
#   scripts/queue.sh --once               one pass (what the timer runs on omen)
#   scripts/queue.sh --install            from the dedicated checkout .worktrees/queue on omen: write
#                                         and start the systemd user timer
#   scripts/queue.sh --self-test          the deciders: marker, entry rules, gate verdict, push
#                                         arguments, busy box, bisection plan
#
#   ALATYR_QUEUE_DRY=1       --once screens, composes and gates but neither pushes, labels nor comments
#   ALATYR_QUEUE_DRY=screen  as 1, and no gate runs (each counted green): a check of the plumbing
set -u

SELF="$0"
## The timer runs a copy under target/queue/ (so a `git switch` cannot rewrite the running file, the
## #1093 hazard), so the root is the enclosing checkout, not the script's parent directory.
ROOT="$(git -C "$(dirname "$SELF")" rev-parse --show-toplevel 2>/dev/null || (cd "$(dirname "$SELF")/.." && pwd))"
REPO="${ALATYR_REPO:-alatyr-programming-language/compiler}"
QUEUE_MAX="${ALATYR_QUEUE_MAX:-4}"
DRY="${ALATYR_QUEUE_DRY:-0}"
QDIR="$ROOT/target/queue"

say() { printf '%s queue: %s\n' "$(date -u +%FT%TZ)" "$*"; }
## Every refusal and every queue-failed relabel also leaves a queue.log line (#1368), so the log alone
## gives each PR's verdict on its head; the PR comment carries the detail.
refused() { say "#$1 refused at $2 on ${3:0:8}: $4"; } # pr stage head reason
die() { printf 'queue: %s\n' "$*" >&2; exit 2; }
prs_h() { printf '#%s ' "$@" | sed 's/ $//'; }

# ---- deciders (pure; held by --self-test) ---------------------------------------------------------

## The reviewed head. Input: one line per comment line, `<authorAssociation><TAB><line>`, oldest
## first. The answer is the LAST `queue-head: <40-hex>` line whose author is OWNER, MEMBER or
## COLLABORATOR; nothing when there is none.
queue_marker_head() { # assoc-lines -> sha or nothing
  printf '%s\n' "$1" | awk -F'\t' '
    ($1 == "OWNER" || $1 == "MEMBER" || $1 == "COLLABORATOR") &&
    $2 ~ /^queue-head: [0-9a-f]+[[:space:]]*$/ {
      s = $2; sub(/^queue-head: /, "", s); sub(/[[:space:]]+$/, "", s)
      if (length(s) == 40) h = s
    }
    END { if (h != "") print h }'
}

## May this PR enter a batch at all? Prints the reason it may not, or nothing.
queue_entry_refusal() { # base-ref is-draft labels(comma) body
  [ "$1" = main ] || { echo "it targets '$1', not main"; return; }
  [ "$2" = false ] || { echo "it is a draft"; return; }
  case ",$3," in *,hold,*) echo "it carries the hold label"; return ;; esac
  local n
  n="$(printf '%s\n' "$4" | grep -c -E '^(Closes|Fixes|Resolves|Refs) #[0-9]+' || true)"
  [ "$n" = 1 ] || echo "its body has $n line-initial relation markers; exactly one is required"
}

## The issue link the merge commit will carry: the ONE line-initial relation marker, normalised. The
## queue refuses a PR whose land.sh link (first match anywhere, any case) differs from this one.
queue_relation_link() { # body -> "Closes #N" etc., or nothing
  printf '%s\n' "$1" | sed -n -E 's/^(Closes|Fixes|Resolves|Refs) #([0-9]+).*$/\1 #\2/p' | head -n 1
}

## Is the fetched object the reviewed one?
queue_head_ok() { [ -n "$1" ] && [ "$1" = "$2" ]; } # expected fetched

## Green means exit 0 AND the gate's own green verdict line; either alone is not enough.
queue_gate_green() { # rc log
  [ "$1" = 0 ] && grep -q '^\*\*\* FULL GATE: GREEN (sweeps RAN) \*\*\*' "$2" 2>/dev/null
}
## 0 green; 1 red — a non-zero exit WITH the gate's own failure verdict, so the PRs are to blame;
## 2 anything else (nix develop failed, the disk filled, a refusal before any stage): not the PRs'.
queue_gate_verdict() { # rc log
  queue_gate_green "$1" "$2" && return 0
  [ "$1" != 0 ] && grep -q '^\*\*\* FULL GATE: FAILURES \*\*\*' "$2" 2>/dev/null && return 1
  return 2
}

## What a solo `land.sh N` run (no --push) decided, from its log. Prints one of:
##   green <sha>  exactly one GATE GREEN line naming a full object id
##   red          the gate or the PR's predicted oracle failed: the PR's fault
##   refused      PR shape, a conflict with main, or the screen (fork)
##   moved        the head moved past the reviewed one
##   infra        anything else (provenance, a tree that moved, a nondeterministic walk, …)
queue_solo_outcome() { # log
  local g
  g="$(sed -n 's/^\*\*\* GATE GREEN on the merged tree — \([0-9a-f]\{40\}\) is landable \*\*\*$/\1/p' "$1" 2>/dev/null)"
  if [ -n "$g" ] && [ "$(printf '%s\n' "$g" | wc -l | tr -d ' ')" = 1 ]; then echo "green $g"; return; fi
  if grep -q -E '^\*\*\* NOT LANDABLE — gate rc [1-9][0-9]*, post-gate assertions ok \*\*\*$' "$1" &&
     grep -q '^\*\*\* FULL GATE: FAILURES \*\*\*' "$1"; then echo red; return; fi
  if grep -q -e '^\*\*\* NOT LANDABLE — the fresh manifest does not realise' \
             -e '^\*\*\* NOT LANDABLE — the predicted oracle failed its checks' \
             -e '^\*\*\* NOT LANDABLE — the corpus pre-walk does not realise' "$1"; then echo red; return; fi
  if grep -q -e '^\*\*\* LAND REFUSED (PR shape)' -e '^\*\*\* LAND REFUSED (the merge conflicts)' \
             -e '^\*\*\* LAND REFUSED (screen)' "$1"; then echo refused; return; fi
  if grep -q '^\*\*\* LAND REFUSED (head moved)' "$1"; then echo moved; return; fi
  echo infra
}

## The push of a gated object: that object, onto main, leased on the base it was composed on, hooks off.
queue_push_args() { # object base
  printf '%s\n' "--no-verify origin $1:refs/heads/main --force-with-lease=refs/heads/main:$2"
}

## What `land.sh --xbackend-follow` (#1383) said the batch must publish. Prints the object: the gated
## one when the gate added no coverage (`xbackend-follow: none`), the baseline commit when it did; fails
## on anything else — a refusal, no verdict line, two, or an abbreviated sha. The queue then re-checks
## that commit's parent and file set itself before pushing it.
queue_follow_object() { # land-output gated-object -> object; 1 none decidable
  local last c
  last="$(printf '%s\n' "$1" | grep '^xbackend-follow: ')"
  [ "$(printf '%s\n' "$last" | grep -c .)" = 1 ] || return 1
  [ "$last" = 'xbackend-follow: none' ] && { echo "$2"; return 0; }
  c="$(printf '%s\n' "$last" | sed -n 's/^xbackend-follow: commit \([0-9a-f]\{40\}\) paths+[0-9][0-9]* rows+[0-9][0-9]*$/\1/p')"
  [ -n "$c" ] && [ "$c" != "$2" ] || return 1
  echo "$c"
}

## Is a full gate running on this box? Input: `ps -eo args=`. Only a bash running scripts/full.sh
## counts — not an editor, a pager or an ssh command line that mentions the file.
queue_gate_running() { # ps-args-text -> 0 running, 1 not
  printf '%s\n' "$1" | awk '$1 ~ /(^|\/)bash$/ && $2 ~ /(^|\/)scripts\/full\.sh$/ { f = 1 } END { exit !f }'
}

## Strikes: a failure that is not visibly the PR's can still be caused by it (a PR that breaks
## `nix develop`, or makes the corpus walk nondeterministic). The first one ends the pass quietly; the
## SECOND in a row for the same PRs at the same heads is charged to them, so no PR blocks the queue by
## failing the same way every pass. Keyed by the PR=head list; a verdict clears it.
queue_strike() { # dir key -> prints the count after this strike
  local f="$1/strike-$(printf '%s' "$2" | cksum | cut -d' ' -f1)" n=0
  [ -f "$f" ] && n="$(cat "$f")"
  n=$((n + 1)); printf '%s\n' "$n" > "$f"; echo "$n"
}
queue_strike_clear() { rm -f "$1/strike-$(printf '%s' "$2" | cksum | cut -d' ' -f1)"; } # dir key

## The bisection driver. It calls three functions the caller defines:
##   queue_try PR...   0 green, 1 red, 2 not the PRs' fault (ends the pass, everything stays queued)
##   queue_land PR...  publish the object queue_try last built for exactly these PRs
##   queue_fail PR     mark one PR red
## A red set of n>1 is narrowed to its first floor(n/2); the rest wait behind it in the same pass, so
## a red PR in [a r c] costs five gates: [a r c] red, [a] green and lands, [r c] red, [r] red and
## fails, [c] green and lands.
queue_drive() { # PR...
  local set=("$@") rest=() h
  while [ "${#set[@]}" -gt 0 ]; do
    queue_try "${set[@]}"
    case $? in
      0) queue_land "${set[@]}" || return 0
         set=(${rest[@]+"${rest[@]}"}); rest=() ;;
      1) if [ "${#set[@]}" = 1 ]; then
           queue_fail "${set[0]}"
           set=(${rest[@]+"${rest[@]}"}); rest=()
         else
           h=$(( ${#set[@]} / 2 ))
           rest=("${set[@]:h}" ${rest[@]+"${rest[@]}"})
           set=("${set[@]:0:h}")
         fi ;;
      *) return 0 ;;
    esac
  done
}

QUEUE_SELFTEST_EXPECTED=62  # the exact count run, compared with -ne like land.sh's; 49, +6 #1383, +7 #1386
queue_self_test() {
  local k=0 bad="" log t
  _ck() { k=$((k+1)); [ "$1" = 0 ] || bad="$bad $2"; }
  local a=1111111111111111111111111111111111111111 b=2222222222222222222222222222222222222222
  t="$(printf 'OWNER\treview ok\nOWNER\tqueue-head: %s\nMEMBER\tqueue-head: %s\nCONTRIBUTOR\tqueue-head: %s' "$a" "$b" "$a")"
  [ "$(queue_marker_head "$t")" = "$b" ]; _ck $? marker-did-not-take-the-last-trusted-head
  [ "$(queue_marker_head "$(printf 'NONE\tqueue-head: %s' "$a")")" = "" ]; _ck $? marker-trusted-an-outside-author
  [ -z "$(queue_marker_head "$(printf 'OWNER\tqueue-head: %s' "${a:0:12}")")" ]; _ck $? marker-took-an-abbreviated-sha
  [ -z "$(queue_marker_head "$(printf 'OWNER\tsee queue-head: %s' "$a")")" ]; _ck $? marker-took-a-mid-line-mention
  [ -z "$(queue_marker_head "")" ]; _ck $? marker-invented-a-head
  # Entry rules, each refusal and the one acceptance.
  [ -z "$(queue_entry_refusal main false "" "x

Closes #1")" ]; _ck $? entry-refused-a-ready-PR
  [ -n "$(queue_entry_refusal release false "" "Closes #1")" ]; _ck $? entry-took-a-PR-into-another-branch
  [ -n "$(queue_entry_refusal main true "" "Closes #1")" ]; _ck $? entry-took-a-draft
  [ -n "$(queue_entry_refusal main false "pilot,hold" "Closes #1")" ]; _ck $? entry-took-a-held-PR
  [ -n "$(queue_entry_refusal main false "" "fixes the bug")" ]; _ck $? entry-took-a-PR-with-no-marker
  [ -n "$(queue_entry_refusal main false "" "Closes #1
Refs #2")" ]; _ck $? entry-took-a-PR-with-two-markers
  [ -n "$(queue_entry_refusal main false "" "this Closes #1 mid-line")" ]; _ck $? entry-took-a-mid-line-marker
  [ "$(queue_relation_link "$(printf 'Partly Fixes #5 too, and Closes #9 mid-line.\n\nRefs #1127')")" = "Refs #1127" ]; _ck $? link-not-the-line-initial-marker
  [ "$(queue_relation_link "$(printf 'x\nCloses #7 (all of it)')")" = "Closes #7" ]; _ck $? link-not-normalised
  queue_head_ok "$a" "$a"; _ck $? head-check-refused-the-reviewed-head
  queue_head_ok "$a" "$b"; [ $? = 1 ]; _ck $? head-check-took-a-moved-head
  queue_head_ok "" ""; [ $? = 1 ]; _ck $? head-check-took-no-head
  # The gate verdict needs both the exit code and the line.
  mkdir -p "$ROOT/target" && t="$(mktemp -d "$ROOT/target/queue-selftest.XXXXXX")" || return 1
  printf 'stuff\n*** FULL GATE: GREEN (sweeps RAN) ***\n' > "$t/green"
  printf 'stuff\n*** FULL GATE: FAILURES ***\n' > "$t/red"
  queue_gate_green 0 "$t/green"; _ck $? gate-verdict-refused-a-green-gate
  queue_gate_green 0 "$t/red"; [ $? = 1 ]; _ck $? gate-verdict-took-rc0-without-the-green-line
  queue_gate_green 1 "$t/green"; [ $? = 1 ]; _ck $? gate-verdict-took-a-green-line-with-rc1
  ! queue_gate_green 0 "$t/none"; _ck $? gate-verdict-took-a-missing-log
  queue_gate_verdict 1 "$t/red"; [ $? = 1 ]; _ck $? gate-verdict-did-not-blame-a-red-gate
  printf 'error: nix develop failed\n' > "$t/died"
  queue_gate_verdict 1 "$t/died"; [ $? = 2 ]; _ck $? gate-verdict-blamed-the-PRs-for-a-gate-that-never-ran
  # The solo outcomes, one log each.
  printf '*** FULL GATE: GREEN (sweeps RAN) ***\n\n*** GATE GREEN on the merged tree — %s is landable ***\n' "$a" > "$t/s-green"
  [ "$(queue_solo_outcome "$t/s-green")" = "green $a" ]; _ck $? solo-missed-green
  printf '*** GATE GREEN on the merged tree — %s is landable ***\n*** GATE GREEN on the merged tree — %s is landable ***\n' "$a" "$b" > "$t/s-two"
  [ "$(queue_solo_outcome "$t/s-two")" = infra ]; _ck $? solo-took-two-green-objects
  printf '*** FULL GATE: FAILURES ***\n\n*** NOT LANDABLE — gate rc 1, post-gate assertions ok ***\n' > "$t/s-red"
  [ "$(queue_solo_outcome "$t/s-red")" = red ]; _ck $? solo-missed-red
  printf '  pre-walk MISMATCH |   MISPREDICTED x\n\n*** NOT LANDABLE — the corpus pre-walk does not realise the rebased scripts/corpus.expected-delta; the full gate was not run ***\n' > "$t/s-prewalk"
  [ "$(queue_solo_outcome "$t/s-prewalk")" = red ]; _ck $? solo-missed-a-pre-walk-refusal-of-a-rebased-delta
  printf '*** FULL GATE: GREEN (sweeps RAN) ***\n\n*** NOT LANDABLE — gate rc 0, post-gate assertions FAILED ***\n' > "$t/s-moved-tree"
  [ "$(queue_solo_outcome "$t/s-moved-tree")" = infra ]; _ck $? solo-blamed-the-PR-for-a-tree-that-moved
  printf '*** NOT LANDABLE — a second walk of the same tree did not reproduce the oracle (rc 1) ***\n' > "$t/s-walk"
  [ "$(queue_solo_outcome "$t/s-walk")" = infra ]; _ck $? solo-blamed-the-PR-for-a-nondeterministic-walk
  printf '*** FULL GATE: FAILURES ***\n\n*** NOT LANDABLE — gate rc 1, post-gate assertions FAILED ***\n' > "$t/s-red-moved"
  [ "$(queue_solo_outcome "$t/s-red-moved")" = infra ]; _ck $? solo-blamed-the-PR-for-a-red-gate-on-a-moved-tree
  printf 'error: nix develop failed\n\n*** NOT LANDABLE — gate rc 1, post-gate assertions ok ***\n' > "$t/s-died"
  [ "$(queue_solo_outcome "$t/s-died")" = infra ]; _ck $? solo-blamed-the-PR-for-a-gate-that-never-ran
  printf '\n*** LAND REFUSED (PR shape) — nothing was merged ***\n' > "$t/s-shape"
  [ "$(queue_solo_outcome "$t/s-shape")" = refused ]; _ck $? solo-missed-a-shape-refusal
  printf '\n*** LAND REFUSED (head moved) — x ***\n' > "$t/s-head"
  [ "$(queue_solo_outcome "$t/s-head")" = moved ]; _ck $? solo-missed-a-moved-head
  printf '\n*** LAND REFUSED (provenance of main) — nothing was merged ***\n' > "$t/s-prov"
  [ "$(queue_solo_outcome "$t/s-prov")" = infra ]; _ck $? solo-blamed-the-PR-for-provenance
  [ "$(queue_strike "$t" "1=$a")" = 1 ] && [ "$(queue_strike "$t" "1=$a")" = 2 ] && [ "$(queue_strike "$t" "1=$b")" = 1 ]
  _ck $? strikes-not-counted-per-PR-and-head
  queue_strike_clear "$t" "1=$a"; [ "$(queue_strike "$t" "1=$a")" = 1 ]; _ck $? strikes-not-cleared-by-a-verdict
  rm -rf "$t"
  [ "$(queue_push_args "$a" "$b")" = "--no-verify origin $a:refs/heads/main --force-with-lease=refs/heads/main:$b" ]
  _ck $? push-arguments-are-not-the-leased-exact-object
  # The batch's xbackend baseline commit (#1383): coverage publishes the commit, none the gated object.
  [ "$(queue_follow_object "$(printf '  the gate: x\nxbackend-follow: none')" "$a")" = "$a" ]; _ck $? follow-zero-coverage-did-not-publish-the-gated-object
  [ "$(queue_follow_object "xbackend-follow: commit $b paths+2 rows+6" "$a")" = "$b" ]; _ck $? follow-coverage-did-not-publish-the-baseline-commit
  ! queue_follow_object "$(printf '  REFUSE: the baseline commit changes {a b}\n')" "$a" >/dev/null; _ck $? follow-took-a-refusal-as-a-verdict
  ! queue_follow_object "$(printf 'xbackend-follow: none\nxbackend-follow: commit %s paths+1 rows+1' "$b")" "$a" >/dev/null; _ck $? follow-took-two-verdicts
  ! queue_follow_object "xbackend-follow: commit ${b:0:12} paths+1 rows+1" "$a" >/dev/null; _ck $? follow-took-an-abbreviated-commit
  ! queue_follow_object "xbackend-follow: commit $a paths+1 rows+1" "$a" >/dev/null; _ck $? follow-took-the-gated-object-as-its-own-baseline-commit
  # queue_follow's own recheck, driven with land.sh's report stubbed (#1386). Each wrong commit has the
  # right numbers and fails exactly ONE clause: an empty commit between it and the gated object (parent),
  # a second parent (count), a second file (path set). DRY=screen gated nothing and must not run land.sh.
  local here="$PWD" xg xp xe xok xpar xtwo xfile qd="$DRY" qb="$BUILT" qbb="$BUILT_BASE" qbf="$BUILT_FOR" qgl="$GATE_LOG" lt
  t="$(mktemp -d "$ROOT/target/queue-selftest.XXXXXX")" && cd "$t" && git init -q . || { cd "$here"; return 1; }
  export GIT_AUTHOR_NAME=st GIT_AUTHOR_EMAIL=st@example.invalid GIT_COMMITTER_NAME=st GIT_COMMITTER_EMAIL=st@example.invalid
  mkdir scripts && printf 'paths=1\nrows=1\n' > scripts/xbackend_diff.baseline && printf 'x\n' > other &&
    git add -A && xg="$(git commit-tree "$(git write-tree)" -m g)" &&
    xe="$(git commit-tree "$xg^{tree}" -p "$xg" -m e)" &&
    printf 'paths=3\nrows=7\n' > scripts/xbackend_diff.baseline && git add -A && xp="$(git write-tree)" &&
    xok="$(git commit-tree "$xp" -p "$xg" -m ok)" && xpar="$(git commit-tree "$xp" -p "$xe" -m par)" &&
    xtwo="$(git commit-tree "$xp" -p "$xg" -p "$xe" -m two)" &&
    printf 'y\n' > other && git add -A && xfile="$(git commit-tree "$(git write-tree)" -p "$xg" -m file)" ||
    { cd "$here"; return 1; }
  queue_follow_run() { echo run >> "$t/ran"; printf 'xbackend-follow: commit %s paths+2 rows+6\n' "${QF_C:-}"; }
  qf() { QF_C="$1" DRY=0 BUILT="$xg" GATE_LOG="$t/gate.log"; queue_follow 1309 2>/dev/null; } # commit -> what the queue would publish
  [ "$(qf "$xok")" = "$xok" ]; _ck $? follow-refused-the-one-child-moving-the-baseline-alone
  [ "$(qf "$xpar")" = "" ] && [ "$(qf "$xpar" >/dev/null; echo $?)" = 1 ]; _ck $? follow-took-a-commit-on-another-parent
  [ "$(qf "$xtwo")" = "" ] && [ "$(qf "$xtwo" >/dev/null; echo $?)" = 1 ]; _ck $? follow-took-a-two-parent-commit
  [ "$(qf "$xfile")" = "" ] && [ "$(qf "$xfile" >/dev/null; echo $?)" = 1 ]; _ck $? follow-took-a-commit-changing-a-second-file
  rm -f "$t/ran"; [ "$(DRY=screen; BUILT="$xg"; queue_follow 1309 2>/dev/null)" = "$xg" ] && [ ! -e "$t/ran" ]
  _ck $? follow-under-dry-screen-ran-land-or-published-another-object
  # A refused baseline commit after a green batch labels every member once; it cannot start, nothing.
  comment() { echo "comment:$1" >> "$t/ql"; }; relabel() { echo "relabel:$1 +$2 -$3" >> "$t/ql"; }
  queue_publish() { echo "publish:$1" >> "$t/ql"; }; queue_accept() { echo accept >> "$t/ql"; }
  queue_follow_run() { echo '  REFUSE: the parent baseline is malformed'; }
  DRY=0 BUILT="$xg" BUILT_FOR="1 3" GATE_LOG="$t/gate.log"; HEAD[1]="$a"; HEAD[3]="$b"; : > "$t/ql"
  queue_land 1 3 > "$t/qland.out" 2>/dev/null; lt=$?
  [ "$lt" = 1 ] && [ "$(tr '\n' ';' < "$t/ql")" = 'comment:1;relabel:1 +queue-failed -queue;comment:3;relabel:3 +queue-failed -queue;' ] &&
    [ "$(grep -c ' queue: #[13] refused at follow on ' "$t/qland.out")" = 2 ]
  _ck $? "follow-refusal-did-not-label-each-member-once($(tr '\n' ';' < "$t/ql"))"
  queue_follow_run() { return 2; }; : > "$t/ql"
  queue_land 1 3 > "$t/qland.out" 2>/dev/null; lt=$?
  [ "$lt" = 1 ] && [ ! -s "$t/ql" ]; _ck $? "follow-that-could-not-start-labelled-or-published($(tr '\n' ';' < "$t/ql"))"
  unset -f qf comment relabel queue_publish queue_accept queue_follow_run; unset 'HEAD[1]' 'HEAD[3]' QF_C
  DRY="$qd" BUILT="$qb" BUILT_BASE="$qbb" BUILT_FOR="$qbf" GATE_LOG="$qgl"
  unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
  cd "$here"; rm -rf "$t"
  queue_gate_running "bash scripts/full.sh --force-sweeps"; _ck $? busy-box-missed-a-relative-gate
  queue_gate_running "$(printf 'vim x\n/run/current-system/sw/bin/bash /h/c/scripts/full.sh')"; _ck $? busy-box-missed-an-absolute-gate
  queue_gate_running "$(printf "ssh omen-wan cd c && bash scripts/full.sh\nvim scripts/full.sh\nbash -c tail scripts/full.sh")"
  [ $? = 1 ]; _ck $? busy-box-counted-a-mention-as-a-gate
  # The driver, against a fake gate in which only PR 2 is red.
  log=""
  queue_try()  { log="$log try:$*;"; case " $* " in *' 2 '*) return 1 ;; esac; return 0; }
  queue_land() { log="$log land:$*;"; }
  queue_fail() { log="$log fail:$*;"; }
  queue_drive 1 2 3
  [ "$log" = " try:1 2 3; try:1; land:1; try:2 3; try:2; fail:2; try:3; land:3;" ]
  _ck $? "bisection-plan-for-a-red-middle-PR($log)"
  log=""; queue_drive 1 3 4; [ "$log" = " try:1 3 4; land:1 3 4;" ]; _ck $? "green-batch-not-landed-whole($log)"
  log=""; queue_drive 2; [ "$log" = " try:2; fail:2;" ]; _ck $? "lone-red-PR-not-failed($log)"
  log=""; queue_drive 1 2; [ "$log" = " try:1 2; try:1; land:1; try:2; fail:2;" ]; _ck $? "pair-bisection($log)"
  # Four PRs, the first red: the deferred halves nest, and the older one must survive.
  queue_try()  { log="$log try:$*;"; case " $* " in *' 1 '*) return 1 ;; esac; return 0; }
  log=""; queue_drive 1 2 3 4
  [ "$log" = " try:1 2 3 4; try:1 2; try:1; fail:1; try:2 3 4; land:2 3 4;" ]; _ck $? "nested-deferral($log)"
  # An infrastructure failure or a failed publish AFTER a split still ends the pass.
  queue_try()  { log="$log try:$*;"; case "$*" in '1 2 3') return 1 ;; esac; return 2; }
  log=""; queue_drive 1 2 3; [ "$log" = " try:1 2 3; try:1;" ]; _ck $? "infrastructure-failure-after-a-split-did-not-end-the-pass($log)"
  queue_try()  { log="$log try:$*;"; case "$*" in '1 2 3') return 1 ;; esac; return 0; }
  queue_land() { log="$log land:$*;"; return 1; }
  log=""; queue_drive 1 2 3; [ "$log" = " try:1 2 3; try:1; land:1;" ]; _ck $? "failed-publish-after-a-split-did-not-end-the-pass($log)"
  queue_land() { log="$log land:$*;"; }
  queue_try() { log="$log try:$*;"; return 2; }
  log=""; queue_drive 1 3; [ "$log" = " try:1 3;" ]; _ck $? "infrastructure-failure-did-not-end-the-pass($log)"
  queue_try() { log="$log try:$*;"; return 0; }
  queue_land() { log="$log land:$*;"; return 1; }
  log=""; queue_drive 1 3; [ "$log" = " try:1 3; land:1 3;" ]; _ck $? "failed-publish-did-not-end-the-pass($log)"
  unset -f queue_try queue_land queue_fail
  if [ -n "$bad" ]; then echo "*** queue self-test: FAILED —$bad ***"; return 1; fi
  if [ "$k" -ne "$QUEUE_SELFTEST_EXPECTED" ]; then
    echo "*** queue self-test: ran $k checks, expected exactly $QUEUE_SELFTEST_EXPECTED: a check was lost or added uncounted ***"
    return 1
  fi
  echo "ok   queue self-test: $k checks — reviewed-head marker, entry rules, head check, gate verdict,"
  echo "     push arguments, the xbackend baseline commit and its refusal, busy box and the bisection plan"
}

# ---- GitHub ------------------------------------------------------------------------------------------
gh_cmd() { command -v gh >/dev/null 2>&1 || die "gh is required"; gh "$@"; }
comment() { # pr body
  if [ "$DRY" != 0 ]; then printf -- '--- (dry) comment on #%s:\n%s\n' "$1" "$2"; return 0; fi
  gh_cmd pr comment "$1" -R "$REPO" --body "$2" >/dev/null || say "could not comment on #$1"
}
relabel() { # pr add remove
  [ "$DRY" != 0 ] && return 0
  [ -n "$2" ] && { gh_cmd pr edit "$1" -R "$REPO" --add-label "$2" >/dev/null || say "could not add $2 to #$1"; }
  [ -n "$3" ] && { gh_cmd pr edit "$1" -R "$REPO" --remove-label "$3" >/dev/null 2>&1 || true; }
  return 0
}
pr_field() { gh_cmd pr view "$1" -R "$REPO" --json "$2" --jq "$3"; } # pr json-field jq
pr_marker() { # pr -> reviewed head; non-zero when GitHub could not be read. Paginated: a marker
  local c   # posted after the 100th comment must still count.
  c="$(gh_cmd api --paginate "repos/$REPO/issues/$1/comments" \
        --jq '.[] | .author_association as $a | .body | split("\n")[] | "\($a)\t\(.)"')" || return 2
  queue_marker_head "$c"
}

# ---- one pass ----------------------------------------------------------------------------------------
## One gate per box: two at once share /tmp and the CPU, and each makes the other's scratch wrong.
wait_for_box() {
  local n=0
  while queue_gate_running "$(ps -eo args= 2>/dev/null)"; do
    [ "$n" = 0 ] && say "another full gate is running on this box; waiting"
    n=$((n+1)); [ "$n" -le 180 ] || { say "box still busy after 3 h; ending the pass"; return 1; }
    sleep 60
  done
}

BUILT_FOR=""; BUILT=""; BUILT_BASE=""; GATE_LOG=""
HEAD=(); LINK=(); BRANCH=()   # indexed by PR number

queue_try() { # PR... — compose onto origin/main and gate
  [ "$DRY" = screen ] || wait_for_box || return 2   # before the base is read: a long wait would void the lease
  git fetch --quiet origin main || return 2
  local base pr msg
  base="$(git rev-parse origin/main)"
  git switch --quiet --detach "$base" || return 2
  for pr in "$@"; do
    git fetch --quiet origin "+refs/pull/$pr/head:refs/remotes/pr/$pr" || return 2
    queue_head_ok "${HEAD[$pr]}" "$(git rev-parse "refs/remotes/pr/$pr")" ||
      { say "#$pr moved after its screen; this pass ends"; return 2; }
    msg="merge #$pr: ${BRANCH[$pr]}"
    [ -n "${LINK[$pr]}" ] && msg="$msg

${LINK[$pr]}"
    git merge --quiet --no-ff --no-verify -m "$msg" "refs/remotes/pr/$pr" >/dev/null 2>&1 ||
      { git merge --abort 2>/dev/null; say "#$pr no longer composes onto $base; this pass ends"; return 2; }
  done
  BUILT="$(git rev-parse HEAD)"; BUILT_BASE="$base"; BUILT_FOR="$*"
  GATE_LOG="$QDIR/gate-$(date -u +%Y%m%dT%H%M%S)-$(git rev-parse --short HEAD).log"
  if [ "$DRY" = screen ]; then say "(dry=screen) composed $BUILT for $(prs_h "$@"); no gate"; return 0; fi
  say "gating $BUILT (base $base) for $(prs_h "$@"); log $GATE_LOG"
  local empty_gh rc; empty_gh="$(mktemp -d "$QDIR/gh-empty.XXXXXX")"
  ( ulimit -c 0
    env -u GH_TOKEN -u GITHUB_TOKEN GIT_CONFIG_GLOBAL=/dev/null GH_CONFIG_DIR="$empty_gh" \
      nix develop -c bash scripts/full.sh --force-sweeps ) > "$GATE_LOG" 2>&1 9>&-
  rc=$?
  rm -rf "$empty_gh"
  git diff --exit-code --quiet && git diff --cached --exit-code --quiet &&
    [ "$(git rev-parse HEAD)" = "$BUILT" ] || { say "the tree moved during the gate; this pass ends"; return 2; }
  local key="" v; for pr in "$@"; do key="$key $pr=${HEAD[$pr]}"; done
  queue_gate_verdict "$rc" "$GATE_LOG"; v=$?
  case $v in
    0) queue_strike_clear "$QDIR" "$key"; say "GREEN on $BUILT"; return 0 ;;
    1) queue_strike_clear "$QDIR" "$key"; say "RED (full.sh rc $rc) on $BUILT"; return 1 ;;
  esac
  if [ "$(queue_strike "$QDIR" "$key")" -ge 2 ]; then
    queue_strike_clear "$QDIR" "$key"
    say "the gate on $BUILT ended with no verdict twice for the same heads; charged to them as red"; return 1
  fi
  say "the gate on $BUILT ended with no verdict (rc $rc); this pass ends, see $GATE_LOG"; return 2
}

gate_line() { grep -m1 '^\*\*\* FULL GATE' "$1" 2>/dev/null || echo '(no verdict line)'; }

## After a push: one acceptance per PR, labels off, the PR's snapshot ref and branch removed.
queue_accept() { # how object base log PR...
  local how="$1" obj="$2" base="$3" log="$4" pr branch; shift 4
  git fetch --quiet origin main || say "fetch after the push failed; acceptance continues on the pushed object"
  for pr in "$@"; do
    comment "$pr" "**Landed by the merge queue** (\`scripts/queue.sh\`, #1127, $how), no agent session attached.

- reviewed head: \`${HEAD[$pr]}\` (the \`queue-head\` marker; the object gated)
- members: $(prs_h "$@"), composed onto \`$base\`; \`main\` is now \`$obj\`
- gate on omen, on that exact object: \`$(gate_line "$log")\` (log \`$(basename "$log")\` under \`target/queue/\` on omen)
$(git diff --quiet "$obj^" "$obj" -- scripts/xbackend_diff.baseline 2>/dev/null || echo "- xbackend baseline: \`$obj\` moves it by the gate's newly covered paths and rows, alone, on the gated object (#1383)")
- check: \`git merge-base --is-ancestor $obj origin/main\`
${LINK[$pr]:+- issue: ${LINK[$pr]}}"
    relabel "$pr" "" queue
    relabel "$pr" "" in-progress
    git update-ref -d "refs/remotes/pr/$pr" 2>/dev/null
    branch="${BRANCH[$pr]}"
    if [ "$DRY" = 0 ] && git merge-base --is-ancestor "${HEAD[$pr]}" "$obj" &&
       [ "$(git ls-remote origin "refs/heads/$branch" | cut -f1)" = "${HEAD[$pr]}" ]; then
      git push --quiet --no-verify origin --delete "$branch" || say "could not delete $branch (left in place)"
    fi
  done
}

queue_publish() { # object base -> 0 pushed, 1 not
  if [ "$DRY" != 0 ]; then say "(dry) would push $1 over $2"; return 0; fi
  # shellcheck disable=SC2046
  git push --quiet $(queue_push_args "$1" "$2") || { say "push rejected: main moved after $2; the PRs stay queued"; return 1; }
  say "LANDED $1"
}

## The batch's xbackend baseline commit (#1383): land.sh PHASE 6c, run from the BASE's copy of
## land.sh (the checkout moves to the base first; the batch's own scripts never run outside the gate),
## on the gated object, from the gate's own log. Prints land.sh's report; 2 when it could not start.
queue_follow_run() { # PR...
  git switch --quiet --detach "$BUILT_BASE" || return 2
  env -u GH_TOKEN -u GITHUB_TOKEN bash scripts/land.sh --xbackend-follow "$BUILT" "$GATE_LOG" "$@" 2>&1 9>&-
  return 0
}
## The queue's own check of the commit land.sh made, independent of land.sh's: its ONE parent is the
## gated object and the baseline is the only file it changes. Same-shape refusals as land.sh's
## xb_follow_commit_check, so a base whose land.sh lost one still cannot publish a wrong object.
queue_follow_commit_ok() { # gated commit -> 0 ok, 1 not
  [ "$(git rev-list --parents -n 1 "$2" 2>/dev/null | wc -w | tr -d ' ')" = 2 ] &&
    [ "$(git rev-parse "$2^" 2>/dev/null)" = "$1" ] &&
    [ "$(git diff --name-only "$1" "$2" 2>/dev/null)" = scripts/xbackend_diff.baseline ]
}
## Prints the object to publish: BUILT (no coverage, or DRY=screen, which gated nothing) or its checked
## baseline commit. 1 = refused: the same inputs would refuse again, so the caller labels the members
## (land.sh's report is in "$GATE_LOG.follow"); 2 = could not run, the pass ends and nothing changes.
queue_follow() { # PR...
  local out obj rc
  [ "$DRY" = screen ] && { echo "$BUILT"; return 0; }
  out="$(queue_follow_run "$@")"; rc=$?
  [ "$rc" = 0 ] || return 2
  printf '%s\n' "$out" > "$GATE_LOG.follow"
  printf '%s\n' "$out" | sed 's/^/  /' >&2
  obj="$(queue_follow_object "$out" "$BUILT")" || return 1
  if [ "$obj" != "$BUILT" ]; then
    queue_follow_commit_ok "$BUILT" "$obj" ||
      { echo "queue: $obj is not one commit on $BUILT changing scripts/xbackend_diff.baseline alone" >> "$GATE_LOG.follow"; return 1; }
  fi
  echo "$obj"
}
## A green batch whose baseline commit is refused would be re-gated every pass for the same refusal,
## about six minutes each time and silent. It leaves the queue instead, each member labelled.
queue_follow_failed() { # PR...
  local pr
  for pr in "$@"; do
    refused "$pr" follow "${HEAD[$pr]}" "the xbackend baseline commit on the green $BUILT was refused (#1383)"
    comment "$pr" "**Merge queue: refused after a green gate** on head \`${HEAD[$pr]}\` (\`scripts/queue.sh\`, #1383). Members $(prs_h "$@") were gated green as \`$BUILT\` (\`$(gate_line "$GATE_LOG")\`), but the xbackend baseline commit that must land with it was refused, so nothing was pushed. Its report (\`$(basename "$GATE_LOG").follow\` under \`target/queue/\` on omen):

\`\`\`
$(tail -n 15 "$GATE_LOG.follow" 2>/dev/null)
\`\`\`

Repair the cause (most often \`scripts/xbackend_diff.baseline\` on main) and re-enqueue."
    relabel "$pr" queue-failed queue
  done
}

queue_land() { # PR... — publish exactly BUILT, or BUILT plus its one-file xbackend baseline commit
  [ "$BUILT_FOR" = "$*" ] || die "internal: asked to land [$*] but built [$BUILT_FOR]"
  local obj rc
  obj="$(queue_follow "$@")"; rc=$?
  case "$rc" in
    0) ;;
    1) say "the xbackend baseline commit on $BUILT was refused (#1383); nothing pushed, the members leave the queue"
       queue_follow_failed "$@"; return 1 ;;
    *) say "could not run land.sh --xbackend-follow on $BUILT; nothing pushed, this pass ends"; return 1 ;;
  esac
  [ "$obj" != "$BUILT" ] && say "xbackend baseline commit $obj on the gated $BUILT"
  queue_publish "$obj" "$BUILT_BASE" || return 1
  queue_accept "batch" "$obj" "$BUILT_BASE" "$GATE_LOG" "$@"
}

queue_fail() { # PR
  local pr="$1"
  refused "$pr" gate "${HEAD[$pr]}" "red, isolated ($(gate_line "$GATE_LOG"))"
  comment "$pr" "**Merge queue: red** on head \`${HEAD[$pr]}\` (\`scripts/queue.sh\`, #1127).

Gated alone on \`$BUILT_BASE\` as \`$BUILT\`: \`$(gate_line "$GATE_LOG")\`. Log \`$(basename "$GATE_LOG")\` under \`target/queue/\` on omen; its failing lines:

\`\`\`
$(grep -E 'FAIL|MISMATCH|REFUSED|NOT LANDABLE|error' "$GATE_LOG" 2>/dev/null | tail -n 30)
\`\`\`

The label moved to \`queue-failed\`. Fix, push, and re-enqueue after review."
  relabel "$pr" queue-failed queue
}

## Which of the screened PRs compose onto origin/main, in order? One that conflicts with main alone is
## sent back for a rebase; one that conflicts only with an earlier member waits for the next pass. The
## queue never resolves a conflict: that is a semantic decision (alatyr-integrate §3).
COMPOSED=""
queue_compose_screen() { # PR...
  local base pr mt; COMPOSED=""
  git fetch --quiet origin main || return 0
  base="$(git rev-parse origin/main)"
  git switch --quiet --detach "$base" || return 0
  for pr in "$@"; do
    git fetch --quiet origin "+refs/pull/$pr/head:refs/remotes/pr/$pr" || continue
    if git merge --quiet --no-ff --no-verify -m "screen #$pr" "refs/remotes/pr/$pr" >/dev/null 2>&1; then
      COMPOSED="$COMPOSED $pr"; continue
    fi
    git merge --abort 2>/dev/null
    git merge-tree --write-tree "$base" "refs/remotes/pr/$pr" >/dev/null 2>&1; mt=$?
    case "$mt" in
      0) say "#$pr conflicts with an earlier member of this batch; it waits for the next pass" ;;
      1) refused "$pr" compose "${HEAD[$pr]}" "conflicts with main $base"
         comment "$pr" "**Merge queue: conflicts with main** on head \`${HEAD[$pr]}\`. Rebase onto \`$base\` and re-enqueue after review."
         relabel "$pr" queue-failed queue ;;
      *) say "git merge-tree failed (rc $mt) on #$pr; it waits for the next pass" ;;
    esac
  done
  git switch --quiet --detach "$base"
}

## A PR with an oracle file or a predicted delta is gated alone by land.sh, whose PHASE 6a owns that
## path (and PHASE 6c the xbackend baseline commit on any landing), on exactly the reviewed head.
## The queue pushes the object land.sh names; land.sh never pushes.
queue_solo() { # pr -> 0 done (landed, failed or dropped), 2 the pass ends
  local pr="$1" log="$QDIR/solo-$1-$(date -u +%Y%m%dT%H%M%S).log" out obj
  if [ "$DRY" = screen ]; then say "(dry=screen) #$pr would be landed alone"; return 0; fi
  wait_for_box || return 2
  say "solo landing #$pr (oracle or predicted delta) at ${HEAD[$pr]}; log $log"
  ( env -u GH_TOKEN -u GITHUB_TOKEN ALATYR_LAND_EXPECT_HEAD="${HEAD[$pr]}" bash scripts/land.sh "$pr" ) > "$log" 2>&1 9>&-
  GATE_LOG="$log"
  BUILT_BASE="$(sed -n 's/^  base=\([0-9a-f]\{40\}\)$/\1/p' "$log")"
  BUILT="$(sed -n 's/^  merged as \([0-9a-f]\{40\}\)$/\1/p' "$log")"
  out="$(queue_solo_outcome "$log")"
  git switch --quiet --detach origin/main 2>/dev/null
  case "$out" in
    green\ *)
      obj="${out#green }"
      if [ "$(printf '%s\n' "$BUILT_BASE" | wc -l | tr -d ' ')" != 1 ] || [ -z "$BUILT_BASE" ] ||
         ! git merge-base --is-ancestor "$BUILT_BASE" "$obj" || ! git merge-base --is-ancestor "${HEAD[$pr]}" "$obj"; then
        say "#$pr: the green object $obj does not contain the base and the reviewed head; this pass ends"; return 2
      fi
      queue_publish "$obj" "$BUILT_BASE" || return 2
      queue_accept "alone, through land.sh" "$obj" "$BUILT_BASE" "$log" "$pr" ;;
    red) queue_strike_clear "$QDIR" "$pr=${HEAD[$pr]}"; queue_fail "$pr" ;;
    refused)
      refused "$pr" solo "${HEAD[$pr]}" "$(grep -m1 -E 'REFUSE|^\*\*\* LAND REFUSED' "$log" | sed 's/^ *//')"
      comment "$pr" "**Merge queue: refused** on head \`${HEAD[$pr]}\` before any gate ran (\`land.sh $pr\`, solo). Its verdict lines:

\`\`\`
$(grep -E '^\*\*\* |REFUSE' "$log" | tail -n 15)
\`\`\`"
      relabel "$pr" queue-failed queue ;;
    moved)
      refused "$pr" solo "${HEAD[$pr]}" "dropped: the head moved past the reviewed one"
      comment "$pr" "**Merge queue: dropped.** The head moved past the reviewed \`${HEAD[$pr]}\` before its solo gate. Review the current head and re-enqueue."
      relabel "$pr" "" queue ;;
    *) if [ "$(queue_strike "$QDIR" "$pr=${HEAD[$pr]}")" -ge 2 ]; then
         queue_strike_clear "$QDIR" "$pr=${HEAD[$pr]}"
         refused "$pr" solo "${HEAD[$pr]}" "stopped twice without a verdict"
         comment "$pr" "**Merge queue: stopped twice** on head \`${HEAD[$pr]}\` without a verdict that blames this PR, so it leaves the queue rather than block it. Last verdict lines (\`$(basename "$log")\` under \`target/queue/\` on omen):

\`\`\`
$(grep -E '^\*\*\* ' "$log" | tail -n 10)
\`\`\`"
         relabel "$pr" queue-failed queue; return 0
       fi
       say "solo landing of #$pr stopped for a reason that is not the PR's; this pass ends, see $log"; return 2 ;;
  esac
  return 0
}

queue_once() {
  mkdir -p "$QDIR" || die "cannot create $QDIR"
  if [ "${QUEUE_LOCK_HELD:-0}" != 1 ]; then
    exec 9> "$QDIR/lock"
    flock -n 9 || { say "another pass holds the lock"; return 0; }
  fi
  [ -z "$(git status --porcelain --untracked-files=no)" ] || die "the queue checkout is dirty"
  local prs pr head marker out why solo batch=() shead rc base draft labels body
  prs="$(gh_cmd pr list -R "$REPO" --label queue --state open --json number --jq '.[].number' | sort -n | head -n "$QUEUE_MAX")"
  [ -n "$prs" ] || { say "queue empty"; return 0; }
  say "queued: $(echo $prs)"
  for pr in $prs; do
    head="$(pr_field "$pr" headRefOid .headRefOid)" && [ -n "$head" ] &&
      marker="$(pr_marker "$pr")" || { say "could not read #$pr from GitHub; this pass ends"; return 0; }
    if ! queue_head_ok "$marker" "$head"; then
      refused "$pr" marker "$head" "dropped: the reviewed head is ${marker:-none}"
      comment "$pr" "**Merge queue: dropped.** The reviewed head is \`${marker:-none}\`; the current head is \`$head\`. A verdict covers one object: review the current head and re-enqueue (\`scripts/queue.sh --enqueue $pr=<reviewed sha>\`)."
      relabel "$pr" "" queue; continue
    fi
    base="$(pr_field "$pr" baseRefName .baseRefName)" && [ -n "$base" ] &&
      draft="$(pr_field "$pr" isDraft .isDraft)" && [ -n "$draft" ] &&
      labels="$(pr_field "$pr" labels '[.labels[].name] | join(",")')" &&
      body="$(pr_field "$pr" body .body)" || { say "could not read #$pr from GitHub; this pass ends"; return 0; }
    why="$(queue_entry_refusal "$base" "$draft" "$labels" "$body")"
    if [ -n "$why" ]; then
      refused "$pr" entry "$head" "$why"
      comment "$pr" "**Merge queue: refused** on head \`$head\`: $why."
      relabel "$pr" queue-failed queue; continue
    fi
    out="$(ALATYR_LAND_EXPECT_HEAD="$head" bash scripts/land.sh "$pr" --screen 2>&1 9>&-)"; rc=$?
    shead="$(printf '%s\n' "$out" | sed -n 's/^land-screen: pr=[0-9]* head=\([0-9a-f]*\) .*$/\1/p')"
    if [ "$rc" != 0 ] || ! queue_head_ok "$head" "$shead"; then
      if printf '%s\n' "$out" | grep -q -e '^\*\*\* LAND REFUSED (PR shape)' -e '^\*\*\* LAND REFUSED (screen)'; then
        refused "$pr" screen "$head" "$(printf '%s\n' "$out" | grep -m1 -E 'REFUSE|^\*\*\* ' | sed 's/^ *//')"
        comment "$pr" "**Merge queue: refused at the screen** on head \`$head\` (\`land.sh $pr --screen\`):

\`\`\`
$(printf '%s\n' "$out" | tail -n 25)
\`\`\`"
        relabel "$pr" queue-failed queue; continue
      fi
      say "the screen of #$pr stopped for a reason that is not the PR's; this pass ends:"
      printf '%s\n' "$out" | tail -n 8
      return 0
    fi
    HEAD[$pr]="$head"
    LINK[$pr]="$(queue_relation_link "$body")"
    if [ "$(printf '%s\n' "$out" | sed -n 's/^land-screen: .* link=\(.*\)$/\1/p')" != "${LINK[$pr]}" ]; then
      refused "$pr" link "$head" "the line-initial marker ${LINK[$pr]} is not land.sh's link"
      comment "$pr" "**Merge queue: refused** on head \`$head\`: the body's line-initial marker is \`${LINK[$pr]}\`, but land.sh reads the first relation anywhere in the title and body as another issue. Remove the other mention, or reword it, and re-enqueue."
      relabel "$pr" queue-failed queue; continue
    fi
    BRANCH[$pr]="$(pr_field "$pr" headRefName .headRefName)" && [ -n "${BRANCH[$pr]}" ] ||
      { say "could not read #$pr's branch from GitHub; this pass ends"; return 0; }
    solo="$(printf '%s\n' "$out" | sed -n 's/^land-screen: .* solo=\([a-z]*\) .*$/\1/p')"
    if [ "$solo" = yes ]; then
      [ "${#batch[@]}" = 0 ] || continue   # a solo PR waits until it is first in line
      queue_solo "$pr"; git switch --quiet --detach origin/main 2>/dev/null; return 0
    fi
    batch+=("$pr")
  done
  if [ "${#batch[@]}" -gt 0 ]; then
    queue_compose_screen "${batch[@]}"
    # shellcheck disable=SC2086
    [ -z "$COMPOSED" ] || queue_drive $COMPOSED
  fi
  git switch --quiet --detach origin/main 2>/dev/null
  return 0
}

queue_enqueue() { # PR=SHA...  — the SHA is the head the review read; a later push is not reviewed
  local arg pr want head
  for arg in "$@"; do
    pr="${arg%%=*}"; want="${arg#*=}"
    case "$pr" in ''|0*|*[!0-9]*) die "use --enqueue N=<reviewed 40-hex sha>, got '$arg'" ;; esac
    case "$want" in ''|*[!0-9a-f]*) die "use --enqueue N=<reviewed 40-hex sha>, got '$arg'" ;; esac
    [ "${#want}" = 40 ] || die "use the full 40-hex sha of the reviewed head, got '$want'"
    head="$(pr_field "$pr" headRefOid .headRefOid)" || die "cannot read #$pr"
    [ "$head" = "$want" ] || die "#$pr's head is $head, not the reviewed $want: review the current head"
    gh_cmd pr comment "$pr" -R "$REPO" --body "Reviewed (alatyr-integrate §2); entering the merge queue (#1127).

queue-head: $head" >/dev/null || die "could not comment on #$pr"
    gh_cmd pr edit "$pr" -R "$REPO" --add-label queue >/dev/null || die "could not label #$pr"
    gh_cmd pr edit "$pr" -R "$REPO" --remove-label queue-failed >/dev/null 2>&1 || true
    echo "enqueued #$pr at $head"
  done
}

queue_status() {
  local pr head marker labels
  for pr in $(gh_cmd pr list -R "$REPO" --state open --search 'label:queue,queue-failed' --json number --jq '.[].number' | sort -n); do
    head="$(pr_field "$pr" headRefOid .headRefOid)"; marker="$(pr_marker "$pr")"
    labels="$(pr_field "$pr" labels '[.labels[].name | select(startswith("queue"))] | join(",")')"
    printf '#%s\t%s\thead %s\t%s\n' "$pr" "$labels" "${head:0:12}" \
      "$(queue_head_ok "$marker" "$head" && echo 'reviewed head is the current head' || echo "STALE (reviewed ${marker:0:12})")"
  done
}

## A user timer runs with no login session only under lingering: `loginctl enable-linger` (set on omen
## 2026-10-30; `loginctl show-user $USER -p Linger` says yes). The timer runs in a checkout of its own: a gate switches the tree, and two target-producing gates
## never share a checkout (AGENTS.md). The bootstrap takes the lock BEFORE it moves the tree.
queue_install() {
  local wt="$ROOT" unit="$HOME/.config/systemd/user"
  [ "$(basename "$wt")" = queue ] && [ "$(basename "$(dirname "$wt")")" = .worktrees ] ||
    die "run --install from the dedicated checkout .worktrees/queue, not $wt"
  mkdir -p "$unit" "$wt/target/queue" || die "cannot create $unit"
  cat > "$unit/alatyr-queue.service" <<EOF
[Unit]
Description=Alatyr compiler merge queue, one pass (scripts/queue.sh, #1127)

[Service]
Type=oneshot
WorkingDirectory=$wt
Environment=PATH=/run/current-system/sw/bin:/etc/profiles/per-user/%u/bin:%h/.nix-profile/bin
Environment=QUEUE_LOCK_HELD=1
ExecStart=/run/current-system/sw/bin/flock -n -o $wt/target/queue/lock /run/current-system/sw/bin/bash -c 'exec >> target/queue/queue.log 2>&1; git fetch -q origin main && git switch -q --detach origin/main && git show origin/main:scripts/queue.sh > target/queue/queue-run.sh && nix build --inputs-from . nixpkgs#gh -o target/queue/gh-tool && PATH="\$\$PWD/target/queue/gh-tool/bin:\$\$PATH" exec bash target/queue/queue-run.sh --once || { echo "queue: bootstrap failed (rc \$\$?)"; exit 1; }'
TimeoutStartSec=infinity
EOF
  cat > "$unit/alatyr-queue.timer" <<EOF
[Unit]
Description=Run the Alatyr merge queue 15 minutes after the previous pass ends

[Timer]
OnBootSec=5min
OnUnitInactiveSec=15min

[Install]
WantedBy=timers.target
EOF
  systemctl --user daemon-reload && systemctl --user enable --now alatyr-queue.timer &&
    systemctl --user list-timers alatyr-queue.timer --no-pager
}

case "${1:-}" in
  --self-test) queue_self_test ;;
  --enqueue)   shift; [ $# -gt 0 ] || die "--enqueue needs PR numbers"; queue_enqueue "$@" ;;
  --status)    queue_status ;;
  --once)
    ## Only in the dedicated checkout (a pass detaches and switches the tree), and only from a copy
    ## under target/queue/ (a switch rewrites scripts/queue.sh under the running bash, the #1093 hazard).
    [ "$(basename "$ROOT")" = queue ] && [ "$(basename "$(dirname "$ROOT")")" = .worktrees ] ||
      [ "${ALATYR_QUEUE_ANY_CHECKOUT:-0}" = 1 ] || die "--once runs in .worktrees/queue, not $ROOT"
    case "$(basename "$SELF")" in
      queue-run-once-*.sh) trap 'rm -f "$SELF"' EXIT ;;
      *) mkdir -p "$QDIR" && cp "$SELF" "$QDIR/queue-run-once-$$.sh" || die "cannot copy myself to $QDIR"
         exec bash "$QDIR/queue-run-once-$$.sh" --once ;;
    esac
    cd "$ROOT" && queue_once ;;
  --install)   queue_install ;;
  *) sed -n '/^# ## Usage/,/^set -u/p' "$SELF" | sed -e 's/^# \{0,1\}//' -e '$d'; exit 2 ;;
esac
