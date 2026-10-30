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
# - Entry is the label `queue` plus a marker comment `queue-head: <sha>` by a repository member,
#   both written by `--enqueue N` after the alatyr-integrate §2 review. The marker is the verdict's
#   object: a PR whose head moved after it is dropped from the queue with a comment, never gated.
# - A pass (`--once`) takes up to ALATYR_QUEUE_MAX (4) queued PRs in PR-number order and screens each
#   with `land.sh N --screen` (preconditions, provenance, PR shape). A refused PR gets `queue-failed`.
#   A PR that carries an oracle file or a predicted delta is landed alone by `land.sh N --push`, as
#   alatyr-integrate §3 requires; the others are composed onto origin/main one merge at a time, and a
#   PR that does not merge cleanly is sent back (on main alone) or left for the next pass (against an
#   earlier member).
# - The composed object is gated once by `full.sh`. Green: it is pushed exactly, with
#   `--force-with-lease` on the base it was built on, and every member gets an acceptance comment.
#   Red: the set is bisected — its first half is gated alone, recursively — so a red PR is isolated
#   and marked `queue-failed` with its log tail, while the PRs that are green land.
# - Every PR the queue touches leaves with a comment naming its current head: landed, failed, dropped.
#
# ## Trust
#
# The timer runs the copy of this script on origin/main, never one from a batch, and `land.sh` runs
# from main's checkout too (and from its own private copy, #1093). Fork PRs are refused. The gate's
# environment carries no GH_TOKEN/GITHUB_TOKEN, no global git config (so no credential helper) and an
# empty gh config dir; the push is a separate step after the gate exits. A same-organisation PR that
# reads ~/.config/gh directly is outside this boundary — entry by review is what covers that.
#
# ## Usage
#
#   scripts/queue.sh --enqueue N [N...]   (integrator, after review) label + head marker
#   scripts/queue.sh --status             the queue, and whether each PR's last verdict names its head
#   scripts/queue.sh --once               one pass (what the timer runs on omen)
#   scripts/queue.sh --install            write and start the systemd user timer on omen
#   scripts/queue.sh --self-test          the deciders: marker parsing, the bisection plan
#
#   ALATYR_QUEUE_DRY=1       --once screens, composes and gates but neither pushes, labels nor comments
#   ALATYR_QUEUE_DRY=screen  as 1, and the gate is skipped (counted green): a check of the plumbing
set -u

SELF="$0"
## The timer runs a copy under target/queue/ (so a `git switch` cannot rewrite the running file, the
## #1093 hazard), so the root is the enclosing checkout, not the script's parent directory.
ROOT="$(git -C "$(dirname "$SELF")" rev-parse --show-toplevel 2>/dev/null)" || { echo "queue: not inside a checkout" >&2; exit 2; }
REPO="${ALATYR_REPO:-alatyr-programming-language/compiler}"
QUEUE_MAX="${ALATYR_QUEUE_MAX:-4}"
DRY="${ALATYR_QUEUE_DRY:-0}"
QDIR="$ROOT/target/queue"

say() { printf '%s queue: %s\n' "$(date -u +%FT%TZ)" "$*"; }
die() { printf 'queue: %s\n' "$*" >&2; exit 2; }

# ---- deciders (pure; held by --self-test) ---------------------------------------------------------

## The reviewed head: the LAST `queue-head: <40-hex>` line among trusted comments, one comment body
## per input line group. Input: the comment bodies of repository members, oldest first.
queue_marker_head() { # bodies-text -> prints the sha or nothing
  printf '%s\n' "$1" | sed -n 's/^queue-head: \([0-9a-f]\{40\}\)[[:space:]]*$/\1/p' | tail -n 1
}

## The bisection driver. It calls three functions the caller defines:
##   queue_try PR...   0 green, 1 red, 2 could not compose (left for the next pass)
##   queue_land PR...  publish the object queue_try last built for exactly these PRs
##   queue_fail PR     mark one PR red
## A red set of n>1 is narrowed to its first floor(n/2); the rest wait their turn behind it in the
## same pass, so a planted red PR in [a r c] costs five gates: [a r c] red, [a] green and lands,
## [r c] red, [r] red and fails, [c] green and lands.
queue_drive() { # PR...
  local set=("$@") rest=() h
  while [ "${#set[@]}" -gt 0 ]; do
    queue_try "${set[@]}"
    case $? in
      0) queue_land "${set[@]}"
         set=(${rest[@]+"${rest[@]}"}); rest=() ;;
      2) return 0 ;;
      *) if [ "${#set[@]}" = 1 ]; then
           queue_fail "${set[0]}"
           set=(${rest[@]+"${rest[@]}"}); rest=()
         else
           h=$(( ${#set[@]} / 2 ))
           rest=("${set[@]:h}" ${rest[@]+"${rest[@]}"})
           set=("${set[@]:0:h}")
         fi ;;
    esac
  done
}

queue_self_test() {
  local k=0 bad="" log
  _ck() { k=$((k+1)); [ "$1" = 0 ] || bad="$bad $2"; }
  local a=1111111111111111111111111111111111111111 b=2222222222222222222222222222222222222222
  [ "$(queue_marker_head "$(printf 'review ok\nqueue-head: %s\nlater\nqueue-head: %s' "$a" "$b")")" = "$b" ]
  _ck $? marker-did-not-take-the-last-head
  [ -z "$(queue_marker_head "queue-head: ${a:0:12}")" ]; _ck $? marker-took-an-abbreviated-sha
  [ -z "$(queue_marker_head "see queue-head: $a")" ]; _ck $? marker-took-a-mid-line-mention
  [ -z "$(queue_marker_head "")" ]; _ck $? marker-invented-a-head
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
  log=""; queue_drive 1 3; [ "$log" = " try:1 3;" ]; _ck $? "compose-failure-did-not-stop-the-pass($log)"
  unset -f queue_try queue_land queue_fail
  if [ -n "$bad" ]; then echo "*** queue self-test: FAILED —$bad ***"; return 1; fi
  echo "ok   queue self-test: $k checks — head marker parsing and the bisection plan"
  [ "$k" -ge 9 ] || { echo "queue self-test: $k checks, expected 9"; return 1; }
}

# ---- GitHub ------------------------------------------------------------------------------------------
gh_cmd() { command -v gh >/dev/null 2>&1 || die "gh is required"; gh "$@"; }
comment() { # pr body
  if [ "$DRY" != 0 ]; then printf -- '--- (dry) comment on #%s:\n%s\n' "$1" "$2"; return 0; fi
  gh_cmd pr comment "$1" -R "$REPO" --body "$2" >/dev/null
}
relabel() { # pr add remove
  [ "$DRY" != 0 ] && return 0
  local args=()
  [ -n "$2" ] && args+=(--add-label "$2")
  [ -n "$3" ] && args+=(--remove-label "$3")
  gh_cmd pr edit "$1" -R "$REPO" "${args[@]}" >/dev/null
}
pr_head() { gh_cmd pr view "$1" -R "$REPO" --json headRefOid --jq .headRefOid; }
pr_marker() { # pr -> reviewed head from trusted comments
  queue_marker_head "$(gh_cmd pr view "$1" -R "$REPO" --json comments --jq \
    '.comments[] | select(.authorAssociation == "OWNER" or .authorAssociation == "MEMBER" or .authorAssociation == "COLLABORATOR") | .body')"
}

# ---- one pass ----------------------------------------------------------------------------------------
## Wait while another full gate runs on this box: one gate per box (two at once share /tmp and the
## CPU, and each makes the other's timings and its scratch files wrong).
wait_for_box() {
  local n=0
  while pgrep -f 'scripts/full\.sh' >/dev/null 2>&1; do
    [ "$n" = 0 ] && say "another full gate is running on this box; waiting"
    n=$((n+1)); [ "$n" -le 180 ] || { say "box still busy after 3 h; ending the pass"; return 1; }
    sleep 60
  done
}

BUILT_FOR=""; BUILT=""; BUILT_BASE=""; GATE_LOG=""
HEAD=(); LINK=(); LABEL=()   # indexed by PR number

queue_try() { # PR... — compose onto origin/main and gate
  git fetch --quiet origin main || return 2
  local base pr msg
  base="$(git rev-parse origin/main)"
  git switch --quiet --detach "$base" || return 2
  for pr in "$@"; do
    git fetch --quiet origin "+refs/pull/$pr/head:refs/remotes/pr/$pr" || return 2
    [ "$(git rev-parse "refs/remotes/pr/$pr")" = "${HEAD[$pr]}" ] || { say "#$pr moved during the pass"; return 2; }
    msg="merge #$pr: ${LABEL[$pr]}"
    [ -n "${LINK[$pr]}" ] && msg="$msg

${LINK[$pr]}"
    git merge --quiet --no-ff --no-verify -m "$msg" "refs/remotes/pr/$pr" >/dev/null 2>&1 ||
      { git merge --abort 2>/dev/null; say "#$pr no longer composes onto $base"; return 2; }
  done
  BUILT="$(git rev-parse HEAD)"; BUILT_BASE="$base"; BUILT_FOR="$*"
  GATE_LOG="$QDIR/gate-$(date -u +%Y%m%dT%H%M%S)-$(git rev-parse --short HEAD).log"
  if [ "$DRY" = screen ]; then say "(dry=screen) composed $BUILT for #${*// / #}; gate skipped"; return 0; fi
  wait_for_box || return 2
  say "gating $BUILT (base $base) for #${*// / #}; log $GATE_LOG"
  local empty_gh; empty_gh="$(mktemp -d "$QDIR/gh-empty.XXXXXX")"
  ( ulimit -c 0
    env -u GH_TOKEN -u GITHUB_TOKEN GIT_CONFIG_GLOBAL=/dev/null GH_CONFIG_DIR="$empty_gh" \
      nix develop -c bash scripts/full.sh --force-sweeps ) > "$GATE_LOG" 2>&1
  local rc=$?
  rm -rf "$empty_gh"
  git diff --exit-code --quiet && git diff --cached --exit-code --quiet &&
    [ "$(git rev-parse HEAD)" = "$BUILT" ] || { say "the tree moved during the gate"; return 1; }
  [ "$rc" = 0 ] && grep -q '^\*\*\* FULL GATE: GREEN (sweeps RAN) \*\*\*' "$GATE_LOG" || {
    say "RED (full.sh rc $rc) on $BUILT"; return 1; }
  say "GREEN on $BUILT"
  return 0
}

gate_line() { grep -m1 '^\*\*\* FULL GATE' "$GATE_LOG" 2>/dev/null || echo '(no verdict line)'; }

queue_land() { # PR... — publish exactly BUILT
  [ "$BUILT_FOR" = "$*" ] || die "internal: asked to land [$*] but built [$BUILT_FOR]"
  if [ "$DRY" != 0 ]; then say "(dry) would push $BUILT over $BUILT_BASE"; return 0; fi
  git push --quiet origin "$BUILT:refs/heads/main" --force-with-lease="refs/heads/main:$BUILT_BASE" || {
    say "push rejected: main moved after $BUILT_BASE; the set stays queued"; return 0; }
  git fetch --quiet origin main
  git merge-base --is-ancestor "$BUILT" origin/main || die "pushed $BUILT but origin/main does not contain it"
  say "LANDED $BUILT for #${*// / #}"
  local pr members="#${*// / #}" branch
  for pr in "$@"; do
    comment "$pr" "**Landed by the merge queue** (\`scripts/queue.sh\`, #1127), no agent session attached.

- reviewed head: \`${HEAD[$pr]}\` (the \`queue-head\` marker)
- batch: $members, composed onto \`$BUILT_BASE\` as \`$BUILT\`, which is now \`main\`
- gate on omen, on that exact object: \`$(gate_line)\` (log \`$(basename "$GATE_LOG")\` under \`target/queue/\` on omen)
- check: \`git merge-base --is-ancestor $BUILT origin/main\`
${LINK[$pr]:+- issue: ${LINK[$pr]}}"
    relabel "$pr" "" queue
    git update-ref -d "refs/remotes/pr/$pr" 2>/dev/null
    branch="${LABEL[$pr]}"
    if git merge-base --is-ancestor "${HEAD[$pr]}" origin/main &&
       [ "$(git ls-remote origin "refs/heads/$branch" | cut -f1)" = "${HEAD[$pr]}" ]; then
      git push --quiet origin --delete "$branch" || say "could not delete $branch (left in place)"
    fi
  done
}

queue_fail() { # PR
  local pr="$1"
  say "#$pr isolated as red"
  comment "$pr" "**Merge queue: red** on head \`${HEAD[$pr]}\` (\`scripts/queue.sh\`, #1127).

Gated alone on \`$BUILT_BASE\` as \`$BUILT\`: \`$(gate_line)\`. Log \`$(basename "$GATE_LOG")\` under \`target/queue/\` on omen; its failing lines:

\`\`\`
$(grep -E 'FAIL|MISMATCH|REFUSED|error' "$GATE_LOG" 2>/dev/null | tail -n 30)
\`\`\`

The label moved to \`queue-failed\`. Fix, push, and re-enqueue after review."
  relabel "$pr" queue-failed queue
}

queue_once() {
  mkdir -p "$QDIR" || die "cannot create $QDIR"
  exec 9> "$QDIR/lock"
  flock -n 9 || { say "another pass holds the lock"; return 0; }
  [ -z "$(git status --porcelain --untracked-files=no)" ] || die "the queue worktree is dirty"
  local prs pr head marker out solo batch=()
  prs="$(gh_cmd pr list -R "$REPO" --label queue --state open --json number --jq '.[].number' | sort -n | head -n "$QUEUE_MAX")"
  [ -n "$prs" ] || { say "queue empty"; return 0; }
  say "queued: $(echo $prs)"
  for pr in $prs; do
    head="$(pr_head "$pr")"; marker="$(pr_marker "$pr")"
    if [ -z "$marker" ] || [ "$marker" != "$head" ]; then
      comment "$pr" "**Merge queue: dropped.** The reviewed head is \`${marker:-none}\`; the current head is \`$head\`. A verdict covers one object: review the current head and re-enqueue (\`scripts/queue.sh --enqueue $pr\`)."
      relabel "$pr" "" queue; continue
    fi
    out="$(bash scripts/land.sh "$pr" --screen 2>&1)"
    if ! printf '%s\n' "$out" | grep -q '^land-screen: '; then
      comment "$pr" "**Merge queue: refused at the screen** on head \`$head\` (\`land.sh $pr --screen\`):

\`\`\`
$(printf '%s\n' "$out" | tail -n 25)
\`\`\`"
      relabel "$pr" queue-failed queue; continue
    fi
    HEAD[$pr]="$head"
    LINK[$pr]="$(printf '%s\n' "$out" | sed -n 's/^land-screen: .* link=\(.*\)$/\1/p')"
    LABEL[$pr]="$(gh_cmd pr view "$pr" -R "$REPO" --json headRefName --jq .headRefName)"
    solo="$(printf '%s\n' "$out" | sed -n 's/^land-screen: .* solo=\([a-z]*\) .*$/\1/p')"
    if [ "$solo" = yes ]; then
      [ "${#batch[@]}" = 0 ] || continue   # a solo PR waits until it is first in line
      queue_solo "$pr"; return 0
    fi
    batch+=("$pr")
  done
  [ "${#batch[@]}" -gt 0 ] || return 0
  queue_compose_screen "${batch[@]}"
  [ -n "$COMPOSED" ] || { git switch --quiet --detach origin/main 2>/dev/null; return 0; }
  queue_drive $COMPOSED
  git switch --quiet --detach origin/main 2>/dev/null
}

## A PR with a predicted oracle change is gated alone by land.sh, whose PHASE 6a/6c own that path.
queue_solo() { # pr
  local pr="$1" log="$QDIR/solo-$1-$(date -u +%Y%m%dT%H%M%S).log" flags=""
  wait_for_box || return 0
  [ "$DRY" != 0 ] || flags="--push"
  say "solo landing #$pr (oracle or predicted delta); log $log"
  ( env -u GH_TOKEN -u GITHUB_TOKEN bash scripts/land.sh "$pr" $flags ) > "$log" 2>&1
  local rc=$?
  GATE_LOG="$log"; BUILT="$(sed -n 's/^  merged as \([0-9a-f]*\)$/\1/p' "$log" | head -1)"
  BUILT_BASE="$(sed -n 's/^  base=\([0-9a-f]*\)$/\1/p' "$log" | head -1)"
  if [ "$rc" = 0 ] && grep -q '^\*\*\* LANDED' "$log"; then
    BUILT="$(sed -n 's/^\*\*\* LANDED — main is now \([0-9a-f]*\) \*\*\*$/\1/p' "$log")"
    git fetch --quiet origin main
    if git merge-base --is-ancestor "$BUILT" origin/main; then
      comment "$pr" "**Landed by the merge queue** (\`scripts/queue.sh\`, #1127, solo through \`land.sh $pr --push\`), no agent session attached.

- reviewed head: \`${HEAD[$pr]}\` (the \`queue-head\` marker)
- base \`$BUILT_BASE\`; \`main\` is now \`$BUILT\`
- gate on omen: \`$(gate_line)\`; landing log \`$(basename "$log")\` under \`target/queue/\`
${LINK[$pr]:+- issue: ${LINK[$pr]}}"
      relabel "$pr" "" queue
    else
      say "#$pr: land.sh reported LANDED but origin/main does not contain $BUILT"
    fi
  elif grep -q 'PUSH REJECTED' "$log"; then
    say "#$pr: main moved during the solo landing; it stays queued"
  elif [ "$DRY" != 0 ] && [ "$rc" = 0 ]; then
    say "(dry) #$pr solo landing green"
  else
    queue_fail "$pr"
  fi
  git switch --quiet --detach origin/main 2>/dev/null
}

## Which of the screened PRs compose onto origin/main, in order? One that conflicts with main alone is
## sent back for a rebase. One that conflicts only with an earlier member waits for the next pass: the
## queue never resolves a conflict, because that resolution is a semantic decision (alatyr-integrate §3).
COMPOSED=""
queue_compose_screen() { # PR...
  local base pr; COMPOSED=""
  git fetch --quiet origin main || return 0
  base="$(git rev-parse origin/main)"
  git switch --quiet --detach "$base" || return 0
  for pr in "$@"; do
    git fetch --quiet origin "+refs/pull/$pr/head:refs/remotes/pr/$pr" || continue
    if git merge --quiet --no-ff --no-verify -m "screen #$pr" "refs/remotes/pr/$pr" >/dev/null 2>&1; then
      COMPOSED="$COMPOSED $pr"; continue
    fi
    git merge --abort 2>/dev/null
    if git merge-tree --write-tree "$base" "refs/remotes/pr/$pr" >/dev/null 2>&1; then
      say "#$pr conflicts with an earlier member of this batch; it waits for the next pass"
    else
      comment "$pr" "**Merge queue: conflicts with main** on head \`${HEAD[$pr]}\`. Rebase onto \`$base\` and re-enqueue after review."
      relabel "$pr" queue-failed queue
    fi
  done
  git switch --quiet --detach "$base"
}

queue_enqueue() { # PR...
  local pr head
  for pr in "$@"; do
    head="$(pr_head "$pr")" || die "cannot read #$pr"
    gh_cmd pr comment "$pr" -R "$REPO" --body "Reviewed (alatyr-integrate §2); entering the merge queue (#1127).

queue-head: $head" >/dev/null || die "could not comment on #$pr"
    gh_cmd pr edit "$pr" -R "$REPO" --add-label queue --remove-label queue-failed >/dev/null 2>&1 ||
      gh_cmd pr edit "$pr" -R "$REPO" --add-label queue >/dev/null || die "could not label #$pr"
    echo "enqueued #$pr at $head"
  done
}

queue_status() {
  local pr head marker labels
  for pr in $(gh_cmd pr list -R "$REPO" --state open --search 'label:queue,queue-failed' --json number --jq '.[].number' | sort -n); do
    head="$(pr_head "$pr")"; marker="$(pr_marker "$pr")"
    labels="$(gh_cmd pr view "$pr" -R "$REPO" --json labels --jq '[.labels[].name | select(startswith("queue"))] | join(",")')"
    printf '#%s\t%s\thead %s\t%s\n' "$pr" "$labels" "${head:0:12}" \
      "$([ "$marker" = "$head" ] && echo 'verdict on this head' || echo "STALE verdict (${marker:0:12})")"
  done
}

queue_install() {
  local wt; wt="$(cd "$ROOT" && pwd)"
  local unit="$HOME/.config/systemd/user"
  mkdir -p "$unit" || die "cannot create $unit"
  cat > "$unit/alatyr-queue.service" <<EOF
[Unit]
Description=Alatyr compiler merge queue, one pass (scripts/queue.sh, #1127)

[Service]
Type=oneshot
WorkingDirectory=$wt
Environment=PATH=/run/current-system/sw/bin:/etc/profiles/per-user/%u/bin:%h/.nix-profile/bin
ExecStart=/run/current-system/sw/bin/bash -c 'git fetch -q origin main && git switch -q --detach origin/main && mkdir -p target/queue && git show origin/main:scripts/queue.sh > target/queue/queue-run.sh && exec nix shell nixpkgs#gh nixpkgs#util-linux nixpkgs#procps -c bash target/queue/queue-run.sh --once >> target/queue/queue.log 2>&1'
TimeoutStartSec=12h
EOF
  cat > "$unit/alatyr-queue.timer" <<EOF
[Unit]
Description=Run the Alatyr merge queue every 15 minutes

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
