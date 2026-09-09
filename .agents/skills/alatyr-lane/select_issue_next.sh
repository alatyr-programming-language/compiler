#!/usr/bin/env bash
# Refresh same-account queue metadata and select one candidate using durable invocation-local state.
set -eu

if [ "$#" -ne 3 ]; then
  echo "usage: $0 REPOSITORY LOGIN STATE_DIRECTORY" >&2
  exit 2
fi

REPOSITORY="$1"
LOGIN="$2"
STATE_DIR="$3"
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SELECTOR="$ROOT/.agents/skills/alatyr-lane/select_issue.sh"
EXCLUSIONS="$STATE_DIR/exclusions.json"
BOUND="$STATE_DIR/initial-issue-bound"

if [ -z "$REPOSITORY" ] || [ -z "$LOGIN" ] || [ ! -d "$STATE_DIR" ]; then
  echo "refusing queue refresh: invalid input" >&2
  exit 2
fi
if [ ! -e "$EXCLUSIONS" ]; then
  printf '[]\n' >"$EXCLUSIONS"
fi
if [ -e "$BOUND" ]; then
  bound_value="$(cat "$BOUND")"
  case "$bound_value" in
    ''|*[!0-9]*)
      echo "refusing queue refresh: initial issue bound is malformed" >&2
      exit 2
      ;;
  esac
fi

REFRESH="$(mktemp -d "$STATE_DIR/.queue-refresh.XXXXXX")"
trap 'rm -rf "$REFRESH"' EXIT

if ! gh pr list -R "$REPOSITORY" --state open --limit 1000 \
  --json number,state,body,closingIssuesReferences,isCrossRepository,headRepository,labels,files,changedFiles \
  >"$REFRESH/prs.json"; then
  echo "refusing queue refresh: open PR metadata is unavailable" >&2
  exit 2
fi
if ! gh issue list -R "$REPOSITORY" --state open --author "$LOGIN" --limit 1000 \
  --json number,state,title,createdAt,author,labels >"$REFRESH/issues.json"; then
  echo "refusing queue refresh: issue metadata is unavailable" >&2
  exit 2
fi

rc=0
issue="$(
  bash "$SELECTOR" "$REPOSITORY" "$LOGIN" \
    "$REFRESH/prs.json" "$REFRESH/issues.json" "$EXCLUSIONS"
)" || rc=$?
case "$rc" in
  0|3) ;;
  *) exit "$rc" ;;
esac

if [ ! -e "$BOUND" ]; then
  count="$(jq -er 'if type == "array" then length else error("not an array") end' \
    "$REFRESH/issues.json")" || {
    echo "refusing queue refresh: initial issue metadata is malformed" >&2
    exit 2
  }
  NEXT_BOUND="$(mktemp "$STATE_DIR/.initial-issue-bound.XXXXXX")"
  printf '%s\n' "$count" >"$NEXT_BOUND"
  mv -- "$NEXT_BOUND" "$BOUND"
fi

if [ "$rc" -eq 3 ]; then
  exit 3
fi
printf '%s\n' "$issue"
