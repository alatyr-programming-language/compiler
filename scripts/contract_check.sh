#!/usr/bin/env bash
# Validate the checked-in language/tooling contracts without compiling or rewriting an oracle.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

fail=0
need_file() {
  local path="$1"
  if [ ! -f "$path" ]; then
    echo "FAIL contract: missing $path" >&2
    fail=1
  fi
}

need_text() {
  local path="$1" needle="$2"
  if [ ! -f "$path" ] || ! grep -qF "$needle" "$path"; then
    echo "FAIL contract: $path does not state: $needle" >&2
    fail=1
  fi
}

for path in \
  docs/target-support.md docs/target-support.tsv docs/conformance.md docs/lowering.md \
  docs/package-tooling.md docs/stdlib.md docs/safety.md docs/release.md \
  src/lower/ctfold.al src/lower_layout.al src/regalloc.al src/iface.al \
  lib/std/argv.al lib/std/term.al scripts/release_manifest.sh scripts/release_manifest_test.sh; do
  need_file "$path"
done

need_text docs/target-support.md 'Linux `x86_64` / GNU / ELF'
need_text docs/target-support.md 'Linux `aarch64` / GNU / ELF'
need_text docs/target-support.md 'Linux `riscv64` / GNU / ELF'
need_text docs/target-support.md "unsupported"
need_text docs/conformance.md "Every tracked"
need_text docs/conformance.md "Fail-closed rules"
need_text docs/lowering.md "regalloc"
need_text docs/package-tooling.md "Deterministic build plan"
need_text docs/package-tooling.md "shared_lib"
need_text docs/stdlib.md "std::argv"
need_text docs/stdlib.md "std::term"
need_text docs/stdlib.md 'There is no `std::net` module'
need_text docs/safety.md "@owning"
need_text docs/safety.md "unchecked"
need_text docs/release.md "release_manifest.sh"
need_text lib/std/argv.al "read_cmdline"
need_text lib/std/term.al "IoError"

if [ ! -x scripts/release_manifest.sh ] || [ ! -x scripts/release_manifest_test.sh ]; then
  echo "FAIL contract: release scripts must be executable" >&2
  fail=1
fi

python3 - "$ROOT/docs/target-support.tsv" <<'PY'
import csv
import sys

path = sys.argv[1]
required = {
    "linux-x86_64",
    "linux-aarch64",
    "linux-riscv64",
    "wasm",
    "linux-i386",
    "linux-aarch32",
    "linux-riscv32",
}
allowed = {"yes", "no", "unsupported", "check-only", "test-only"}
with open(path, newline="", encoding="utf-8") as stream:
    rows = list(csv.reader(stream, delimiter="\t"))
if not rows or rows[0] != [
    "surface", "arch", "os", "env", "container", "build", "check", "emit", "assemble", "run", "boundary"
]:
    raise SystemExit("FAIL contract: target-support.tsv header changed")
seen = set()
for line, row in enumerate(rows[1:], 2):
    if len(row) != 11 or not row[0]:
        raise SystemExit(f"FAIL contract: malformed target row {line}")
    seen.add(row[0])
    if any(value not in allowed for value in row[5:10]):
        raise SystemExit(f"FAIL contract: unknown target status on row {line}")
if not required.issubset(seen):
    raise SystemExit("FAIL contract: target matrix lost a required surface")
print(f"ok   contract target matrix: {len(rows) - 1} rows")
PY
matrix_rc=$?
[ "$matrix_rc" = 0 ] || fail=1

oracle_base=HEAD
if git rev-parse --verify origin/main >/dev/null 2>&1; then oracle_base=origin/main; fi
for oracle in scripts/corpus.manifest scripts/idiom.baseline scripts/needle.baseline; do
  if ! git diff --quiet "$oracle_base" -- "$oracle"; then
    echo "FAIL contract: protected oracle modified: $oracle" >&2
    fail=1
  fi
done

if [ "$fail" = 0 ]; then
  echo "CONTRACT CHECK: PASS"
else
  echo "CONTRACT CHECK: FAIL" >&2
fi
exit "$fail"
