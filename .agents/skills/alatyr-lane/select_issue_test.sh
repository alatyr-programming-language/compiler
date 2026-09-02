#!/usr/bin/env bash
# Repository-controlled non-vacuous self-test for select_issue.sh.
#
# The positive cases prove that a bounded Refs relation excludes an otherwise eligible issue even
# without its in-progress label, and that the GitHub closing relation path remains supported.
#
# The availability cases prove that contributor-written PR text cannot disable the fallback: a PR
# with a missing, malformed, multiple, mixed, or disagreeing relation is reported by number and
# excludes only the issues it legibly names, a hold-labelled PR is excluded from the fallback, and
# a fork or oracle PR is reported but still excludes its issue.
#
# The refusal cases prove that unreliable selector input still fails closed, that every refusal
# names the offending PR or issue, and that a refusal (exit 2) is distinguishable from an empty
# queue (exit 3) by exit status rather than by an empty stdout.
set -u

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SELECTOR="$ROOT/.agents/skills/alatyr-lane/select_issue.sh"
SKILL="$ROOT/.agents/skills/alatyr-lane/SKILL.md"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail=0
checks=0
pass()  { checks=$((checks + 1)); echo "ok   lane-selection: $*"; }
flunk() { checks=$((checks + 1)); fail=1; echo "FAIL lane-selection: $*"; }

# run_case NAME EXPECTED_RC PRS_JSON ISSUES_JSON EXPECTED_STDOUT EXPECTED_STDERR
# Use - for an unchecked stdout or stderr expectation.
run_case() {
  local name="$1" want_rc="$2" prs="$3" issues="$4" want_out="$5" want_err="$6"
  local out="$WORK/$name.out" err="$WORK/$name.err" rc=0
  bash "$SELECTOR" alatyr-programming-language/compiler nizovtsevnv \
    "$prs" "$issues" >"$out" 2>"$err" || rc=$?
  if [ "$rc" -ne "$want_rc" ]; then
    flunk "$name: exit $rc, expected $want_rc (stderr: $(tr '\n' '|' <"$err"))"
    return
  fi
  if [ "$want_out" != - ] && [ "$(cat "$out")" != "$want_out" ]; then
    flunk "$name: stdout $(cat "$out"), expected $want_out"
    return
  fi
  if [ "$want_err" != - ] && ! grep -Fq "$want_err" "$err"; then
    flunk "$name: stderr lacks '$want_err' (got: $(tr '\n' '|' <"$err"))"
    return
  fi
  pass "$name"
}

json() { cat > "$WORK/$1"; printf '%s' "$WORK/$1"; }

pr() {
  # pr NUMBER BODY LABELS FILES CHANGED CLOSING EXTRA_ONELINE_JSON_FIELDS
  printf '{"number":%s,"state":"OPEN","body":%s,"isCrossRepository":false,' "$1" "$2"
  printf '"headRepository":{"nameWithOwner":"alatyr-programming-language/compiler"},'
  printf '"labels":%s,"files":%s,"changedFiles":%s,"closingIssuesReferences":%s}' "$3" "$4" "$5" "$6"
}

issue() {
  # issue NUMBER CREATED_SUFFIX LABELS
  printf '{"number":%s,"state":"OPEN","title":"candidate","createdAt":"2026-09-01T01:08:%sZ",' "$1" "$2"
  printf '"author":{"login":"nizovtsevnv"},"labels":%s}' "$3"
}

# ---------------------------------------------------------------- wiring checks

if [ -f "$SELECTOR" ] && grep -Fq 'select_issue.sh' "$SKILL" &&
   grep -Fq 'closingIssuesReferences,isCrossRepository,headRepository,labels,files,changedFiles' "$SKILL"; then
  pass "skill wires the data-only selector and complete PR metadata"
else
  flunk "skill does not wire the data-only selector and complete PR metadata"
fi

if grep -Fq 'SELECT_RC=$?' "$SKILL" && grep -Eq '^[[:space:]]*3\)' "$SKILL" &&
   grep -Fq 'select_issue_test.sh' "$SKILL"; then
  pass "skill branches on the selector exit status and runs this self-test"
else
  flunk "skill does not branch on the selector exit status"
fi

# ------------------------------------------------------------- positive selection

ISSUES_338_339="$(json issues-338-339.json <<JSON
[$(issue 338 48 '[]'),$(issue 339 49 '[]')]
JSON
)"

PRS_REFS="$(json prs-refs.json <<JSON
[$(pr 337 '"Refs #338"' '[]' '[]' 0 '[]')]
JSON
)"
run_case refs-relation-excludes-its-issue 0 "$PRS_REFS" "$ISSUES_338_339" 339 -

ISSUES_CLOSING="$(json issues-closing.json <<JSON
[$(issue 340 48 '[]'),$(issue 341 49 '[]'),$(issue 342 50 '[]'),$(issue 343 51 '[]'),$(issue 344 52 '[]')]
JSON
)"
PRS_CLOSING="$(json prs-closing.json <<JSON
[$(pr 350 '"Closes #340"' '[]' '[]' 0 '[{"number":340}]'),
 $(pr 351 '"Fixes #341"' '[]' '[]' 0 '[{"number":341}]'),
 $(pr 352 '"Resolves #342"' '[]' '[]' 0 '[{"number":342}]'),
 $(pr 353 '""' '[]' '[]' 0 '[{"number":343}]')]
JSON
)"
run_case closing-relations-exclude-their-issues 0 "$PRS_CLOSING" "$ISSUES_CLOSING" 344 -

# -------------------------------------------- availability: a bad PR body is diagnosed, not fatal

ISSUES_338="$(json issues-338.json <<JSON
[$(issue 338 48 '[]')]
JSON
)"

PRS_NO_RELATION="$(json prs-no-relation.json <<JSON
[$(pr 343 '"No linked issue"' '[]' '[]' 0 '[]')]
JSON
)"
run_case missing-relation-is-named-and-ranking-continues 0 \
  "$PRS_NO_RELATION" "$ISSUES_338" 338 \
  "PR #343 is not a conforming relation source: no issue relation; it excludes no issue"

ISSUES_338_339_340="$(json issues-338-339-340.json <<JSON
[$(issue 338 48 '[]'),$(issue 339 49 '[]'),$(issue 340 50 '[]')]
JSON
)"

PRS_BAD_LINE="$(json prs-bad-line.json <<JSON
[$(pr 345 '"Refs #338 and also #339"' '[]' '[]' 0 '[]')]
JSON
)"
run_case malformed-relation-line-excludes-every-issue-it-mentions 0 \
  "$PRS_BAD_LINE" "$ISSUES_338_339_340" 340 \
  "PR #345 is not a conforming relation source: malformed issue relation on body line 1; it excludes issue #338, #339 and ranking continues"

PRS_BAD_NUMBER="$(json prs-bad-number.json <<JSON
[$(pr 346 '"Please Refs #12x when landing"' '[]' '[]' 0 '[]')]
JSON
)"
run_case malformed-relation-number-is-named 0 \
  "$PRS_BAD_NUMBER" "$ISSUES_338" 338 \
  "PR #346 is not a conforming relation source: malformed issue relation number"

PRS_MULTIPLE="$(json prs-multiple.json <<JSON
[$(pr 344 '"Refs #338\nFixes #339"' '[]' '[]' 0 '[]')]
JSON
)"
run_case multiple-relations-exclude-both-named-issues 0 \
  "$PRS_MULTIPLE" "$ISSUES_338_339_340" 340 \
  "PR #344 is not a conforming relation source: multiple issue relations (issue #338, #339); it excludes issue #338, #339"

ISSUES_338_349="$(json issues-338-349.json <<JSON
[$(issue 338 48 '[]'),$(issue 349 49 '[]')]
JSON
)"
PRS_MIXED="$(json prs-mixed.json <<JSON
[$(pr 348 '"Refs #338"' '[]' '[]' 0 '[{"number":338}]')]
JSON
)"
run_case mixed-relation-is-named-and-still-excludes 0 \
  "$PRS_MIXED" "$ISSUES_338_349" 349 \
  "PR #348 is not a conforming relation source: bounded relation to issue #338 mixed with a closing reference to issue #338"

ISSUES_340_341_350="$(json issues-340-341-350.json <<JSON
[$(issue 340 48 '[]'),$(issue 341 49 '[]'),$(issue 350 50 '[]')]
JSON
)"
PRS_DISAGREE="$(json prs-disagree.json <<JSON
[$(pr 352 '"Fixes #340"' '[]' '[]' 0 '[{"number":341}]')]
JSON
)"
run_case disagreeing-relation-excludes-both-named-issues 0 \
  "$PRS_DISAGREE" "$ISSUES_340_341_350" 350 \
  "PR #352 is not a conforming relation source: body relation to issue #340 disagrees with closingIssuesReferences (issue #341)"

PRS_FORK="$(json prs-fork.json <<'JSON'
[{"number":346,"state":"OPEN","body":"Refs #338","isCrossRepository":true,
  "headRepository":{"nameWithOwner":"untrusted/fork"},"labels":[],"files":[],
  "changedFiles":0,"closingIssuesReferences":[]}]
JSON
)"
run_case fork-pr-is-reported-and-still-excludes-its-issue 0 \
  "$PRS_FORK" "$ISSUES_338_339" 339 \
  "PR #346 head is outside alatyr-programming-language/compiler"

PRS_ORACLE="$(json prs-oracle.json <<JSON
[$(pr 347 '"Refs #338"' '[]' '[{"path":"scripts/corpus.manifest"}]' 1 '[]')]
JSON
)"
run_case oracle-pr-is-reported-and-still-excludes-its-issue 0 \
  "$PRS_ORACLE" "$ISSUES_338_339" 339 \
  "PR #347 touches an oracle"

PRS_HOLD="$(json prs-hold.json <<JSON
[$(pr 354 '"Refs #338"' '[{"name":"hold"}]' '[]' 0 '[]')]
JSON
)"
run_case hold-pr-is-excluded-from-the-fallback 0 \
  "$PRS_HOLD" "$ISSUES_338" 338 \
  "PR #354 carries hold: excluded from the fallback, so it no longer excludes issue #338"

# ------------------------------------------------- refusals: unreliable input, each one named

PRS_NO_CHANGED_FILES="$(json prs-no-changed-files.json <<'JSON'
[{"number":349,"state":"OPEN","body":"Refs #338","isCrossRepository":false,
  "headRepository":{"nameWithOwner":"alatyr-programming-language/compiler"},
  "labels":[],"files":[],"closingIssuesReferences":[]}]
JSON
)"
run_case refusal-names-pr-with-missing-changed-files 2 \
  "$PRS_NO_CHANGED_FILES" "$ISSUES_338" "" \
  "PR #349 changedFiles is missing or malformed"

PRS_FILE_COUNT="$(json prs-file-count.json <<JSON
[$(pr 355 '"Refs #338"' '[]' '[]' 1 '[]')]
JSON
)"
run_case refusal-names-pr-with-truncated-file-list 2 \
  "$PRS_FILE_COUNT" "$ISSUES_338" "" \
  "PR #355 file metadata is incomplete: 0 of 1 paths returned"

PRS_BAD_CLOSING="$(json prs-bad-closing.json <<JSON
[$(pr 356 '"Refs #338"' '[]' '[]' 0 '"not-an-array"')]
JSON
)"
run_case refusal-names-pr-with-malformed-closing-references 2 \
  "$PRS_BAD_CLOSING" "$ISSUES_338" "" \
  "PR #356 closingIssuesReferences is missing or malformed"

ISSUES_BAD_PRIORITY="$(json issues-bad-priority.json <<JSON
[$(issue 338 48 '[{"name":"priority-1"},{"name":"priority-2"}]')]
JSON
)"
run_case refusal-names-issue-with-ambiguous-priority 2 \
  "$PRS_NO_RELATION" "$ISSUES_BAD_PRIORITY" "" \
  "issue #338 carries ambiguous or malformed priority labels"

PRS_NOT_ARRAY="$(json prs-not-array.json <<'JSON'
{"number":357}
JSON
)"
run_case refusal-on-pr-input-that-is-not-an-array 2 \
  "$PRS_NOT_ARRAY" "$ISSUES_338" "" \
  "open PR metadata must be one JSON array"

# ------------------------------------ empty queue: exit 3, distinct from the refusals above

ISSUES_CLAIMED="$(json issues-claimed.json <<JSON
[$(issue 338 48 '[{"name":"in-progress"}]')]
JSON
)"
run_case empty-queue-when-every-issue-is-claimed 3 \
  "$PRS_NO_RELATION" "$ISSUES_CLAIMED" "" \
  "no eligible issue authored by nizovtsevnv"

run_case empty-queue-when-every-issue-has-a-conforming-pr 3 \
  "$PRS_REFS" "$ISSUES_338" "" \
  "no eligible issue authored by nizovtsevnv"

if [ "$checks" -ne 20 ]; then
  echo "FAIL lane-selection: expected 20 checks, reached $checks" >&2
  exit 1
fi
if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "ok   lane-selection: proof-of-work checks=$checks"
