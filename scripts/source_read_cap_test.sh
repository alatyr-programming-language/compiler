#!/usr/bin/env bash
# scripts/source_read_cap_test.sh — regression for the ambient source scanner's old 512 KiB cap.
#
# THE DEFECT THIS LOCKS. `cli::ambient_paths` used to read every user and injected-library source
# through a 524288-byte `read_proc` budget. A regular source larger than that budget was returned as
# a plausible, truncated `str`; the later driver read the file completely, but the ambient scan had
# already missed a qualified stdlib path in the tail. The compiler then rejected a valid program as
# if its ambient module had never existed. The source below deliberately places its real
# `std::io::print` use after the old boundary, so this exercises discovery rather than just the
# driver's independent full-file read.
#
# Run standalone after building Stage1:
#   nix develop -c bash scripts/source_read_cap_test.sh
# `ALATYR` overrides the compiler under test (default: `target/alatyr`).
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CC="${ALATYR:-$ROOT/target/alatyr}"

if [ ! -x "$CC" ]; then
  echo "FAIL source_read_cap: compiler not found at $CC" >&2
  echo "build it first with: seed/alatyr build package.al" >&2
  exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

SRC="$WORK/source_read_cap.al"
{
  ## Keep the filler as comments: it increases the source byte length without changing the program
  ## being compiled. 40000 lines put the real qualified call well beyond 512 KiB.
  awk 'BEGIN { for (i = 0; i < 40000; i++) printf "## source-read-cap filler %06d\n", i }'
  printf '%s\n' \
    'main := fn() -> u64 {' \
    '  n := std::io::print("source past cap\n")' \
    '  if n == 16 { return 42 }' \
    '  return 1' \
    '}'
} > "$SRC"

size="$(wc -c < "$SRC")"
offset="$(grep -aob 'std::io::print' "$SRC" | head -1 | cut -d: -f1)"
if [ "$size" -le 524288 ] || [ -z "$offset" ] || [ "$offset" -le 524288 ]; then
  echo "FAIL source_read_cap: fixture is not past the old boundary (size=$size offset=${offset:-missing})" >&2
  exit 1
fi
echo "ok   source_read_cap: fixture size=$size, std::io::print offset=$offset"

"$CC" -o "$WORK/source_read_cap.out" "$SRC" > "$WORK/compile.log" 2>&1
rc=$?
if [ "$rc" != 0 ]; then
  echo "FAIL source_read_cap: compile exited $rc" >&2
  sed -n '1,8p' "$WORK/compile.log" >&2
  exit 1
fi

"$WORK/source_read_cap.out" > "$WORK/run.out" 2> "$WORK/run.err"
rc=$?
if [ "$rc" != 42 ]; then
  echo "FAIL source_read_cap: compiled fixture exited $rc" >&2
  sed -n '1,8p' "$WORK/run.err" >&2
  exit 1
fi

if grep -q 'more than 524288 bytes' "$WORK/compile.log"; then
  echo "FAIL source_read_cap: source scan reported a truncation despite a successful build" >&2
  exit 1
fi

echo "ok   source_read_cap: a late ambient stdlib reference was scanned, compiled, and ran"
