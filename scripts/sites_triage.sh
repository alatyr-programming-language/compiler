#!/usr/bin/env bash
# sites_triage.sh — which fired trap sites are DEFECTS and which are the thing under test.
#
# WHY THIS EXISTS. `scripts/xbackend_diff.sh --sites <cc>` prints, for every corpus path whose backends
# disagree, the comment the emitter wrote at the place it gave up:
#
#   aarch64  test/when_guard.al  SITE  undefined/builtin callee  when_guard__main
#
# That is a count of REASONS, not a list of defects — the fault §16 of docs/ir-slice-3.md records.
# `when_guard.al` traps on `answer`, and `zst_and_empty_ctor.al` traps on `size`: both call a callee the
# fixture deliberately leaves undefined, so "closing" that trap would delete the thing being tested. A cut
# taken from the reason table without this filter is a plan to delete tests.
#
# The declaration of what a program must do already exists, in the file the gate runs: `scripts/e2e.sh`'s
# registration form. `run <name> <want>` says every backend must run it and answer `<want>`;
# `run_a64 <name> <want>` says that of aarch64 alone; `build_reject_has <name> "<needle>"` says the
# program must be REFUSED at build; `run_x86_trap <name> 132` says a trap is the expected answer. This
# script joins the two, per (backend, path), and reports how many rows survive as genuine gaps.
#
# It REPORTS. It gates nothing and writes no oracle — the expected answers stay in e2e.sh, the observed
# ones in scripts/corpus.manifest, and this reads both without touching either.
#
#   scripts/sites_triage.sh <ABSOLUTE compiler path> [<manifest>] [--reason RE] [--all]
#
#   --reason RE   the reason substring to triage (default: undefined/builtin callee, the family §16 names
#                 as the largest block on main = 9d04a4b)
#   --all         triage every reason, not just --reason
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

CC=""
MANIFEST="scripts/corpus.manifest"
## a REGEX, not a substring: the backends spell this family two different ways (see below)
REASON="undefined/builtin (callee|fn)"
ALL=0
SITES=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --reason) [ "$#" -ge 2 ] || { echo "sites_triage: --reason needs a substring" >&2; exit 2; }
              REASON="$2"; shift 2 ;;
    --all)    ALL=1; shift ;;
    --sites)  [ "$#" -ge 2 ] || { echo "sites_triage: --sites needs a file" >&2; exit 2; }
              SITES="$2"; shift 2 ;;
    *)        ## the first positional is the compiler, the second the manifest
              if [ -z "$CC" ]; then CC="$1"; else MANIFEST="$1"; fi; shift ;;
  esac
done

if [ -z "$SITES" ]; then
  case "$CC" in /*) ;; *) echo "sites_triage: needs an ABSOLUTE compiler path (or --sites FILE)" >&2; exit 2 ;; esac
  SITES="$(mktemp)"; trap 'rm -f "$SITES" "${OUT:-}"' EXIT
  echo "sites_triage: taking sites with scripts/xbackend_diff.sh --sites (this walks the corpus)…" >&2
  bash scripts/xbackend_diff.sh --sites "$CC" "$MANIFEST" > "$SITES" 2>/dev/null
fi
OUT="$(mktemp)"; trap 'rm -f "${SITES:-}" "$OUT"' EXIT

E2E="scripts/e2e.sh"
[ -f "$E2E" ]   || { echo "sites_triage: $E2E not found" >&2; exit 1; }
[ -f "$SITES" ] || { echo "sites_triage: no sites input" >&2; exit 1; }

## ── the registration table, read out of e2e.sh ────────────────────────────────────────────────
## One line per fixture: name, then the forms that name it. The forms are matched at the start of a
## line only — `run` appears inside prose and inside other identifiers, and a needle quoted in a
## comment is not a registration.
awk -F'\t' -v e2e="$E2E" -v reason_re="$REASON" -v all="$ALL" '
BEGIN {
  ## backend -> the registration form that speaks for THAT backend
  forms["x86_64"]   = "run_x86 run_x86_out"
  forms["aarch64"] = "run_a64 run_a64_out"
  forms["riscv64"] = "run_rv64 run_rv64_out"
  forms["wasm"]    = "run_wat run_wat_out"
  while ((getline l < e2e) > 0) {
    if (l !~ /^(run|run_x86|run_a64|run_rv64|run_wat|run_ffi|run_x86_out|run_a64_out|run_rv64_out|run_wat_out|run_x86_trap|run_a64_trap|run_rv64_trap|run_wat_trap|build_reject|build_reject_has|root_package_test)[ \t]/) continue
    n = split(l, f, /[ \t]+/)
    if (n < 2) continue
    form = f[1]; name = f[2]
    if (form == "build_reject" || form == "build_reject_has") rej[name] = rej[name] " build_reject"
    else if (form ~ /_trap$/)                          trap[name] = trap[name] " " form
    else if (form == "root_package_test")            pkg[name] = 1
    else if (form == "run" || form == "run_ffi")     allrun[name] = 1
    else                                                per[name] = per[name] " " form
  }
  close(e2e)
}
{
  b = $1; p = $2; kind = $3; why = $4
  if (kind != "SITE" && kind != "ASSEMBLE") next
  w = why
  gsub(/^;+[ \t]*/, "", w); gsub(/[ \t]*\;+$/, "", w)      # wasm writes (; … ;)
  ## x86/aarch64/riscv64 write "undefined/builtin callee"; wasm writes "call to undefined/builtin fn X".
  ## A single substring silently drops a whole backend — the fault §16 records, one level down. Matched as
  ## a REGEX so both spellings are in scope, and the per-backend counts below make a backend that drops
  ## out visible rather than merely absent. (No apostrophes in this block: it lives in single quotes.)
  if (!all && match(tolower(w), reason_re) == 0) next
  ## the callee named in the reason, when the reason names one
  cal = "-"
  if (match(w, /builtin fn [A-Za-z0-9_]+/)) cal = substr(w, RSTART + 11, RLENGTH - 11)
  base = p; sub(/^.*\//, "", base); sub(/\.al$/, "", base)
  rows[p SUBSEP b] = rows[p SUBSEP b] " " cal
  seen[p SUBSEP b] = 1
  if (kind == "ASSEMBLE") asm[p SUBSEP b] = 1
}
END {
  for (k in seen) {
    split(k, a, SUBSEP); p = a[1]; b = a[2]
    v = ""
    ## the lookup key is the fixture NAME, as e2e.sh registers it — not the path. A package fixture
    ## lives at test/package/<name>/package.al and is registered by <name>, so there the directory is
    ## the name; taking "package" would collide every package in the corpus onto one key.
    base = p; sub(/^.*\//, "", base); sub(/\.al$/, "", base)
    if (base == "package") { base = p; sub(/\/package\.al$/, "", base); sub(/^.*\//, "", base) }
    if (rej[base] != "")                          v = "EXPECTED-REFUSE"   # the program must not build at all
    else if (trap[base] ~ ("(^| )" b "_trap"))  v = "EXPECTED-TRAP"
    else if (pkg[base])                          v = "declared-package-build"
    else if (allrun[base])                       v = "GAP:declared-run"
    else if (per[base] ~ ("(^| )" forms[b]))   v = "GAP:declared-per-backend"
    else if (per[base] != "")                   v = "undeclared-here"     # another backend is asserted, not this one
    else                                        v = "UNREGISTERED"
    if (asm[p SUBSEP b]) v = v "+ASSEMBLE"
    n = split(rows[p SUBSEP b], u, " ")
    cs = ""; delete s
    for (i = 1; i <= n; i++) if (u[i] != "-" && !s[u[i]]++) cs = cs " " u[i]
    printf "ROW\t%-24s %-46s%s\n", v, p, cs
    cnt[v]++; tot++; bc[b]++
    if (v ~ /^GAP/) { for (i = 1; i <= n; i++) if (u[i] != "-" && u[i] != "") gapcal[u[i]]++ }
    if (!pathseen[p]++) { npaths++ }
  }
  printf "SUM\t%d rows triaged, %d distinct paths\n", tot, npaths
  ## per backend: a family whose rows come from only some backends is a different task than one that is
  ## spread over all of them, and a backend missing from the list means the matcher dropped it
  for (b in bc) printf "SUM\t%6d  backend %s\n", bc[b], b
  for (v in cnt) printf "SUM\t%6d  %s\n", cnt[v], v
  ## the actionable list: which callee the declared-run gaps are actually stuck on, most first
  for (c in gapcal) printf "CAL\t%6d  %s\n", gapcal[c], c
}
' "$SITES" > "$OUT"

echo "── per (backend, path), verdict from scripts/e2e.sh's own registration ──"
grep '^ROW' "$OUT" | cut -c5- | sort
echo
echo "── summary ──"
grep '^SUM' "$OUT" | cut -c5-
echo
echo "── callees the declared-run gaps are stuck on (most first) ──"
grep '^CAL' "$OUT" | cut -c5- | sort -rn | head -20
