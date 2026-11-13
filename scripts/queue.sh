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
#   onto origin/main one merge at a time and never resolved by the queue itself: a PR that conflicts
#   with main is sent back; one that conflicts only with an earlier member waits for the next pass.
#   The one thing the composer does settle (#1390) is a conflict confined to files `land.sh
#   --settle-append-only` covers — scripts/e2e.sh, whose `run` rows every fixture PR appends at the
#   end of one list — where BOTH sides only ADDED lines at the same anchor: it keeps both runs, ours
#   first, and says so in the merge message. That is land.sh's resolver called, not a second one
#   written here. CHANGELOG.md is not on the list: a new entry is a changelog.d fragment (#1566),
#   which never conflicts, and the solo route above stays only for PRs opened before it. A counted
#   registry (scripts/known-deviations.tsv, scripts/seed_forms.tsv) is not on the list: keeping both
#   sides of one means re-sorting it and rewriting its `# live-rows:` count, which is a decision.
# - The composed object is gated once by `full.sh`. Green: it is pushed exactly, with
#   `--force-with-lease` on the base it was built on, and every member gets an acceptance comment.
#   When the gate's `xbackend diff:` line reports `new-paths=N new-rows=M` or `x86fix-paths=P
#   x86fix-rows=R` above zero (#1526: an x86_64 fix whose twins stay at a listed trap), the pushed object
#   is the gated one plus ONE commit moving scripts/xbackend_diff.baseline by exactly N+P and M+R, made
#   by the base's `land.sh --xbackend-follow` (its PHASE 6c, #1383), naming every member and each x86fix
#   row with its issue, and checked again here against the gate's own line;
#   without it every next gate on main would be red on the ratchet alone. Zero coverage, no commit.
#   A refused baseline commit pushes nothing and labels every member `queue-failed` (#1386).
#   Red: the set is bisected — its first half is gated alone, recursively — so a red PR is isolated
#   and marked `queue-failed` with its log tail, while the PRs that are green land. Every refusal and
#   `queue-failed` relabel also writes one `#N refused at <stage> on <sha8>: <reason>` line to queue.log
#   (#1368).
# - With ALATYR_QUEUE_RUNNER=github (#1571) the batch is gated as speculative stacks instead: S1 =
#   main+A, S2 = S1+B, … up to ALATYR_QUEUE_DEPTH (3), each pushed to its own gate/queue-<sha> run of
#   .github/workflows/gate.yml at once. A stack's verdict is its run's conclusion AND the one verdict
#   line of its `gate-<sha>` artifact, for exactly that object, and it counts only while main is still
#   the base the stacks were composed on (each Sk's parents are checked to chain back to it). The
#   deepest green prefix lands in ONE push of exactly that object, with its xbackend baseline commit
#   made from that stack's own gate.log. A red Sk over a green S(k-1) has isolated its member, which is
#   marked `queue-failed`; the members after it are recomposed on the new main. A cancelled, timed-out
#   or verdict-less run blames no one: the pass ends, and the second time for the same head is charged
#   to its member, as on omen. Solo PRs stay on omen, which the runner cannot replace for the native
#   seed; an object is never gated on both. The acceptance comment names the machine that gated it.
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
#                                         arguments, busy box, bisection plan, and the append-only batch
#                                         settle against a planted repository (#1390), and the
#                                         speculative stacks against a fake runner (#1571)
#
#   ALATYR_QUEUE_DRY=1       --once screens, composes and gates but neither pushes, labels nor comments
#   ALATYR_QUEUE_DRY=screen  as 1, and no gate runs (each counted green): a check of the plumbing
#   ALATYR_QUEUE_RUNNER=github  gate a batch as speculative stacks S1=main+A, S2=S1+B, … on parallel
#                            gate/** runs and land the deepest green prefix in one push (#1571); with
#                            DRY=1 it still pushes the gate/queue-<sha> branches, never main
#   ALATYR_QUEUE_DEPTH=3     the deepest stack one round gates (#1571)
set -u

SELF="$0"
## The timer runs a copy under target/queue/ (so a `git switch` cannot rewrite the running file, the
## #1093 hazard), so the root is the enclosing checkout, not the script's parent directory.
ROOT="$(git -C "$(dirname "$SELF")" rev-parse --show-toplevel 2>/dev/null || (cd "$(dirname "$SELF")/.." && pwd))"
REPO="${ALATYR_REPO:-alatyr-programming-language/compiler}"
QUEUE_MAX="${ALATYR_QUEUE_MAX:-4}"
DRY="${ALATYR_QUEUE_DRY:-0}"
RUNNER="${ALATYR_QUEUE_RUNNER:-omen}"   # omen, or github: speculative stacks on gate/** runs (#1571)
GATE_MACHINE=omen; GATE_RUN_URL=""; STACK_NOTE=""
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

## ---- speculative stacks on the GitHub runner (#1571) ----
## With ALATYR_QUEUE_RUNNER=github a batch is not gated as one object on omen. The queue composes
## S1 = base+A, S2 = S1+B, … up to ALATYR_QUEUE_DEPTH, gates every Sk at once as its own gate/** run,
## and lands the deepest green prefix in ONE push of exactly that gated object. Each stack adds one
## member, so a red Sk over a green S(k-1) has already isolated its member: that is the bisection's
## answer, reached in one round instead of log2(n) gates in a row. A batch that bisection would have
## split further is still split: the members after the red one are recomposed on the new main.

## What one round of stacks decided. Input: the base the stacks were composed on, what main is now,
## and one verdict per stack in order — g green, r red (the run's own FAILURES verdict), n anything
## else (cancelled, timed out, no verdict, a verdict for another object). Prints `land K`, then the
## reason the round went no deeper: `fail J` (stack J red over a green prefix: member J is red),
## `stop J` (stack J has no verdict that blames anyone) or `moved` (main is no longer the base: no
## verdict counts, nothing lands, everything is recomposed next pass).
queue_stack_plan() { # base main-now verdict...
  local base="$1" now="$2" k=0 v; shift 2
  [ -n "$base" ] && [ "$base" = "$now" ] || { echo "land 0 moved"; return; }
  for v in "$@"; do
    case "$v" in
      g) k=$((k + 1)) ;;
      r) echo "land $k fail $((k + 1))"; return ;;
      *) echo "land $k stop $((k + 1))"; return ;;
    esac
  done
  echo "land $k"
}

## The verdict of one stack's run. Input: the stack's object, the run as `headSha<TAB>status<TAB>
## conclusion` from `gh run list`, and the gate.log of its `gate-<sha>` artifact. 0 green: the run
## gated exactly this object, completed with success, and its log holds ONE verdict line and it is
## GREEN. 1 red: the same object, completed with failure, and the one verdict line is FAILURES.
## 2 otherwise — another object's run, still running, cancelled or timed out (an operator act or the
## runner's, not the member's), or a log without exactly one verdict line: never green, never blamed.
queue_runner_verdict() { # object run-line gate-log
  local sha st co n
  IFS=$'\t' read -r sha st co _ <<< "$2"
  [ -n "$1" ] && [ "$sha" = "$1" ] && [ "$st" = completed ] || return 2
  n="$(grep -c '^\*\*\* FULL GATE' "$3" 2>/dev/null)"
  [ "$n" = 1 ] || return 2
  [ "$co" = success ] && grep -q '^\*\*\* FULL GATE: GREEN (sweeps RAN) \*\*\*$' "$3" && return 0
  [ "$co" = failure ] && grep -q '^\*\*\* FULL GATE: FAILURES \*\*\*$' "$3" && return 1
  return 2
}

## Are these the stacks of these members on this base? S1's first parent is the base and its second
## the member's reviewed head, Sk's first parent is S(k-1): so a green verdict counts only for the base
## it was composed on — an object composed on an older main is a different object and fails here.
queue_stack_chain_ok() { # base object=head...
  local prev="$1" pair obj head; shift
  [ "$#" -gt 0 ] || return 1
  for pair in "$@"; do
    obj="${pair%%=*}"; head="${pair#*=}"
    [ "$(git rev-list --parents -n 1 "$obj" 2>/dev/null | wc -w | tr -d ' ')" = 3 ] &&
      [ "$(git rev-parse "$obj^1" 2>/dev/null)" = "$prev" ] &&
      [ "$(git rev-parse "$obj^2" 2>/dev/null)" = "$head" ] || return 1
    prev="$obj"
  done
}

## The stacks driver. It calls the functions the caller defines:
##   queue_stack_build PR...  compose STACK=(S1 … Sn) on origin/main, base STACK_BASE; non-zero ends the pass
##   queue_stack_gate         gate every stack at once; SV=(one g, r or n per stack, in order)
##   queue_main_now           print what main is now
##   queue_stack_land K PR... publish stack K, which holds exactly these PRs
##   queue_stack_fail J PR    stack J is red over a green prefix: mark its member PR red
##   queue_stack_stop J PR    stack J, which PR completes, has no verdict: a strike, the pass ends
QUEUE_DEPTH="${ALATYR_QUEUE_DEPTH:-3}"
queue_stack_drive() { # PR...
  local rest=("$@") n plan k what j now vs i
  case "$QUEUE_DEPTH" in ''|0*|*[!0-9]*) say "ALATYR_QUEUE_DEPTH must be a positive number, not '$QUEUE_DEPTH'"; return 0 ;; esac
  while [ "${#rest[@]}" -gt 0 ]; do
    n="${#rest[@]}"; [ "$n" -gt "$QUEUE_DEPTH" ] && n="$QUEUE_DEPTH"
    queue_stack_build "${rest[@]:0:n}" || return 0
    queue_stack_gate || return 0
    now="$(queue_main_now)" || return 0
    vs=(); for ((i = 0; i < n; i++)); do vs+=("${SV[i]:-n}"); done   # a stack with no verdict is n
    plan="$(queue_stack_plan "$STACK_BASE" "$now" "${vs[@]}")"
    read -r _ k what j <<< "$plan"
    if [ "$k" -gt 0 ]; then queue_stack_land "$k" "${rest[@]:0:k}" || return 0; fi
    case "$what" in
      fail) queue_stack_fail "$j" "${rest[$((j - 1))]}"; rest=("${rest[@]:j}") ;;
      stop) queue_stack_stop "$j" "${rest[$((j - 1))]}"; return 0 ;;
      moved) return 0 ;;
      '') rest=("${rest[@]:k}") ;;
      *) say "internal: the stack plan '$plan' is not one the driver knows; this pass ends"; return 0 ;;
    esac
    [ "$k" -gt 0 ] || [ "$what" = fail ] || return 0   # a round that settled nothing ends the pass
  done
}

## The exact number of checks queue_self_test runs, compared with -ne like land.sh's.
QUEUE_SELFTEST_EXPECTED=109  # 49, +6 #1383, +7 #1386, +9 #1423, +2 #1526, +9 #1390, +27 #1571
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
  xgl() { printf 'xbackend diff: paths=1 rows=1 sources=9 hw-defined=0 raw-escape=0 target-na=0 quiet=0 attributed=0 unexplained=0 %s\n' "$1" > "$t/gate.log"; }
  xgl 'new-paths=2 new-rows=6'
  queue_follow_run() { echo run >> "$t/ran"; printf 'xbackend-follow: commit %s paths+2 rows+6\n' "${QF_C:-}"; }
  qf() { QF_C="$1" DRY=0 BUILT="$xg" GATE_LOG="$t/gate.log"; queue_follow 1309 2>/dev/null; } # commit -> what the queue would publish
  [ "$(qf "$xok")" = "$xok" ]; _ck $? follow-refused-the-one-child-moving-the-baseline-alone
  [ "$(qf "$xpar")" = "" ] && [ "$(qf "$xpar" >/dev/null; echo $?)" = 1 ]; _ck $? follow-took-a-commit-on-another-parent
  [ "$(qf "$xtwo")" = "" ] && [ "$(qf "$xtwo" >/dev/null; echo $?)" = 1 ]; _ck $? follow-took-a-two-parent-commit
  [ "$(qf "$xfile")" = "" ] && [ "$(qf "$xfile" >/dev/null; echo $?)" = 1 ]; _ck $? follow-took-a-commit-changing-a-second-file
  # #1526: the move is the gate's new + x86fix figures, read from the gate's own line, never land.sh's word.
  xgl 'new-paths=1 new-rows=2 x86fix-paths=1 x86fix-rows=4'
  [ "$(qf "$xok")" = "$xok" ]; _ck $? follow-refused-a-move-by-new-plus-x86fix
  xgl 'new-paths=2 new-rows=5 x86fix-paths=0 x86fix-rows=0'
  [ "$(qf "$xok")" = "" ] && [ "$(qf "$xok" >/dev/null; echo $?)" = 1 ]; _ck $? follow-took-a-move-the-gate-line-does-not-hold
  xgl 'new-paths=2 new-rows=6'
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
  unset -f qf xgl comment relabel queue_publish queue_accept queue_follow_run; unset 'HEAD[1]' 'HEAD[3]' QF_C
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
  # ---- speculative stacks (#1571): the round's plan, the runner's verdict, the chain, the driver ----
  [ "$(queue_stack_plan B B g g g)" = "land 3" ]; _ck $? stack-plan-did-not-land-three-greens-at-once
  [ "$(queue_stack_plan B B g r g)" = "land 1 fail 2" ]; _ck $? stack-plan-did-not-strike-the-member-of-a-red-S2
  [ "$(queue_stack_plan B B r g g)" = "land 0 fail 1" ]; _ck $? stack-plan-landed-over-a-red-S1
  [ "$(queue_stack_plan B M g g g)" = "land 0 moved" ]; _ck $? stack-plan-landed-on-a-main-that-moved
  [ "$(queue_stack_plan "" "" g)" = "land 0 moved" ]; _ck $? stack-plan-landed-with-no-base
  [ "$(queue_stack_plan B B g n r)" = "land 1 stop 2" ]; _ck $? stack-plan-blamed-a-stack-with-no-verdict
  mkdir -p "$ROOT/target" && t="$(mktemp -d "$ROOT/target/queue-selftest.XXXXXX")" || return 1
  printf 'x\n*** FULL GATE: GREEN (sweeps RAN) ***\n' > "$t/green"
  printf 'x\n*** FULL GATE: FAILURES ***\n' > "$t/red"
  printf '*** FULL GATE: GREEN (sweeps RAN) ***\n*** FULL GATE: GREEN (sweeps RAN) ***\n' > "$t/two"
  printf '*** FULL GATE: GREEN — but the SWEEPS DID NOT RUN (sweeps STATUS=SKIP): x\n' > "$t/nosweeps"
  rl() { printf '%s\t%s\t%s\t%s\t%s' "$1" "$2" "$3" 42 https://example/run/42; } # sha status conclusion
  queue_runner_verdict "$a" "$(rl "$a" completed success)" "$t/green"; _ck $? runner-refused-its-green
  queue_runner_verdict "$a" "$(rl "$b" completed success)" "$t/green"; [ $? = 2 ]; _ck $? runner-took-a-verdict-on-another-object
  queue_runner_verdict "$a" "$(rl "$a" completed cancelled)" "$t/red"; [ $? = 2 ]; _ck $? runner-took-a-cancelled-run-as-a-verdict
  queue_runner_verdict "$a" "$(rl "$a" in_progress "")" "$t/green"; [ $? = 2 ]; _ck $? runner-took-an-unfinished-run
  queue_runner_verdict "$a" "$(rl "$a" completed failure)" "$t/red"; [ $? = 1 ]; _ck $? runner-did-not-blame-its-red
  queue_runner_verdict "$a" "$(rl "$a" completed success)" "$t/red"; [ $? = 2 ]; _ck $? runner-took-success-over-a-FAILURES-line
  queue_runner_verdict "$a" "$(rl "$a" completed success)" "$t/two"; [ $? = 2 ]; _ck $? runner-took-a-log-with-two-verdicts
  queue_runner_verdict "$a" "$(rl "$a" completed success)" "$t/none"; [ $? = 2 ]; _ck $? runner-took-a-run-with-no-log
  queue_runner_verdict "$a" "$(rl "$a" completed success)" "$t/nosweeps"; [ $? = 2 ]; _ck $? runner-took-a-green-whose-sweeps-did-not-run
  # The chain, in a planted repository: a stale green from an older base is another object.
  ( cd "$t" && git init -q -b main c && cd c && git config user.email q@x && git config user.name q &&
    git commit -q --allow-empty -m old && git tag old && git commit -q --allow-empty -m base && git tag base &&
    for m in A B; do git switch -q -c "m$m" old && git commit -q --allow-empty -m "$m" && git tag "$m"; done &&
    git switch -q --detach base && git merge -q --no-ff -m s1 A && git tag s1 && git merge -q --no-ff -m s2 B && git tag s2 &&
    git switch -q --detach old && git merge -q --no-ff -m o1 A && git tag o1 ) >/dev/null 2>&1
  cs() { git -C "$t/c" rev-parse "$1"; }
  ( cd "$t/c" && queue_stack_chain_ok "$(cs base)" "$(cs s1)=$(cs A)" "$(cs s2)=$(cs B)" ); _ck $? chain-refused-its-stacks
  ( cd "$t/c" && queue_stack_chain_ok "$(cs base)" "$(cs o1)=$(cs A)" ); [ $? = 1 ]; _ck $? chain-took-a-stack-composed-on-an-older-base
  ( cd "$t/c" && queue_stack_chain_ok "$(cs base)" "$(cs s1)=$(cs B)" "$(cs s2)=$(cs A)" ); [ $? = 1 ]; _ck $? chain-took-swapped-members
  ( cd "$t/c" && queue_stack_chain_ok "$(cs base)" "$(cs s2)=$(cs B)" ); [ $? = 1 ]; _ck $? chain-took-a-stack-that-skips-one
  rm -rf "$t"; unset -f rl cs
  # The driver against a fake runner: a stack is red when it holds a PR in FR, has no verdict when it
  # holds one in FN, and is green otherwise; FM is what main is when the round ends.
  local FR FN FM qdp="$QUEUE_DEPTH"
  queue_stack_build() { log="$log build:$*;"; STACK_BASE=B; STACK=(); local p s=""; for p in "$@"; do s="$s$p"; STACK+=("$s"); done; }
  queue_stack_gate() { local i x; SV=(); for i in "${!STACK[@]}"; do x=g
      case "${STACK[i]}" in *[$FN]*) x=n ;; esac; case "${STACK[i]}" in *[$FR]*) x=r ;; esac; SV+=("$x"); done; }
  queue_main_now() { echo "$FM"; }
  queue_stack_land() { log="$log land:$*;"; }
  queue_stack_fail() { log="$log fail:$*;"; }
  queue_stack_stop() { log="$log stop:$*;"; }
  QUEUE_DEPTH=3 FR=_ FN=_ FM=B
  log=""; queue_stack_drive 1 2 3; [ "$log" = " build:1 2 3; land:3 1 2 3;" ]; _ck $? "stacks-three-greens-not-one-push($log)"
  FR=2; log=""; queue_stack_drive 1 2 3; [ "$log" = " build:1 2 3; land:1 1; fail:2 2; build:3; land:1 3;" ]; _ck $? "stacks-red-S2($log)"
  FR=1; log=""; queue_stack_drive 1 2 3; [ "$log" = " build:1 2 3; fail:1 1; build:2 3; land:2 2 3;" ]; _ck $? "stacks-red-S1($log)"
  FR=_ FM=M; log=""; queue_stack_drive 1 2 3; [ "$log" = " build:1 2 3;" ]; _ck $? "stacks-landed-on-a-main-that-moved($log)"
  FM=B FN=2; log=""; queue_stack_drive 1 2 3; [ "$log" = " build:1 2 3; land:1 1; stop:2 2;" ]; _ck $? "stacks-cancelled-S2($log)"
  FN=_; log=""; queue_stack_drive 1 2 3 4; [ "$log" = " build:1 2 3; land:3 1 2 3; build:4; land:1 4;" ]; _ck $? "stacks-deeper-than-the-depth($log)"
  queue_stack_gate() { SV=(g); }
  log=""; queue_stack_drive 1 2; [ "$log" = " build:1 2; land:1 1; stop:2 2;" ]; _ck $? "stacks-a-missing-verdict-was-not-n($log)"
  QUEUE_DEPTH=0; log=""; queue_stack_drive 1 2 >/dev/null; [ "$log" = "" ]; _ck $? "stacks-built-at-depth-0($log)"
  QUEUE_DEPTH="$qdp"
  unset -f queue_stack_build queue_stack_gate queue_main_now queue_stack_land queue_stack_fail queue_stack_stop
  # The bootstrap recovers the queue checkout from a merge left in flight (#1423), and still cleans dirt.
  ## The scratch clone names its branch `main` EXPLICITLY, three times over: `git init -b`, the bare
  ## repo's HEAD, and every clone's `-b`. A row that inherits the machine's `init.defaultBranch` passes
  ## on a laptop set to `main` and dies on a runner whose default is `master` — which is exactly what
  ## happened to the first version of these rows (run 41602783694: three rows red on the runner, green
  ## here). A check whose verdict depends on a git config the test never sets is not a check.
  local s; s="$(mktemp -d "$ROOT/target/queue-bootstrap.XXXXXX")" || return 1
  git init -q --bare "$s/up" && git -C "$s/up" symbolic-ref HEAD refs/heads/main &&
    git clone -q -b main "$s/up" "$s/wt" 2>/dev/null || git clone -q "$s/up" "$s/wt"
  git -C "$s/wt" symbolic-ref HEAD refs/heads/main
  git -C "$s/wt" config user.email q@q && git -C "$s/wt" config user.name q &&
    printf 'base\n' > "$s/wt/f.txt" && git -C "$s/wt" add f.txt && git -C "$s/wt" commit -q -m base &&
    git -C "$s/wt" push -q origin HEAD:refs/heads/main && git -C "$s/wt" fetch -q origin
  [ "$(git -C "$s/wt" rev-parse --abbrev-ref HEAD)" = main ] &&
    [ "$(git -C "$s/wt" rev-parse --verify origin/main)" = "$(git -C "$s/wt" rev-parse HEAD)" ]
  _ck $? bootstrap-case-had-no-main-to-recover-to
  queue_bootstrap_recover "$s/wt" >/dev/null 2>&1; _ck $? bootstrap-refused-a-clean-checkout
  # A compose that conflicts mid-merge: MERGE_HEAD stays, and `git switch` refuses to move.
  git -C "$s/wt" checkout -q -b side && printf 'side\n' > "$s/wt/f.txt" && git -C "$s/wt" commit -q -am side
  git -C "$s/up" symbolic-ref HEAD refs/heads/main
  git clone -q "$s/up" "$s/other" && git -C "$s/other" symbolic-ref HEAD refs/heads/main &&
    git -C "$s/other" config user.email o@o && git -C "$s/other" config user.name o &&
    printf 'main moved\n' > "$s/other/f.txt" && git -C "$s/other" commit -q -am moved &&
    git -C "$s/other" push -q origin HEAD:refs/heads/main
  git -C "$s/wt" checkout -q -B main "$(git -C "$s/other" rev-parse HEAD~1)" 2>/dev/null ||
    git -C "$s/wt" checkout -q main
  git -C "$s/wt" fetch -q origin
  git -C "$s/wt" merge --no-ff --no-commit origin/main >/dev/null 2>&1
  [ -e "$(git -C "$s/wt" rev-parse --absolute-git-dir)/MERGE_HEAD" ]; _ck $? bootstrap-case-left-no-merge-state-to-recover
  ! git -C "$s/wt" switch -q --detach origin/main 2>/dev/null; _ck $? bootstrap-case-switched-while-a-merge-was-in-flight
  queue_bootstrap_recover "$s/wt" >/dev/null 2>&1; _ck $? bootstrap-did-not-recover-a-conflicted-merge
  [ "$(git -C "$s/wt" rev-parse HEAD)" = "$(git -C "$s/wt" rev-parse origin/main)" ]
  _ck $? bootstrap-recovered-to-the-wrong-object
  [ ! -e "$(git -C "$s/wt" rev-parse --absolute-git-dir)/MERGE_HEAD" ]; _ck $? bootstrap-left-MERGE_HEAD-behind
  # Tracked dirt is reset, and said out loud while it goes.
  printf 'dirt\n' > "$s/wt/f.txt"
  queue_bootstrap_recover "$s/wt" >/dev/null 2>&1; _ck $? bootstrap-refused-dirt-it-can-clean
  [ "$(cat "$s/wt/f.txt")" = "main moved" ]; _ck $? bootstrap-kept-dirty-tracked-content
  rm -rf "$s"
  # ---- the batch composer's append-only settle (#1390) ------------------------------------------
  # Two members that both append at one anchor of scripts/e2e.sh settle through land.sh's
  # pure-addition resolver, reached by `--settle-append-only`, which accepts a hunk only when its diff3
  # base section is empty. A rewritten line, a deleted line, a file off the list (CHANGELOG.md among
  # them: an entry is a changelog.d fragment since #1566) and a counted registry stay refusals,
  # with the merge aborted, HEAD where it was and the tree clean. The settled tree must still hold
  # both counted registries whole: rows in LC_ALL=C order, and a `# live-rows:` that equals what
  # parses. The fixture's land.sh is this tree's, the one the composer will call in production.
  local here="$PWD" qa qhead qrc qb pb qh qn
  qa="$(mktemp -d "$ROOT/target/queue-selftest.XXXXXX")" || return 1
  qhead="$(git -C "$ROOT" rev-parse HEAD)" || { cd "$here"; rm -rf "$qa"; return 1; }
  ( set -e; cd "$qa"; git init -q -b main qa; cd qa
    git config user.name t; git config user.email t@t; git config commit.gpgsign false
    git config core.hooksPath /dev/null
    mkdir -p scripts src
    printf '# C\n\n## Unreleased\n\n## 0.1.0 — d\n\n- old\n' > CHANGELOG.md
    printf 'run base\nrun old\n' > scripts/e2e.sh
    printf '# live-rows: 1\nform_a\ttree\t42\t#1\ts.al:k\n' > scripts/seed_forms.tsv
    printf '# rows\nbase\tf.al\tsema/1\t#1\n' > scripts/known-deviations.tsv
    printf '# union\nscripts/known-deviations.tsv merge=union\n' > .gitattributes
    printf 'x\n' > src/x.al
    git add -A; git commit -q -m base
    git switch -q -c ours                                     # the batch so far, on main
    printf '# C\n\n## Unreleased\n\n- main bullet\n\n## 0.1.0 — d\n\n- old\n' > CHANGELOG.md
    printf 'run base\nrun old\nrun main\n' > scripts/e2e.sh
    printf '# live-rows: 2\nform_a\ttree\t42\t#1\ts.al:k\nform_b\ttree\t7\t#2\ts.al:m\n' > scripts/seed_forms.tsv
    printf 'ours-x\n' > src/x.al
    git add -A; git commit -q -m ours
    git switch -q -c p1 main                                # e2e.sh: additions at the same anchor
    printf 'run base\nrun old\nrun pr\n  cont\n' > scripts/e2e.sh
    git add -A; git commit -q -m p1
    git switch -q -c p2 main                              # rewrites an existing e2e row
    printf 'run base\nrun old REWRITTEN\n' > scripts/e2e.sh
    git add -A; git commit -q -m p2
    git switch -q -c p3 main                              # deletes an existing e2e row
    printf 'run base\n' > scripts/e2e.sh
    git add -A; git commit -q -m p3
    git switch -q -c p4 main                              # a settleable e2e row beside a source conflict
    printf 'run base\nrun old\nrun pr\n' > scripts/e2e.sh
    printf 'pr-x\n' > src/x.al
    git add -A; git commit -q -m p4
    git switch -q -c p5 main                              # a counted registry alone
    printf '# live-rows: 2\nform_a\ttree\t42\t#1\ts.al:k\nform_c\ttree\t9\t#4\ts.al:n\n' > scripts/seed_forms.tsv
    git add -A; git commit -q -m p5
    git switch -q -c p6 main                              # an Unreleased bullet: off the list since #1566
    printf '# C\n\n## Unreleased\n\n- pr bullet\n\n## 0.1.0 — d\n\n- old\n' > CHANGELOG.md
    git add -A; git commit -q -m p6 ) >/dev/null 2>&1
  _ck $? selftest-could-not-build-the-append-only-fixture
  QUEUE_LAND_REF="$qhead"
  cd "$qa/qa" || return 1
  git switch -q --detach ours
  queue_merge_member p1 'merge #21: p1'; qrc=$?
  [ "$qrc" = 0 ] &&
    [ "$(git show HEAD:scripts/e2e.sh | tr '\n' '|')" = 'run base|run old|run main|run pr|  cont|' ]
  _ck $? "composer-refused-a-pure-addition-conflict-in-e2e.sh(rc $qrc)"
  git merge --abort 2>/dev/null
  git log -1 --format=%B | grep -q 'scripts/e2e.sh: 1 conflict hunk(s) settled by scripts/land.sh (#1390)'
  _ck $? settled-merge-message-did-not-name-the-settle
  grep -v '^#' scripts/known-deviations.tsv | LC_ALL=C sort -c &&
    [ "$(grep -cv -e '^#' -e '^[[:space:]]*$' scripts/seed_forms.tsv)" = "$(sed -n 's/^# live-rows: *\([0-9][0-9]*\) *$/\1/p' scripts/seed_forms.tsv | head -n 1)" ]
  _ck $? settled-tree-broke-a-counted-registry
  for pb in 'p2 rewrote an existing line' 'p3 deleted an existing line' \
            'p4 a settleable e2e row beside a source conflict' \
            'p5 a counted registry alone' 'p6 an Unreleased bullet in CHANGELOG.md'; do
    read -r qh qn <<< "$pb"; pb="${qn// /-}"
    git switch -q --detach ours; qb="$(git rev-parse HEAD)"
    queue_merge_member "$qh" "merge: $qh"; qrc=$?
    git merge --abort 2>/dev/null      # a refusal leaves the merge in progress; the composer aborts it
    [ "$qrc" = 1 ] && [ "$(git rev-parse HEAD)" = "$qb" ] && ! git rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1 &&
      [ -z "$(git status --porcelain --untracked-files=no)" ]
    _ck $? "composer-settled-a-conflict-that-$pb"
  done
  QUEUE_LAND_REF="${ALATYR_QUEUE_LAND_REF:-origin/main}"
  cd "$here" || return 1
  rm -rf "$qa"
  if [ -n "$bad" ]; then echo "*** queue self-test: FAILED —$bad ***"; return 1; fi
  if [ "$k" -ne "$QUEUE_SELFTEST_EXPECTED" ]; then
    echo "*** queue self-test: ran $k checks, expected exactly $QUEUE_SELFTEST_EXPECTED: a check was lost or added uncounted ***"
    return 1
  fi
  echo "ok   queue self-test: $k checks — reviewed-head marker, entry rules, head check, gate verdict,"
  echo "     push arguments, the xbackend baseline commit and its refusal, busy box, the bisection plan,"
  echo "     the bootstrap recovery (#1423), the append-only batch settle (#1390) and the speculative"
  echo "     stacks on the runner: plan, verdict, chain and driver (#1571)"
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

## The BASE's copy of land.sh, run for one thing only: `--settle-append-only <path>...` (#1390).
## The tree is mid-merge and therefore holds the batch's scripts, so the queue takes this script's
## own base revision out of git rather than running what is checked out (`never a batch's`, the Trust
## section above). It lands directly under target/ because land.sh resolves its ROOT to the copy's
## parent's parent, and it is named `land-run-*` so land.sh takes its private-copy path and does not
## re-exec. It removes the copy itself on exit; the rm here covers a run that never got that far.
## Prints land.sh's sentences for the merge message. 0 settled, 1 refused (the merge is untouched),
## 2 could not run.
QUEUE_LAND_REF="${ALATYR_QUEUE_LAND_REF:-origin/main}"
queue_land_sh() { # path...
  local top copy rc
  top="$(git rev-parse --show-toplevel 2>/dev/null)" || return 2
  mkdir -p "$top/target" || return 2
  copy="$top/target/land-run-queue-$$.sh"
  git -C "$ROOT" show "$QUEUE_LAND_REF:scripts/land.sh" > "$copy" 2>/dev/null ||
    { rm -f "$copy"; return 2; }
  bash "$copy" --settle-append-only "$@"; rc=$?
  rm -f "$copy"
  case "$rc" in 0|1) return "$rc" ;; *) return 2 ;; esac
}

## Merge one member into the tree the batch is being composed in (#1390). A clean merge commits as it
## always did. A conflict goes to land.sh's append-only settle, and ONLY there: it accepts a path
## whose every hunk has an empty diff3 base section — both sides inserted at one anchor, neither
## deleted nor rewrote a line — and refuses everything else. The queue decides nothing of its own here;
## it asks, and a refusal aborts the merge exactly as before.
##   0 merged (QUEUE_MERGE_NOTE carries land.sh's sentences when it settled anything)
##   1 a conflict the settle does not cover — back to the author, or wait for the next pass
##   2 git could not merge, or land.sh could not run — this pass ends
QUEUE_MERGE_NOTE=""
queue_merge_member() { # ref msg
  local ref="$1" msg="$2" un=() p note rc
  QUEUE_MERGE_NOTE=""
  git merge --quiet --no-ff --no-verify -m "$msg" "$ref" >/dev/null 2>&1 && return 0
  while IFS= read -r p; do [ -n "$p" ] && un+=("$p"); done < <(git diff --name-only --diff-filter=U)
  { [ "${#un[@]}" -gt 0 ] && git rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; } || return 2
  note="$(queue_land_sh "${un[@]}" 2>&1)"; rc=$?   # land.sh names the hunk it refused on stderr
  QUEUE_MERGE_NOTE="$note"          # on a refusal, the hunk land.sh refused, for the caller to print
  [ "$rc" = 0 ] || return "$rc"     # 1 refused, 2 could not run: both leave the merge untouched
  git commit --quiet --no-verify -m "$msg

$note" >/dev/null 2>&1 || return 2
  QUEUE_MERGE_NOTE="$note"
  return 0
}

## Compose the members onto origin/main one merge at a time, each its reviewed head. Leaves the tree at
## the last merge; COMPOSE_BASE is the base, COMPOSE_OBJS the object after each member, in order.
## 0 composed, 2 not (a fetch, a moved head, a conflict: this pass ends, nothing is labelled).
COMPOSE_BASE=""; COMPOSE_OBJS=()
queue_compose_onto_main() { # PR...
  local base pr msg rc
  COMPOSE_OBJS=()
  git fetch --quiet origin main || return 2
  base="$(git rev-parse origin/main)"; COMPOSE_BASE="$base"
  git switch --quiet --detach "$base" || return 2
  QUEUE_LAND_REF="$base"     # the base's copy of land.sh settles, never a batch's (#1390)
  for pr in "$@"; do
    git fetch --quiet origin "+refs/pull/$pr/head:refs/remotes/pr/$pr" || return 2
    queue_head_ok "${HEAD[$pr]}" "$(git rev-parse "refs/remotes/pr/$pr")" ||
      { say "#$pr moved after its screen; this pass ends"; return 2; }
    msg="merge #$pr: ${BRANCH[$pr]}"
    [ -n "${LINK[$pr]}" ] && msg="$msg

${LINK[$pr]}"
    queue_merge_member "refs/remotes/pr/$pr" "$msg"; rc=$?
    if [ "$rc" != 0 ]; then
      git merge --abort 2>/dev/null
      say "#$pr no longer composes onto $base (rc $rc); this pass ends"
      [ "$rc" = 1 ] && printf '%s\n' "$QUEUE_MERGE_NOTE" | sed 's/^/  /'
      return 2
    fi
    [ -z "$QUEUE_MERGE_NOTE" ] || say "#$pr composed with an append-only conflict settled (#1390)"
    COMPOSE_OBJS+=("$(git rev-parse HEAD)")
  done
}

queue_try() { # PR... — compose onto origin/main and gate
  [ "$DRY" = screen ] || wait_for_box || return 2   # before the base is read: a long wait would void the lease
  queue_compose_onto_main "$@" || return 2
  local base="$COMPOSE_BASE" pr
  GATE_MACHINE=omen; GATE_RUN_URL=""; STACK_NOTE=""
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
## Where a reader finds a gate's log: under target/queue/ on omen, or the runner's run and artifact.
queue_log_where() { # log
  if [ "${GATE_MACHINE:-omen}" = omen ]; then echo "log \`$(basename "$1")\` under \`target/queue/\` on omen"
  else echo "run ${GATE_RUN_URL:-(unknown)}, artifact \`gate-$BUILT\`"; fi
}

## After a push: one acceptance per PR, labels off, the PR's snapshot ref and branch removed.
queue_accept() { # how object base log PR...
  local how="$1" obj="$2" base="$3" log="$4" pr branch; shift 4
  git fetch --quiet origin main || say "fetch after the push failed; acceptance continues on the pushed object"
  for pr in "$@"; do
    comment "$pr" "**Landed by the merge queue** (\`scripts/queue.sh\`, #1127, $how), no agent session attached.

- reviewed head: \`${HEAD[$pr]}\` (the \`queue-head\` marker; the object gated)
- members: $(prs_h "$@"), composed onto \`$base\`; \`main\` is now \`$obj\`
- gate on ${GATE_MACHINE:-omen}, on that exact object: \`$(gate_line "$log")\` ($(queue_log_where "$log"))
$(git diff --quiet "$obj^" "$obj" -- scripts/xbackend_diff.baseline 2>/dev/null || echo "- xbackend baseline: \`$obj\` moves it by the gate's newly covered and x86_64-fixed paths and rows (#1526), alone, on the gated object (#1383)")
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
## gated object, the baseline is the only file it changes, and its paths=/rows= move by exactly what the
## gate's own `xbackend diff:` line holds outside the ratchet: new-paths+x86fix-paths and
## new-rows+x86fix-rows (#1526; a line from before #1526 has no x86fix pair and reads it as 0). Same
## refusals as land.sh's xb_follow_commit_check, so a base whose land.sh lost one still cannot publish
## a wrong object.
queue_follow_gate_move() { # gate-log -> "paths rows" the baseline must move by; 1 unreadable
  local line
  [ "$(grep -c '^xbackend diff: paths=' "$1" 2>/dev/null)" = 1 ] || return 1
  line="$(grep '^xbackend diff: paths=' "$1")"
  printf '%s\n' "$line" | sed -n \
    -e 's/^xbackend diff: paths=[0-9][0-9]* .* new-paths=\([0-9][0-9]*\) new-rows=\([0-9][0-9]*\) x86fix-paths=\([0-9][0-9]*\) x86fix-rows=\([0-9][0-9]*\)$/\1 \2 \3 \4/p' \
    -e 's/^xbackend diff: paths=[0-9][0-9]* .* new-paths=\([0-9][0-9]*\) new-rows=\([0-9][0-9]*\)$/\1 \2 0 0/p' |
    awk 'NR == 1 { print $1 + $3, $2 + $4; f = 1 } END { exit !f }'
}
queue_follow_commit_ok() { # gated commit gate-log -> 0 ok, 1 not
  local want got o
  [ "$(git rev-list --parents -n 1 "$2" 2>/dev/null | wc -w | tr -d ' ')" = 2 ] &&
    [ "$(git rev-parse "$2^" 2>/dev/null)" = "$1" ] &&
    [ "$(git diff --name-only "$1" "$2" 2>/dev/null)" = scripts/xbackend_diff.baseline ] || return 1
  want="$(queue_follow_gate_move "$3")" || return 1
  got="$(for o in "$1" "$2"; do git show "$o:scripts/xbackend_diff.baseline" 2>/dev/null |
           awk -F= '$1 == "paths" { p = $2 } $1 == "rows" { r = $2 } END { print p + 0, r + 0 }'; done |
         awk 'NR == 1 { p = $1; r = $2 } NR == 2 { print $1 - p, $2 - r }')"
  [ -n "$got" ] && [ "$got" = "$want" ]
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
    queue_follow_commit_ok "$BUILT" "$obj" "$GATE_LOG" ||
      { echo "queue: $obj is not one commit on $BUILT changing scripts/xbackend_diff.baseline alone, by the gate's new + x86fix figures" >> "$GATE_LOG.follow"; return 1; }
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

Gated ${STACK_NOTE:-alone} on \`$BUILT_BASE\` as \`$BUILT\`: \`$(gate_line "$GATE_LOG")\`. $(queue_log_where "$GATE_LOG"); its failing lines:

\`\`\`
$(grep -E 'FAIL|MISMATCH|REFUSED|NOT LANDABLE|error' "$GATE_LOG" 2>/dev/null | tail -n 30)
\`\`\`

The label moved to \`queue-failed\`. Fix, push, and re-enqueue after review."
  relabel "$pr" queue-failed queue
}

## ---- the runner's side of the stacks (#1571) ----
## Every stack is pushed to gate/queue-<sha>, which runs .github/workflows/gate.yml on exactly that
## object; its verdict is the run's conclusion AND the one `*** FULL GATE` line of its `gate-<sha>`
## artifact (queue_runner_verdict). An omen gate and a runner gate never both claim an object: in this
## mode a batch is gated on the runner only, and a solo PR (oracle, predicted delta) on omen only,
## through land.sh as before — the runner cannot run what needs the native seed. Trust is the omen
## gate's: the composed tree's own full.sh judges it there, and the composed tree's own gate.yml here,
## both bounded by the §2 review that precedes --enqueue.
QUEUE_RUNNER_WAIT="${ALATYR_QUEUE_RUNNER_WAIT:-240}"   # minutes; the slowest of 30 runs took 146
STACK_BASE=""; STACK=(); STACK_FOR=(); SV=(); STACK_LOGS=(); STACK_RUNS=(); STACK_IDS=()
queue_stack_build() { # PR...
  local i pairs=()
  STACK=(); STACK_FOR=("$@"); SV=(); STACK_LOGS=(); STACK_RUNS=(); STACK_IDS=()
  queue_compose_onto_main "$@" || return 2
  STACK_BASE="$COMPOSE_BASE"; STACK=("${COMPOSE_OBJS[@]}")
  for i in "${!STACK[@]}"; do pairs+=("${STACK[i]}=${HEAD[${STACK_FOR[i]}]}"); done
  queue_stack_chain_ok "$STACK_BASE" "${pairs[@]}" ||
    { say "the stacks of $(prs_h "$@") are not one chain on $STACK_BASE; this pass ends"; return 2; }
  say "stacks on $STACK_BASE:$(for i in "${!STACK[@]}"; do printf ' S%d=%s(+#%s)' $((i + 1)) "${STACK[i]:0:12}" "${STACK_FOR[i]}"; done)"
}
## Is the round decided? Every stack up to and including the first one that is not green has a verdict.
queue_stack_decided() {
  local v
  for v in ${SV[@]+"${SV[@]}"}; do
    case "$v" in g) ;; '') return 1 ;; *) return 0 ;; esac
  done
  [ "${#SV[@]}" = "${#STACK[@]}" ]
}
queue_stack_gate() {
  local i obj line st id url dir deadline
  SV=(); STACK_LOGS=(); STACK_RUNS=(); STACK_IDS=()
  for i in "${!STACK[@]}"; do SV[i]=""; STACK_LOGS[i]=""; STACK_RUNS[i]=""; STACK_IDS[i]=""; done
  if [ "$DRY" = screen ]; then
    for i in "${!STACK[@]}"; do SV[i]=g; done; say "(dry=screen) no runner gate; every stack counted green"; return 0
  fi
  for obj in "${STACK[@]}"; do
    git push --quiet --no-verify origin "$obj:refs/heads/gate/queue-$obj" ||
      { say "could not push gate/queue-$obj; this pass ends"; queue_stack_cleanup; return 2; }
  done
  say "gating ${#STACK[@]} stack(s) on the runner (gate/queue-<sha>), at most $QUEUE_RUNNER_WAIT min"
  deadline=$(( $(date +%s) + QUEUE_RUNNER_WAIT * 60 ))
  while :; do
    for i in "${!STACK[@]}"; do
      [ -z "${SV[i]}" ] || continue
      obj="${STACK[i]}"
      line="$(gh_cmd run list -R "$REPO" --workflow gate.yml --branch "gate/queue-$obj" --limit 1 \
        --json headSha,status,conclusion,databaseId,url \
        --jq '.[0] | [.headSha, .status, (.conclusion // "" | if . == "" then "none" else . end), (.databaseId | tostring), .url] | @tsv' 2>/dev/null)"
      IFS=$'\t' read -r _ st _ id url <<< "$line"   # every field non-empty: tab is whitespace to read
      STACK_IDS[i]="$id"
      [ "$st" = completed ] || continue
      dir="$QDIR/stack-$obj"; rm -rf "$dir"; mkdir -p "$dir"
      gh_cmd run download "$id" -R "$REPO" -n "gate-$obj" -D "$dir" >/dev/null 2>&1
      STACK_LOGS[i]="$dir/gate.log"; STACK_RUNS[i]="$url"
      queue_runner_verdict "$obj" "$line" "$dir/gate.log"
      case $? in 0) SV[i]=g ;; 1) SV[i]=r ;; *) SV[i]=n ;; esac
      say "S$((i + 1)) ${obj:0:12} (+#${STACK_FOR[i]}): ${SV[i]} — $(gate_line "$dir/gate.log") $url"
    done
    queue_stack_decided && break
    [ "$(date +%s)" -lt "$deadline" ] ||
      { say "no verdict within $QUEUE_RUNNER_WAIT min; a stack without one counts as n"; break; }
    sleep 60
  done
  queue_stack_cleanup
}
## The gate branches go once the round is decided; a run no verdict depends on any more is cancelled,
## so it frees its runners for the next round.
queue_stack_cleanup() {
  local i
  for i in "${!STACK[@]}"; do
    [ -z "${SV[i]}" ] && [ -n "${STACK_IDS[i]}" ] && gh_cmd run cancel "${STACK_IDS[i]}" -R "$REPO" >/dev/null 2>&1
    git push --quiet --no-verify origin --delete "gate/queue-${STACK[i]}" >/dev/null 2>&1
  done
  return 0
}
queue_main_now() { git fetch --quiet origin main && git rev-parse origin/main; }
## Land stack K: the members it holds, its own object and log, and the base it was composed on.
queue_stack_select() { # K
  BUILT="${STACK[$1 - 1]}"; BUILT_BASE="$STACK_BASE"; GATE_LOG="${STACK_LOGS[$1 - 1]}"
  GATE_MACHINE="the GitHub runner"; GATE_RUN_URL="${STACK_RUNS[$1 - 1]}"
  STACK_NOTE="as stack S$1 of $(prs_h ${STACK_FOR[@]+"${STACK_FOR[@]}"}) over a green S$(($1 - 1))"
}
queue_stack_land() { # K PR...
  local k="$1"; shift
  queue_stack_select "$k"; BUILT_FOR="$*"
  queue_land "$@"
}
queue_stack_fail() { # J PR
  queue_stack_select "$1"
  queue_fail "$2"
}
queue_stack_stop() { # J PR
  local pr="$2" key
  queue_stack_select "$1"; key="$pr=${HEAD[$pr]} stack"
  if [ "$(queue_strike "$QDIR" "$key")" -ge 2 ]; then
    queue_strike_clear "$QDIR" "$key"
    say "S$1 (+#$pr) ended with no verdict twice at the same head; charged to it as red"
    queue_fail "$pr"; return 0
  fi
  say "S$1 (+#$pr) ended with no verdict; this pass ends, everything stays queued"
}

## Which of the screened PRs compose onto origin/main, in order? One that conflicts with main alone is
## sent back for a rebase; one that conflicts only with an earlier member waits for the next pass. The
## queue resolves nothing itself: `queue_merge_member` asks land.sh's append-only settle (#1390) and a
## refusal is the old refusal.
COMPOSED=""
queue_compose_screen() { # PR...
  local base pr mt rc
  COMPOSED=""
  git fetch --quiet origin main || return 0
  base="$(git rev-parse origin/main)"
  git switch --quiet --detach "$base" || return 0
  QUEUE_LAND_REF="$base"     # the base's copy of land.sh settles, never a batch's (#1390)
  for pr in "$@"; do
    git fetch --quiet origin "+refs/pull/$pr/head:refs/remotes/pr/$pr" || continue
    queue_merge_member "refs/remotes/pr/$pr" "screen #$pr"; rc=$?
    if [ "$rc" = 0 ]; then
      COMPOSED="$COMPOSED $pr"
      [ -z "$QUEUE_MERGE_NOTE" ] ||
        say "#$pr composes with an append-only conflict settled (#1390): $(printf '%s ' "$QUEUE_MERGE_NOTE" | tr -s '\n ' ' ')"
      continue
    fi
    git merge --abort 2>/dev/null
    # rc 2 still asks merge-tree: a PR that conflicts with main goes back to its author even when the
    # settle could not run, as before #1390.
    git merge-tree --write-tree "$base" "refs/remotes/pr/$pr" >/dev/null 2>&1; mt=$?
    case "$mt" in
      0) if [ "$rc" = 2 ]; then say "git could not compose #$pr onto the batch; it waits for the next pass"
         else say "#$pr conflicts with an earlier member of this batch in a shape the settle does not cover; it waits for the next pass"; fi ;;
      1) refused "$pr" compose "${HEAD[$pr]}" "conflicts with main $base"
         comment "$pr" "**Merge queue: conflicts with main** on head \`${HEAD[$pr]}\`. Rebase onto \`$base\` and re-enqueue after review. The append-only settle (#1390) covers a conflict confined to \`scripts/e2e.sh\` where both sides only add lines at one anchor; this conflict is not that."
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
  GATE_MACHINE=omen; GATE_RUN_URL=""; STACK_NOTE=""
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

## Recover the queue checkout to `origin/main` before a pass (#1423). A compose that conflicts mid-merge
## leaves `MERGE_HEAD` in `.worktrees/queue`; `git switch` refuses to move while a merge is in flight, so
## every later pass died at bootstrap with rc 128 and the queue sat silent for two hours. The checkout is
## dedicated to the queue — every object it ever holds is either `origin/main` or a compose that was
## already refused and is recomputed next pass — so recovering it is safe, and silence about it is not:
## each step says what it found and what it discarded. Returns 0 when the checkout stands clean at
## `origin/main`, 1 when a human must look.
queue_bootstrap_recover() { # [dir]
  local d="${1:-$ROOT}" g target dirty was=""
  g="$(git -C "$d" rev-parse --absolute-git-dir 2>/dev/null)" || { say "queue: no git checkout at $d"; return 1; }
  target="$(git -C "$d" rev-parse --verify origin/main 2>/dev/null)" ||
    { say "queue: no origin/main to stand on in $d"; return 1; }
  if [ -e "$g/MERGE_HEAD" ] || [ -e "$g/rebase-merge" ] || [ -e "$g/rebase-apply" ] ||
     [ -e "$g/CHERRY_PICK_HEAD" ] || [ -e "$g/BISECT_LOG" ]; then
    was="an unfinished merge or sequencer at $(git -C "$d" rev-parse HEAD)"
    say "queue: #1423 — $was; aborting it, the pass that left it there is over"
    git -C "$d" merge --abort >/dev/null 2>&1 || git -C "$d" merge --quit >/dev/null 2>&1 || true
    git -C "$d" rebase --abort >/dev/null 2>&1 || true
    git -C "$d" cherry-pick --abort >/dev/null 2>&1 || true
    git -C "$d" bisect reset >/dev/null 2>&1 || true
  fi
  if [ "$(git -C "$d" rev-parse HEAD 2>/dev/null)" != "$target" ]; then
    say "queue: #1423 — the checkout stood at $(git -C "$d" rev-parse HEAD), not origin/main $target; detaching"
    git -C "$d" switch -q --detach "$target" 2>/dev/null || {
      dirty="$(git -C "$d" status --porcelain --untracked-files=no | head -n 5)"
      say "queue: #1423 — switch refused; hard-resetting to $target, discarding: $(echo "$dirty" | tr '\n' ' ')"
      git -C "$d" reset --hard -q "$target" || { say "queue: #1423 recovery FAILED — cannot reach $target"; return 1; }
    }
  fi
  dirty="$(git -C "$d" status --porcelain --untracked-files=no)"
  if [ -n "$dirty" ]; then
    say "queue: #1423 — tracked files differ from origin/main; resetting, discarding:"
    echo "$dirty" | head -n 10 | sed 's/^/queue:   /'
    git -C "$d" reset --hard -q "$target" || { say "queue: #1423 recovery FAILED"; return 1; }
    [ -z "$(git -C "$d" status --porcelain --untracked-files=no)" ] ||
      { say "queue: the checkout is dirty after recovery — a human looks at $d now"; return 1; }
  fi
  [ "$(git -C "$d" rev-parse HEAD)" = "$target" ] ||
    { say "queue: recovery ended at $(git -C "$d" rev-parse HEAD), not $target"; return 1; }
  [ -e "$g/MERGE_HEAD" ] && { say "queue: MERGE_HEAD survived recovery in $d"; return 1; }
  [ -n "$was" ] && say "queue: #1423 — recovered, the checkout stands at origin/main $target"
  return 0
}

queue_once() {
  mkdir -p "$QDIR" || die "cannot create $QDIR"
  if [ "${QUEUE_LOCK_HELD:-0}" != 1 ]; then
    exec 9> "$QDIR/lock"
    flock -n 9 || { say "another pass holds the lock"; return 0; }
  fi
  case "$RUNNER" in omen|github) ;; *) die "ALATYR_QUEUE_RUNNER is omen or github, not '$RUNNER'" ;; esac
  queue_bootstrap_recover || die "the queue checkout cannot be cleaned to origin/main (#1423) — see above"
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
    if [ -z "$COMPOSED" ]; then :
    elif [ "$RUNNER" = github ]; then queue_stack_drive $COMPOSED   # #1571
    else queue_drive $COMPOSED; fi
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
ExecStart=/run/current-system/sw/bin/flock -n -o $wt/target/queue/lock /run/current-system/sw/bin/bash -c 'exec >> target/queue/queue.log 2>&1; if [ -e "$(git rev-parse --absolute-git-dir)/MERGE_HEAD" ]; then echo "queue: #1423 — an unfinished merge was left here at $(git rev-parse HEAD); aborting before the pass"; git merge --abort 2>/dev/null || git merge --quit 2>/dev/null || true; fi; git fetch -q origin main && { git switch -q --detach origin/main || { echo "queue: #1423 — switch refused, hard-resetting to $(git rev-parse origin/main)"; git reset --hard -q origin/main || { echo "queue: bootstrap FAILED — the checkout cannot reach origin/main"; exit 1; }; }; } && git show origin/main:scripts/queue.sh > target/queue/queue-run.sh && nix build --inputs-from . nixpkgs#gh -o target/queue/gh-tool && PATH="\$\$PWD/target/queue/gh-tool/bin:\$\$PATH" exec bash target/queue/queue-run.sh --once || { echo "queue: bootstrap failed (rc \$\$?)"; exit 1; }'
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
