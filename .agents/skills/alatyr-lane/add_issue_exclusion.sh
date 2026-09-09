#!/usr/bin/env bash
# Atomically add one issue number to an invocation-local selector exclusion set.
set -eu

if [ "$#" -ne 3 ]; then
  echo "usage: $0 EXCLUSIONS_JSON ISSUE LIMIT" >&2
  exit 2
fi

EXCLUSIONS="$1"
ISSUE="$2"
LIMIT="$3"

case "$ISSUE" in
  ''|*[!0-9]*|0*)
    echo "refusing local exclusion: issue must be a positive integer" >&2
    exit 2
    ;;
esac
case "$LIMIT" in
  ''|*[!0-9]*|0*)
    echo "refusing local exclusion: limit must be a positive integer" >&2
    exit 2
    ;;
esac
if [ ! -r "$EXCLUSIONS" ]; then
  echo "refusing local exclusion: state is unreadable" >&2
  exit 2
fi
if ! jq -e '
  type == "array" and
  all(.[]; type == "number" and . > 0 and . == floor) and
  (length == (unique | length))
' "$EXCLUSIONS" >/dev/null; then
  echo "refusing local exclusion: state is malformed" >&2
  exit 2
fi
if jq -e --argjson issue "$ISSUE" 'index($issue) != null' "$EXCLUSIONS" >/dev/null; then
  echo "refusing local exclusion: issue #$ISSUE is already excluded" >&2
  exit 2
fi
COUNT="$(jq -r 'length' "$EXCLUSIONS")"
if [ "$COUNT" -ge "$LIMIT" ]; then
  echo "refusing local exclusion: initial candidate bound $LIMIT is exhausted" >&2
  exit 2
fi

STATE_DIR="$(dirname "$EXCLUSIONS")"
NEXT="$(mktemp "$STATE_DIR/.issue-exclusions.XXXXXX")"
trap 'rm -f "$NEXT"' EXIT
jq --argjson issue "$ISSUE" '. + [$issue]' "$EXCLUSIONS" >"$NEXT"
mv -- "$NEXT" "$EXCLUSIONS"
trap - EXIT
