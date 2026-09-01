#!/usr/bin/env bash
# Repository-controlled non-vacuous self-test for select_issue.sh.
#
# The positive cases prove that a bounded Refs relation excludes an otherwise eligible issue even
# without its in-progress label, and that the GitHub closing relation path remains supported. The
# refusal cases prove that untrusted PR metadata cannot silently enter the worker queue.
set -u

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SELECTOR="$ROOT/.agents/skills/alatyr-lane/select_issue.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail=0
checks=0
pass()  { checks=$((checks + 1)); echo "ok   lane-selection: $*"; }
flunk() { checks=$((checks + 1)); fail=1; echo "FAIL lane-selection: $*"; }

run_selector() {
  local pr_file="$1" issue_file="$2" out_file="$3"
  bash "$SELECTOR" alatyr-programming-language/compiler nizovtsevnv "$pr_file" "$issue_file" >"$out_file" 2>"$out_file.err"
}

SKILL="$ROOT/.agents/skills/alatyr-lane/SKILL.md"
if [ -f "$SELECTOR" ] && grep -Fq 'select_issue.sh' "$SKILL" &&
   grep -Fq 'closingIssuesReferences,isCrossRepository,headRepository,labels,files,changedFiles' "$SKILL"; then
  pass "skill wires the data-only selector and complete PR metadata"
else
  flunk "skill does not wire the data-only selector and complete PR metadata"
fi

cat > "$WORK/issues-positive.json" <<'JSON'
[
  {"number":338,"state":"OPEN","title":"bounded relation","createdAt":"2026-09-01T01:08:48Z","author":{"login":"nizovtsevnv"},"labels":[]},
  {"number":339,"state":"OPEN","title":"next eligible issue","createdAt":"2026-09-01T01:08:49Z","author":{"login":"nizovtsevnv"},"labels":[]}
]
JSON
cat > "$WORK/prs-refs.json" <<'JSON'
[
  {"number":337,"state":"OPEN","body":"Refs #338","isCrossRepository":false,"headRepository":{"nameWithOwner":"alatyr-programming-language/compiler"},"labels":[],"files":[],"changedFiles":0,"closingIssuesReferences":[]}
]
JSON
if run_selector "$WORK/prs-refs.json" "$WORK/issues-positive.json" "$WORK/refs.out" && [ "$(cat "$WORK/refs.out")" = 339 ]; then
  pass "Refs excludes issue 338 without an in-progress label and selects 339"
else
  flunk "Refs exclusion did not select issue 339"
fi

cat > "$WORK/issues-closing.json" <<'JSON'
[
  {"number":340,"state":"OPEN","title":"closing relation","createdAt":"2026-09-01T01:08:48Z","author":{"login":"nizovtsevnv"},"labels":[]},
  {"number":341,"state":"OPEN","title":"closing relation","createdAt":"2026-09-01T01:08:49Z","author":{"login":"nizovtsevnv"},"labels":[]},
  {"number":342,"state":"OPEN","title":"closing relation","createdAt":"2026-09-01T01:08:50Z","author":{"login":"nizovtsevnv"},"labels":[]},
  {"number":343,"state":"OPEN","title":"api relation","createdAt":"2026-09-01T01:08:51Z","author":{"login":"nizovtsevnv"},"labels":[]},
  {"number":344,"state":"OPEN","title":"next eligible issue","createdAt":"2026-09-01T01:08:52Z","author":{"login":"nizovtsevnv"},"labels":[]}
]
JSON
cat > "$WORK/prs-closing.json" <<'JSON'
[
  {"number":350,"state":"OPEN","body":"Closes #340","isCrossRepository":false,"headRepository":{"nameWithOwner":"alatyr-programming-language/compiler"},"labels":[],"files":[],"changedFiles":0,"closingIssuesReferences":[{"number":340}]},
  {"number":351,"state":"OPEN","body":"Fixes #341","isCrossRepository":false,"headRepository":{"nameWithOwner":"alatyr-programming-language/compiler"},"labels":[],"files":[],"changedFiles":0,"closingIssuesReferences":[{"number":341}]},
  {"number":352,"state":"OPEN","body":"Resolves #342","isCrossRepository":false,"headRepository":{"nameWithOwner":"alatyr-programming-language/compiler"},"labels":[],"files":[],"changedFiles":0,"closingIssuesReferences":[{"number":342}]},
  {"number":353,"state":"OPEN","body":"","isCrossRepository":false,"headRepository":{"nameWithOwner":"alatyr-programming-language/compiler"},"labels":[],"files":[],"changedFiles":0,"closingIssuesReferences":[{"number":343}]}
]
JSON
if run_selector "$WORK/prs-closing.json" "$WORK/issues-closing.json" "$WORK/closing.out" && [ "$(cat "$WORK/closing.out")" = 344 ]; then
  pass "Closes, Fixes, Resolves, and API-only closing relations exclude issues 340-343"
else
  flunk "closing relations did not select issue 344"
fi

expect_refusal() {
  local name="$1" pr_file="$2" issue_file="$3" out_file="$WORK/$name.out"
  if run_selector "$pr_file" "$issue_file" "$out_file"; then
    flunk "$name was accepted"
  else
    pass "$name fails closed"
  fi
}

cat > "$WORK/issues-refusal.json" <<'JSON'
[
  {"number":338,"state":"OPEN","title":"candidate","createdAt":"2026-09-01T01:08:48Z","author":{"login":"nizovtsevnv"},"labels":[]}
]
JSON

cat > "$WORK/pr-missing.json" <<'JSON'
[
  {"number":343,"state":"OPEN","body":"No linked issue","isCrossRepository":false,"headRepository":{"nameWithOwner":"alatyr-programming-language/compiler"},"labels":[],"files":[],"changedFiles":0,"closingIssuesReferences":[]}
]
JSON
expect_refusal missing-relation "$WORK/pr-missing.json" "$WORK/issues-refusal.json"

cat > "$WORK/pr-incomplete.json" <<'JSON'
[
  {"number":349,"state":"OPEN","body":"Refs #338","isCrossRepository":false,"headRepository":{"nameWithOwner":"alatyr-programming-language/compiler"},"labels":[],"files":[],"closingIssuesReferences":[]}
]
JSON
expect_refusal incomplete-file-metadata "$WORK/pr-incomplete.json" "$WORK/issues-refusal.json"

cat > "$WORK/pr-multiple.json" <<'JSON'
[
  {"number":344,"state":"OPEN","body":"Refs #338\nFixes #339","isCrossRepository":false,"headRepository":{"nameWithOwner":"alatyr-programming-language/compiler"},"labels":[],"files":[],"changedFiles":0,"closingIssuesReferences":[]}
]
JSON
expect_refusal multiple-relations "$WORK/pr-multiple.json" "$WORK/issues-refusal.json"

cat > "$WORK/pr-malformed.json" <<'JSON'
[
  {"number":345,"state":"OPEN","body":"Refs #not-a-number","isCrossRepository":false,"headRepository":{"nameWithOwner":"alatyr-programming-language/compiler"},"labels":[],"files":[],"changedFiles":0,"closingIssuesReferences":[]}
]
JSON
expect_refusal malformed-relation "$WORK/pr-malformed.json" "$WORK/issues-refusal.json"

cat > "$WORK/pr-fork.json" <<'JSON'
[
  {"number":346,"state":"OPEN","body":"Refs #338","isCrossRepository":true,"headRepository":{"nameWithOwner":"untrusted/fork"},"labels":[],"files":[],"changedFiles":0,"closingIssuesReferences":[]}
]
JSON
expect_refusal fork-pr "$WORK/pr-fork.json" "$WORK/issues-refusal.json"

cat > "$WORK/pr-oracle.json" <<'JSON'
[
  {"number":347,"state":"OPEN","body":"Refs #338","isCrossRepository":false,"headRepository":{"nameWithOwner":"alatyr-programming-language/compiler"},"labels":[],"files":[{"path":"scripts/corpus.manifest"}],"changedFiles":1,"closingIssuesReferences":[]}
]
JSON
expect_refusal oracle-pr "$WORK/pr-oracle.json" "$WORK/issues-refusal.json"

cat > "$WORK/pr-mixed.json" <<'JSON'
[
  {"number":348,"state":"OPEN","body":"Refs #338","isCrossRepository":false,"headRepository":{"nameWithOwner":"alatyr-programming-language/compiler"},"labels":[],"files":[],"changedFiles":0,"closingIssuesReferences":[{"number":338}]}
]
JSON
expect_refusal mixed-relation "$WORK/pr-mixed.json" "$WORK/issues-refusal.json"

if [ "$checks" -ne 10 ]; then
  echo "FAIL lane-selection: expected 10 checks, reached $checks" >&2
  exit 1
fi
if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "ok   lane-selection: proof-of-work checks=$checks"
