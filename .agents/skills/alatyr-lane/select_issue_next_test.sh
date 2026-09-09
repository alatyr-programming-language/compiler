#!/usr/bin/env bash
# Prove refresh, local progression, and later-iteration refusal as one controller sequence.
set -u

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
NEXT="$ROOT/.agents/skills/alatyr-lane/select_issue_next.sh"
ADD="$ROOT/.agents/skills/alatyr-lane/add_issue_exclusion.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/bin"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -eu' \
  'case "$1 $2" in' \
  '  "pr list") cat "$FAKE_PRS" ;;' \
  '  "issue list") cat "$FAKE_ISSUES" ;;' \
  '  *) exit 2 ;;' \
  'esac' >"$WORK/bin/gh"
chmod +x "$WORK/bin/gh"

printf '[]\n' >"$WORK/prs-empty.json"
printf '%s\n' \
  '[{"number":360,"state":"OPEN","title":"first","createdAt":"2026-01-01T00:00:00Z","author":{"login":"nizovtsevnv"},"labels":[{"name":"priority-0"}]},' \
  ' {"number":361,"state":"OPEN","title":"second","createdAt":"2026-01-02T00:00:00Z","author":{"login":"nizovtsevnv"},"labels":[{"name":"priority-1"}]}]' \
  >"$WORK/issues.json"

checks=0
fail=0
pass() { checks=$((checks + 1)); echo "ok   lane-refresh: $*"; }
flunk() { checks=$((checks + 1)); fail=1; echo "FAIL lane-refresh: $*"; }

select_next() {
  local state="$1" prs="$2" issues="$3"
  PATH="$WORK/bin:$PATH" FAKE_PRS="$prs" FAKE_ISSUES="$issues" \
    bash "$NEXT" alatyr-programming-language/compiler nizovtsevnv "$state"
}

state="$WORK/state"
mkdir "$state"
got="$(select_next "$state" "$WORK/prs-empty.json" "$WORK/issues.json")"
if [ "$got" = 360 ] && [ "$(cat "$state/initial-issue-bound")" = 2 ]; then
  pass "initial refresh selects first candidate and records finite bound"
else
  flunk "initial refresh returned '$got' with bound '$(cat "$state/initial-issue-bound" 2>/dev/null)'"
fi

if bash "$ADD" "$state/exclusions.json" 360 2; then
  pass "durable disposition advances local state"
else
  flunk "could not record first disposition"
fi

got="$(select_next "$state" "$WORK/prs-empty.json" "$WORK/issues.json")"
if [ "$got" = 361 ]; then
  pass "second refresh selects the next ranked candidate"
else
  flunk "second refresh returned '$got', expected 361"
fi

printf '%s\n' \
  '[{"number":700,"state":"OPEN","body":"Refs #361","isCrossRepository":false,' \
  '  "headRepository":{"nameWithOwner":"alatyr-programming-language/compiler"},' \
  '  "labels":[],"files":[],"changedFiles":0,"closingIssuesReferences":[]}]' \
  >"$WORK/prs-new.json"
rc=0
select_next "$state" "$WORK/prs-new.json" "$WORK/issues.json" >"$WORK/new-pr.out" 2>"$WORK/new-pr.err" || rc=$?
if [ "$rc" -eq 3 ]; then
  pass "refreshed PR ownership excludes a newly claimed next candidate"
else
  flunk "new PR refresh returned $rc, expected empty queue exit 3"
fi

state_bad="$WORK/state-bad"
mkdir "$state_bad"
got="$(select_next "$state_bad" "$WORK/prs-empty.json" "$WORK/issues.json")"
if [ "$got" = 360 ]; then
  pass "later-refusal setup selected first candidate"
else
  flunk "later-refusal setup returned '$got'"
fi
bash "$ADD" "$state_bad/exclusions.json" 360 2
printf '%s\n' \
  '[{"number":360,"state":"OPEN","title":"first","createdAt":"2026-01-01T00:00:00Z","author":{"login":"nizovtsevnv"},"labels":[{"name":"priority-0"}]},' \
  ' {"number":361,"state":"OPEN","title":"second","createdAt":"2026-01-02T00:00:00Z","author":{"login":"nizovtsevnv"},"labels":"malformed"}]' \
  >"$WORK/issues-malformed.json"
rc=0
select_next "$state_bad" "$WORK/prs-empty.json" "$WORK/issues-malformed.json" \
  >"$WORK/malformed.out" 2>"$WORK/malformed.err" || rc=$?
if [ "$rc" -eq 2 ]; then
  pass "later refresh preserves metadata refusal"
else
  flunk "later malformed refresh returned $rc, expected 2"
fi

if [ "$checks" -ne 6 ]; then
  echo "FAIL lane-refresh: expected 6 checks, reached $checks" >&2
  exit 1
fi
if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "ok   lane-refresh: proof-of-work checks=$checks"
