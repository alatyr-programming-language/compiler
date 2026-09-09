#!/usr/bin/env bash
# Non-vacuous state and progression tests for invocation-local issue exclusions.
set -u

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
ADD="$ROOT/.agents/skills/alatyr-lane/add_issue_exclusion.sh"
SELECT="$ROOT/.agents/skills/alatyr-lane/select_issue.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

checks=0
fail=0
pass() { checks=$((checks + 1)); echo "ok   lane-progression: $*"; }
flunk() { checks=$((checks + 1)); fail=1; echo "FAIL lane-progression: $*"; }

printf '[]\n' >"$WORK/prs.json"
printf '%s\n' \
  '[{"number":360,"state":"OPEN","title":"first","createdAt":"2026-01-01T00:00:00Z","author":{"login":"nizovtsevnv"},"labels":[{"name":"priority-0"}]},' \
  ' {"number":361,"state":"OPEN","title":"second","createdAt":"2026-01-02T00:00:00Z","author":{"login":"nizovtsevnv"},"labels":[{"name":"priority-1"}]},' \
  ' {"number":362,"state":"OPEN","title":"third","createdAt":"2026-01-03T00:00:00Z","author":{"login":"nizovtsevnv"},"labels":[]}]' \
  >"$WORK/issues.json"
printf '[]\n' >"$WORK/exclusions.json"

select_one() {
  bash "$SELECT" alatyr-programming-language/compiler nizovtsevnv \
    "$WORK/prs.json" "$WORK/issues.json" "$WORK/exclusions.json" 2>"$WORK/select.err"
}

for want in 360 361 362; do
  got="$(select_one)"
  if [ "$got" = "$want" ]; then
    pass "selected #$want in deterministic order"
  else
    flunk "selected #$got, expected #$want"
  fi
  if bash "$ADD" "$WORK/exclusions.json" "$want" 3; then
    pass "recorded #$want within initial bound"
  else
    flunk "could not record #$want"
  fi
done

rc=0
select_one >"$WORK/empty.out" || rc=$?
if [ "$rc" -eq 3 ]; then
  pass "three durable exclusions terminate as an empty queue"
else
  flunk "exhausted progression returned $rc, expected 3"
fi

rc=0
bash "$ADD" "$WORK/exclusions.json" 362 3 >"$WORK/repeat.out" 2>"$WORK/repeat.err" || rc=$?
if [ "$rc" -eq 2 ]; then
  pass "repeated selected issue is refused"
else
  flunk "repeated issue returned $rc, expected 2"
fi

printf '[1,2]\n' >"$WORK/bounded.json"
rc=0
bash "$ADD" "$WORK/bounded.json" 3 2 >"$WORK/bound.out" 2>"$WORK/bound.err" || rc=$?
if [ "$rc" -eq 2 ]; then
  pass "initial candidate bound is enforced"
else
  flunk "exhausted bound returned $rc, expected 2"
fi

printf '{"issue":1}\n' >"$WORK/malformed.json"
rc=0
bash "$ADD" "$WORK/malformed.json" 2 3 >"$WORK/malformed.out" 2>"$WORK/malformed.err" || rc=$?
if [ "$rc" -eq 2 ]; then
  pass "malformed exclusion state is refused"
else
  flunk "malformed state returned $rc, expected 2"
fi

printf '[1,1]\n' >"$WORK/duplicate.json"
rc=0
bash "$ADD" "$WORK/duplicate.json" 2 3 >"$WORK/duplicate.out" 2>"$WORK/duplicate.err" || rc=$?
if [ "$rc" -eq 2 ]; then
  pass "duplicate exclusion state is refused"
else
  flunk "duplicate state returned $rc, expected 2"
fi

printf '[]\n' >"$WORK/invalid-argument.json"
rc=0
bash "$ADD" "$WORK/invalid-argument.json" 01 3 >"$WORK/issue.out" 2>"$WORK/issue.err" || rc=$?
if [ "$rc" -eq 2 ]; then
  pass "non-canonical issue number is refused"
else
  flunk "non-canonical issue returned $rc, expected 2"
fi

rc=0
bash "$ADD" "$WORK/invalid-argument.json" 1 0 >"$WORK/limit.out" 2>"$WORK/limit.err" || rc=$?
if [ "$rc" -eq 2 ]; then
  pass "invalid bound is refused"
else
  flunk "invalid bound returned $rc, expected 2"
fi

if [ "$checks" -ne 13 ]; then
  echo "FAIL lane-progression: expected 13 checks, reached $checks" >&2
  exit 1
fi
if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "ok   lane-progression: proof-of-work checks=$checks"
