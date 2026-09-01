#!/usr/bin/env bash
set -eu
set -o pipefail

: "${ALATYR:?ALATYR must name the compiler under test}"
mode="${1:-fixed}"
case "$mode" in
  fixed|parent) ;;
  *) echo "usage: $0 [fixed|parent]" >&2; exit 2 ;;
esac

work="$(mktemp -d "${TMPDIR:-/tmp}/alatyr-issue344.XXXXXX")"
trap 'rm -rf "$work"' EXIT

spaces_483="$(printf '%*s' 483 '')"
spaces_484="$(printf '%*s' 484 '')"

write_fixture() {
  local path="$1" gap="$2"
  {
    printf '%s\n' \
      'main := fn() -> u64 {' \
      '  s := "ABCDEFGH"' \
      '  addr := unchecked bitcast(usize, s.ptr)'
    printf '  p := unchecked%sbitcast(ptr(u8), addr)\n' "$gap"
    printf '%s\n' \
      '  if deref(p) != 65 { return 1 }' \
      '  return 42' \
      '}'
  } > "$path"
}

control="$work/issue344_control.al"
boundary="$work/issue344_boundary.al"
write_fixture "$control" "$spaces_483"
write_fixture "$boundary" "$spaces_484"

run_case() {
  local name="$1" source="$2" want="$3" out="$work/$1.out" got
  "$ALATYR" -o "$out" "$source" >/dev/null 2>&1
  if "$out" >/dev/null 2>&1; then
    got=0
  else
    got=$?
  fi
  if [ "$got" != "$want" ]; then
    echo "FAIL $name: got $got want $want" >&2
    exit 1
  fi
  echo "ok   $name: $got"
}

if [ "$mode" = parent ]; then
  run_case issue344_control_483 "$control" 42
  run_case issue344_boundary_484 "$boundary" 1
  "$ALATYR" "$boundary" > "$work/boundary.gas" 2>/dev/null
  grep -qF 'movq (%rax), %rax' "$work/boundary.gas" || {
    echo 'FAIL issue344_boundary_484: old word-sized load was not observed' >&2
    exit 1
  }
  echo 'ok   issue344_boundary_484: parent emitted word-sized load'
else
  run_case issue344_control_483 "$control" 42
  run_case issue344_boundary_484 "$boundary" 42
  "$ALATYR" "$boundary" > "$work/boundary.gas" 2>/dev/null
  grep -qF 'movzbq (%rax), %rax' "$work/boundary.gas" || {
    echo 'FAIL issue344_boundary_484: byte-sized load is missing' >&2
    exit 1
  }
  echo 'ok   issue344_boundary_484: emitted byte-sized load'
fi
