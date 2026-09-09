#!/usr/bin/env bash
# Classify one committed range as a candidate for the inert-prose verification path.
#
# Exit status is the interface:
#   0  every changed object is a regular, non-executable file on the narrow prose allowlist
#   1  the ordinary full gate is required
#   2  the requested range is invalid
#
# A zero is only a candidate classification. The lane and integrator must still inspect every hunk
# and reject tool-consumed text, executable examples, or normative build/security/release behavior.
set -eu

if [ "$#" -ne 2 ]; then
  echo "usage: $0 BASE HEAD" >&2
  exit 2
fi

BASE="$(git rev-parse --verify "$1^{commit}" 2>/dev/null)" || {
  echo "invalid docs-only base commit" >&2
  exit 2
}
HEAD="$(git rev-parse --verify "$2^{commit}" 2>/dev/null)" || {
  echo "invalid docs-only head commit" >&2
  exit 2
}
if ! git merge-base --is-ancestor "$BASE" "$HEAD"; then
  echo "docs-only base is not an ancestor of head" >&2
  exit 2
fi

changed=0
eligible=1
reason=""
paths=()

while IFS= read -r -d '' meta; do
  if ! IFS= read -r -d '' path; then
    echo "malformed raw diff while classifying docs-only range" >&2
    exit 2
  fi
  changed=$((changed + 1))
  paths+=("$path")

  if [[ ! "$path" =~ ^[A-Za-z0-9._/-]+$ ]]; then
    eligible=0
    reason="a changed path contains unsupported bytes"
    continue
  fi

  read -r old_token new_mode old_oid new_oid status <<EOF
$meta
EOF
  old_mode="${old_token#:}"

  case "$status" in
    A)
      if [ "$old_mode" != 000000 ] || [ "$new_mode" != 100644 ]; then
        eligible=0
        reason="$path is not a new regular non-executable file"
      fi
      ;;
    M)
      if [ "$old_mode" != 100644 ] || [ "$new_mode" != 100644 ]; then
        eligible=0
        reason="$path changes object type or file mode"
      fi
      ;;
    *)
      eligible=0
      reason="$path has disallowed status $status"
      ;;
  esac

  case "$path" in
    README.md|CONTRIBUTING.md|CODE_OF_CONDUCT.md|docs/*.md|docs/*.txt)
      ;;
    *)
      eligible=0
      reason="$path is outside the inert-prose allowlist"
      ;;
  esac
done < <(git diff --raw -z --no-abbrev --no-renames "$BASE" "$HEAD" --)

if [ "$changed" -eq 0 ]; then
  echo "full gate required: range has no changes" >&2
  exit 1
fi
if [ "$eligible" -ne 1 ]; then
  echo "full gate required: $reason" >&2
  exit 1
fi

echo "docs-only candidate"
printf '%s\n' "${paths[@]}"
