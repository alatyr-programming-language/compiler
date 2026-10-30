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
# - Entry is the label `queue` plus a marker comment `queue-head: <sha>`, both written by `--enqueue N`
#   after the alatyr-integrate §2 review. Only the integrator enqueues (alatyr-integrate, alatyr-lane);
#   every panel posts as the same GitHub account, so the marker records WHICH object was reviewed, not
#   who reviewed it. A PR whose head moved past its marker is dropped with a comment, never gated.
# - A pass (`--once`) takes up to ALATYR_QUEUE_MAX (4) queued PRs in PR-number order. Each must target
#   `main`, be ready (not draft, no `hold`), carry exactly one line-initial relation marker, and pass
#   `land.sh N --screen` (preconditions, provenance, PR shape; forks refused) on its reviewed head.
# - A PR that carries an oracle file or a predicted delta is gated alone by `land.sh N` (its PHASE 6a/6c
#   own that path), as alatyr-integrate §3 requires. The others are composed onto origin/main one merge
#   at a time and never resolved: a PR that conflicts with main is sent back; one that conflicts only
#   with an earlier member waits for the next pass.
# - The composed object is gated once by `full.sh`. Green: it is pushed exactly, with
#   `--force-with-lease` on the base it was built on, and every member gets an acceptance comment.
#   Red: the set is bisected — its first half is gated alone, recursively — so a red PR is isolated
#   and marked `queue-failed` with its log tail, while the PRs that are green land.
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
#   scripts/queue.sh --enqueue N [N...]   (the integrator, after review) label + reviewed-head marker
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

## Is the fetched object the reviewed one?
queue_head_ok() { [ -n "$1" ] && [ "$1" = "$2" ]; } # expected fetched

## Green means exit 0 AND the gate's own green verdict line; either alone is not enough.
queue_gate_green() { # rc log
  [ "$1" = 0 ] && grep -q '^\*\*\* FULL GATE: GREEN (sweeps RAN) \*\*\*' "$2" 2>/dev/null
}

## The push of a gated object: that object, onto main, leased on the base it was composed on, hooks off.
queue_push_args() { # object base
  printf '%s\n' "--no-verify origin $1:refs/heads/main --force-with-lease=refs/heads/main:$2"
}

## Is a full gate running on this box? Input: `ps -eo args=`. Only a bash running scripts/full.sh
## counts — not an editor, a pager or an ssh command line that mentions the file.
queue_gate_running() { # ps-args-text -> 0 running, 1 not
  printf '%s\n' "$1" | awk '$1 ~ /(^|\/)bash$/ && $2 ~ /(^|\/)scripts\/full\.sh$/ { f = 1 } END { exit !f }'
}

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
  rm -rf "$t"
  [ "$(queue_push_args "$a" "$b")" = "--no-verify origin $a:refs/heads/main --force-with-lease=refs/heads/main:$b" ]
  _ck $? push-arguments-are-not-the-leased-exact-object
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
  queue_try() { log="$log try:$*;"; return 2; }
  log=""; queue_drive 1 3; [ "$log" = " try:1 3;" ]; _ck $? "infrastructure-failure-did-not-end-the-pass($log)"
  queue_try() { log="$log try:$*;"; return 0; }
  queue_land() { log="$log land:$*;"; return 1; }
  log=""; queue_drive 1 3; [ "$log" = " try:1 3; land:1 3;" ]; _ck $? "failed-publish-did-not-end-the-pass($log)"
  unset -f queue_try queue_land queue_fail
  if [ -n "$bad" ]; then echo "*** queue self-test: FAILED —$bad ***"; return 1; fi
  echo "ok   queue self-test: $k checks — reviewed-head marker, entry rules, head check, gate verdict,"
  echo "     push arguments, busy box and the bisection plan"
  [ "$k" -ge 28 ] || { echo "queue self-test: $k checks, expected 28"; return 1; }
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
pr_marker() { # pr -> reviewed head
  queue_marker_head "$(pr_field "$1" comments \
    '.comments[] | .authorAssociation as $a | .body | split("\n")[] | "\($a)\t\(.)"')"
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
  wait_for_box || return 2
  say "gating $BUILT (base $base) for $(prs_h "$@"); log $GATE_LOG"
  local empty_gh rc; empty_gh="$(mktemp -d "$QDIR/gh-empty.XXXXXX")"
  ( ulimit -c 0
    env -u GH_TOKEN -u GITHUB_TOKEN GIT_CONFIG_GLOBAL=/dev/null GH_CONFIG_DIR="$empty_gh" \
      nix develop -c bash scripts/full.sh --force-sweeps ) > "$GATE_LOG" 2>&1 9>&-
  rc=$?
  rm -rf "$empty_gh"
  git diff --exit-code --quiet && git diff --cached --exit-code --quiet &&
    [ "$(git rev-parse HEAD)" = "$BUILT" ] || { say "the tree moved during the gate; this pass ends"; return 2; }
  queue_gate_green "$rc" "$GATE_LOG" || { say "RED (full.sh rc $rc) on $BUILT"; return 1; }
  say "GREEN on $BUILT"
  return 0
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

queue_land() { # PR... — publish exactly BUILT
  [ "$BUILT_FOR" = "$*" ] || die "internal: asked to land [$*] but built [$BUILT_FOR]"
  queue_publish "$BUILT" "$BUILT_BASE" || return 1
  queue_accept "batch" "$BUILT" "$BUILT_BASE" "$GATE_LOG" "$@"
}

queue_fail() { # PR
  local pr="$1"
  say "#$pr isolated as red"
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
      1) comment "$pr" "**Merge queue: conflicts with main** on head \`${HEAD[$pr]}\`. Rebase onto \`$base\` and re-enqueue after review."
         relabel "$pr" queue-failed queue ;;
      *) say "git merge-tree failed (rc $mt) on #$pr; it waits for the next pass" ;;
    esac
  done
  git switch --quiet --detach "$base"
}

## A PR with an oracle file or a predicted delta is gated alone by land.sh, whose PHASE 6a/6c own that
## path, on exactly the reviewed head. The queue pushes the object land.sh names; land.sh never pushes.
queue_solo() { # pr -> 0 done (landed, failed or dropped), 2 the pass ends
  local pr="$1" log="$QDIR/solo-$1-$(date -u +%Y%m%dT%H%M%S).log" rc obj base
  if [ "$DRY" = screen ]; then say "(dry=screen) #$pr would be landed alone"; return 0; fi
  wait_for_box || return 2
  say "solo landing #$pr (oracle or predicted delta) at ${HEAD[$pr]}; log $log"
  ( env -u GH_TOKEN -u GITHUB_TOKEN ALATYR_LAND_EXPECT_HEAD="${HEAD[$pr]}" bash scripts/land.sh "$pr" ) > "$log" 2>&1 9>&-
  rc=$?
  GATE_LOG="$log"; BUILT_BASE="$(sed -n 's/^  base=\([0-9a-f]*\)$/\1/p' "$log" | head -1)"
  BUILT="$(sed -n 's/^  merged as \([0-9a-f]*\)$/\1/p' "$log" | head -1)"
  obj="$(sed -n 's/^\*\*\* GATE GREEN on the merged tree — \([0-9a-f]\{40\}\) is landable \*\*\*$/\1/p' "$log")"
  git switch --quiet --detach origin/main 2>/dev/null
  if [ "$rc" = 0 ] && [ -n "$obj" ] && [ -n "$BUILT_BASE" ]; then
    queue_publish "$obj" "$BUILT_BASE" || return 2
    queue_accept "alone, through land.sh" "$obj" "$BUILT_BASE" "$log" "$pr"
    return 0
  fi
  if grep -q '^\*\*\* NOT LANDABLE' "$log"; then queue_fail "$pr"; return 0; fi
  if grep -q -e '^\*\*\* LAND REFUSED (PR shape)' -e '^\*\*\* LAND REFUSED (the merge conflicts)' "$log"; then
    queue_fail "$pr"; return 0
  fi
  if grep -q '^\*\*\* LAND REFUSED (head moved)' "$log"; then
    comment "$pr" "**Merge queue: dropped.** The head moved past the reviewed \`${HEAD[$pr]}\` before its solo gate. Review the current head and re-enqueue."
    relabel "$pr" "" queue; return 0
  fi
  say "solo landing of #$pr stopped for a reason that is not the PR's (rc $rc); see $log"
  return 2
}

queue_once() {
  mkdir -p "$QDIR" || die "cannot create $QDIR"
  if [ "${QUEUE_LOCK_HELD:-0}" != 1 ]; then
    exec 9> "$QDIR/lock"
    flock -n 9 || { say "another pass holds the lock"; return 0; }
  fi
  [ -z "$(git status --porcelain --untracked-files=no)" ] || die "the queue checkout is dirty"
  local prs pr head marker out why solo batch=() shead rc
  prs="$(gh_cmd pr list -R "$REPO" --label queue --state open --json number --jq '.[].number' | sort -n | head -n "$QUEUE_MAX")"
  [ -n "$prs" ] || { say "queue empty"; return 0; }
  say "queued: $(echo $prs)"
  for pr in $prs; do
    head="$(pr_field "$pr" headRefOid .headRefOid)"; marker="$(pr_marker "$pr")"
    if ! queue_head_ok "$marker" "$head"; then
      comment "$pr" "**Merge queue: dropped.** The reviewed head is \`${marker:-none}\`; the current head is \`$head\`. A verdict covers one object: review the current head and re-enqueue (\`scripts/queue.sh --enqueue $pr\`)."
      relabel "$pr" "" queue; continue
    fi
    why="$(queue_entry_refusal "$(pr_field "$pr" baseRefName .baseRefName)" "$(pr_field "$pr" isDraft .isDraft)" \
            "$(pr_field "$pr" labels '[.labels[].name] | join(",")')" "$(pr_field "$pr" body .body)")"
    if [ -n "$why" ]; then
      comment "$pr" "**Merge queue: refused** on head \`$head\`: $why."
      relabel "$pr" queue-failed queue; continue
    fi
    out="$(ALATYR_LAND_EXPECT_HEAD="$head" bash scripts/land.sh "$pr" --screen 2>&1 9>&-)"; rc=$?
    shead="$(printf '%s\n' "$out" | sed -n 's/^land-screen: pr=[0-9]* head=\([0-9a-f]*\) .*$/\1/p')"
    if [ "$rc" != 0 ] || ! queue_head_ok "$head" "$shead"; then
      if printf '%s\n' "$out" | grep -q -e '^\*\*\* LAND REFUSED (PR shape)' -e '^\*\*\* LAND REFUSED (screen)'; then
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
    LINK[$pr]="$(printf '%s\n' "$out" | sed -n 's/^land-screen: .* link=\(.*\)$/\1/p')"
    BRANCH[$pr]="$(pr_field "$pr" headRefName .headRefName)"
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

queue_enqueue() { # PR...
  local pr head
  for pr in "$@"; do
    head="$(pr_field "$pr" headRefOid .headRefOid)" || die "cannot read #$pr"
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

## The timer runs in a checkout of its own: a gate switches the tree, and two target-producing gates
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
ExecStart=/run/current-system/sw/bin/flock -n $wt/target/queue/lock /run/current-system/sw/bin/bash -c 'git fetch -q origin main && git switch -q --detach origin/main && git show origin/main:scripts/queue.sh > target/queue/queue-run.sh && nix build --inputs-from . nixpkgs#gh -o target/queue/gh-tool && PATH="\$\$PWD/target/queue/gh-tool/bin:\$\$PATH" exec bash target/queue/queue-run.sh --once >> target/queue/queue.log 2>&1'
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
  --once)      cd "$ROOT" && queue_once ;;
  --install)   queue_install ;;
  *) sed -n '/^# ## Usage/,/^set -u/p' "$SELF" | sed -e 's/^# \{0,1\}//' -e '$d'; exit 2 ;;
esac
