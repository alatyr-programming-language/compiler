#!/usr/bin/env bash
# scripts/xbackend_report.sh — the CROSS-BACKEND consistency report over the corpus manifest (#683).
#
# Why this exists: `scripts/corpus.manifest` already OBSERVES all four backends on every tracked
# source, and it already HOLDS rows where a non-x86 backend runs to a different, non-trap exit code
# than x86_64 — the sweeps' own `SILENT MISCOMPILE` verdict. Nothing ever compared those four rows
# with each other. Each row is only ever compared with its own recorded past, so a cross-backend
# disagreement that was present when the oracle was blessed is frozen AS the expected state.
#
# The sweeps do compare backends, and their comparator is right — `a64_sweep.sh`'s `a64_verdict`
# already prints `WRONG aarch64=$GOT want=$WANT (valid binary, normal exit, wrong = SILENT
# MISCOMPILE)`. But their input is the e2e `run <name> <want>` table, so they can only disagree over
# a program somebody already registered. The manifest walks far more sources, on all four backends,
# and throws the comparison away. This script is that comparison, and nothing else: it runs NO
# compiler and executes NO program — it is a join over a file the gate already regenerates.
#
# The rule, read straight off the manifest:
#
#   for every path whose `x86_64` row is phase `run`, flag each non-x86 `run` row whose exit
#   DIFFERS from the x86_64 exit and is < 128, whose stderr is EMPTY, and whose backend that
#   fixture does not already register an answer for in `scripts/e2e.sh`.
#
# The last two clauses are the triage's, not #683's; `--raw` drops them and re-derives the issue's
# original count exactly (29 paths / 60 rows at the time of writing). Their justification is at
# `the two filters` below — in short, neither is a curated list: both read declarations the tree
# already maintains, so neither can rot into a stale allow-list nobody re-reads.
#
# The `< 128` bound is the point. A shell exit of 128+N is a signal death, and this project accepts
# a trap: `AGENTS.md` says "a trap is acceptable; a wrong value is not". So a backend that traps
# where x86_64 answers is a `fails-when-valid` question for the sweeps, not a silent wrong value.
# What this report names is the other case — a backend that exits NORMALLY with a DIFFERENT answer.
#
# It deliberately does NOT decide whether a flagged row is a defect. Some divergences are legitimate:
# a hardware-defined `unchecked` operation (integer division by zero traps on x86_64, yields 0 on
# aarch64 and all-ones on riscv64), a fixture whose own `when target.arch` guard selects a different
# value per target, or a construct a backend implements only on x86 today. Separating those from real
# defects is a triage, one path at a time, and the triage's conclusions are not this script's to hold.
#
# REPORTING ONLY. This script never reddens a gate on a FINDING: it exits 0 whether or not it found
# anything, and it carries no baseline of its own. What remains after the two filters is real,
# undeclared divergence that nobody has read yet — 18 paths at the time of writing, itemised in
# #683's triage — so gating on it today would simply be permanently red. Promoting it to a gate is a
# separate decision, and the honest precondition is that those 18 reach zero or are declared.
#
# Usage:  scripts/xbackend_report.sh [--quiet] [--raw] [<manifest>]
#         scripts/xbackend_report.sh --self-test
#   default manifest: scripts/corpus.manifest
#   --quiet     print only the counts, not the per-path table
#   --raw       apply #683's literal rule only — no stderr and no registration filter, so the
#               issue's own measurement stays re-derivable from this script
#   --self-test run the planted-defect checks below and exit non-zero if the report cannot see one
# Exit 0 = the report ran (findings or not). Exit 2 = the manifest is missing or malformed.
# Exit 3 = --self-test failed, i.e. THIS SCRIPT is broken and its silence means nothing.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

QUIET=0
SELFTEST=0
RAW=0
export RAW
while [ "$#" -gt 0 ]; do
  case "$1" in
    --quiet)     QUIET=1; shift ;;
    --raw)       RAW=1; shift ;;
    --self-test) SELFTEST=1; shift ;;
    *)           break ;;
  esac
done
MANIFEST="${1:-scripts/corpus.manifest}"

## ── the two filters the triage added, and why they are not an allow-list ──────────────────────
## #683 feared that separating legitimate divergence from defect needed a reviewed allow-list, and
## that such a list would be a FOURTH oracle file. Triaging the 29 showed the declaration already
## exists, twice over, in data the repository already maintains:
##
##  1. `scripts/e2e.sh`'s REGISTRATION FORM. A fixture registered `run_a64 <name> <want>` states its
##     own expected aarch64 answer; 700+ registrations already do this (`run_x86` 270, `run_wat` 135,
##     `run_a64` 100, `run_rv64` 92). A divergence on a backend the fixture registers per-backend is
##     DECLARED, and reporting it would be reporting the table back at itself.
##  2. The manifest's own `stderr_sha256`. A tool that failed and said so is a loud failure, which
##     `AGENTS.md` accepts ("a trap is acceptable; a wrong value is not"); only an empty stderr makes
##     a differing exit a candidate SILENT wrong value. Measured: every one of the 426 wasm rows that
##     answered 42 has empty stderr, while 40 of the 52 wasm rows that exited 1 do not.
##
## So neither filter is a curated list — both read declarations the tree already carries, and both
## move when the tree moves. `--raw` turns them off to re-derive #683's original 29 paths / 60 rows.
EMIT="$(cd "$(dirname "$0")" && pwd)/e2e.sh"     # overridden by the self-test
SHA_EMPTY=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855

## Which backends a fixture registers PER BACKEND, as `<path>\t<backend>,…` lines.
declared_rows() {
  [ -r "$1" ] || return 0
  awk '
    /^run_a64([_a-z0-9]*)?[ \t]/  { print "aarch64\t" $2; next }
    /^run_rv64([_a-z0-9]*)?[ \t]/ { print "riscv64\t" $2; next }
    /^run_wat([_a-z0-9]*)?[ \t]/  { print "wasm\t"    $2 }
  ' "$1" | sort -u
}

## The join itself. Reads a manifest path, writes one line per flagged row:
##   <path> <backend> <x86_exit> <backend_exit>
## Kept as a function so the self-test below can feed it a synthetic manifest instead of the tree's.
xbackend_rows() {
  awk -F'\t' -v raw="${RAW:-0}" -v declf="${2:-}" -v empty="$SHA_EMPTY" '
    BEGIN { if (raw != 1 && declf != "")
              while ((getline l < declf) > 0) { split(l, d, "\t"); decl[d[2] "\t" d[1]] = 1 } }
    /^#/      { next }
    NF < 6    { next }
    $3 != "run" { next }
    $1 == "x86_64" { x[$2] = $4; next }
    { be[NR] = $1; p[NR] = $2; e[NR] = $4; se[NR] = $6 }
    END {
      for (i in p) {
        if (!(p[i] in x))            continue   # no x86_64 `run` row to compare against
        if (e[i] + 0 == x[p[i]] + 0) continue
        if (e[i] + 0 >= 128)         continue   # a trap is acceptable; a wrong value is not
        if (raw != 1) {
          if (se[i] != empty)                       continue   # loud failure, not a silent answer
          key = p[i]; sub(/^test\//, "", key); sub(/\.al$/, "", key)
          if ((key "\t" be[i]) in decl)             continue   # the e2e table declares this one
        }
        printf "%s\t%s\t%s\t%s\n", p[i], be[i], x[p[i]], e[i]
      }
    }
  ' "$1"
}

## ── the planted defect ────────────────────────────────────────────────────────────────────────
## `AGENTS.md`: "The whole-program invariant checks and cross-target sweeps need non-vacuity tests;
## a green gate that never fails its own planted defect is not evidence." A report that has never
## been seen to FIRE is decoration, so this proves every decision it makes, in both directions.
if [ "$SELFTEST" = 1 ]; then
  T="$(mktemp -d)" || exit 3
  trap 'rm -rf "$T"' EXIT
  fails=0; ran=0
  E="$SHA_EMPTY"          # stderr of a program that printed nothing
  L=1111111111111111111111111111111111111111111111111111111111111111   # ... and of one that did
  ## A stand-in e2e table: `p` is registered x86-only, `d` registers its own aarch64 answer.
  printf 'run_x86 p 42\nrun_x86 d 42\nrun_a64 d 24\n' > "$T/e2e.sh"
  declared_rows "$T/e2e.sh" > "$T/decl"
  check() { # <case> <expected-row-count> <manifest-body> [raw]
    ## `raw` is a positional argument, not `RAW=1 check …`: in bash a variable assignment prefixed
    ## to a SHELL FUNCTION persists in the caller afterwards, which would silently put every later
    ## case into raw mode and turn this self-test into a test of nothing.
    ran=$((ran + 1))
    printf '%s\n' "$3" > "$T/m"
    got="$(RAW="${4:-0}" xbackend_rows "$T/m" "$T/decl" | wc -l | tr -d ' ')"
    if [ "$got" = "$2" ]; then
      echo "  ok    $1 (rows=$got)"
    else
      echo "  FAIL  $1: expected $2 row(s), got $got"; fails=$((fails + 1))
    fi
  }
  H='columns=backend	path	phase	exit	stdout_sha256	stderr_sha256'
  # 1. the defect this report exists to catch: a quiet normal exit that disagrees with x86_64.
  check "planted divergence is seen" 1 "$H
x86_64	test/p.al	run	42	$E	$E
aarch64	test/p.al	run	24	$E	$E"
  # 2. agreement must stay silent, or every green run means nothing.
  check "agreement stays silent" 0 "$H
x86_64	test/p.al	run	42	$E	$E
aarch64	test/p.al	run	42	$E	$E"
  # 3. a trap is acceptable (AGENTS.md) — 128+N must NOT be reported as a wrong value.
  check "a trap is not a wrong value" 0 "$H
x86_64	test/p.al	run	42	$E	$E
aarch64	test/p.al	run	133	$E	$E"
  # 4. a row with no x86_64 `run` counterpart has nothing to disagree with.
  check "no x86_64 row, no verdict" 0 "$H
x86_64	test/p.al	build	1	$E	$E
aarch64	test/p.al	run	24	$E	$E"
  # 5. all three non-x86 backends are compared, not just the first.
  check "all three twins are compared" 3 "$H
x86_64	test/p.al	run	42	$E	$E
aarch64	test/p.al	run	24	$E	$E
riscv64	test/p.al	run	25	$E	$E
wasm	test/p.al	run	26	$E	$E"
  # 6. a tool that FAILED and said so on stderr is a loud failure, not a silent wrong value.
  check "a loud failure is not a silent wrong value" 0 "$H
x86_64	test/p.al	run	42	$E	$E
wasm	test/p.al	run	1	$E	$L"
  # 7. a divergence the e2e table already declares per backend is not a finding.
  check "a declared per-backend answer is not a finding" 0 "$H
x86_64	test/d.al	run	42	$E	$E
aarch64	test/d.al	run	24	$E	$E"
  # 8. ... but the SAME fixture on a backend it does NOT register still is.
  check "declaration covers only the backend it names" 1 "$H
x86_64	test/d.al	run	42	$E	$E
riscv64	test/d.al	run	24	$E	$E"
  # 9. `--raw` restores #683's literal rule, so the issue's 29/60 stays re-derivable: both of the
  #    rows filters 6 and 7 removed must come back.
  check "--raw restores the issue's literal rule" 2 "$H
x86_64	test/d.al	run	42	$E	$E
aarch64	test/d.al	run	24	$E	$E
wasm	test/d.al	run	1	$E	$L" 1
  if [ "$fails" = 0 ]; then echo "xbackend_report self-test: $ran/$ran ok"; exit 0; fi
  echo "xbackend_report self-test: $fails of $ran check(s) FAILED — this report's silence proves nothing"
  exit 3
fi

## ── the report ────────────────────────────────────────────────────────────────────────────────
[ -s "$MANIFEST" ] && grep -q '^columns=' "$MANIFEST" || {
  echo "xbackend_report: no usable manifest at $MANIFEST (expected a 'columns=' header)"; exit 2; }

TMP_ROWS="$(mktemp)" || exit 2
DECL="$(mktemp)" || exit 2
trap 'rm -f "$TMP_ROWS" "$DECL"' EXIT
declared_rows "$EMIT" > "$DECL"
ROWS="$(xbackend_rows "$MANIFEST" "$DECL")"
runrows="$(grep -c '	run	' "$MANIFEST")"
npaths=0; nrows=0
if [ -n "$ROWS" ]; then
  npaths="$(printf '%s\n' "$ROWS" | cut -f1 | sort -u | wc -l | tr -d ' ')"
  nrows="$(printf '%s\n' "$ROWS" | wc -l | tr -d ' ')"
fi

## The PROOF-OF-WORK line, in the shape `scripts/full.sh` greps for. It is printed on every run,
## findings or none, and it names what was WALKED — not just what was found. A report that says
## nothing is indistinguishable from a report that ran over an empty manifest, and the gate must be
## able to tell those apart (`scripts/idiom_gate.sh`'s `idiom gate: files=` line exists for the same
## reason, and full.sh treats its absence as a failure).
echo "xbackend report: paths=$npaths rows=$nrows walked-run-rows=$runrows"

[ "$nrows" = 0 ] && exit 0

echo "  $npaths path(s) where a non-x86 backend exits NORMALLY with a different answer than x86_64."
echo "  REPORTING ONLY — nothing here is gated, and none of it is triaged (see the header)."
printf '%s\n' "$ROWS" | cut -f2 | sort | uniq -c | while read -r n b; do
  printf '  %-8s %s\n' "$b" "$n"
done

if [ "$QUIET" = 0 ]; then
  ## Print every backend for a flagged path, not only the flagged ones. A path whose aarch64 row
  ## TRAPPED and whose wasm row answered differently would otherwise show a single column, and the
  ## reader cannot tell "agreed" from "trapped" from "never reached the run phase" — three states a
  ## triage must separate. Flagged values are bare; everything else is bracketed and is context only.
  echo
  echo "  bare = flagged (normal exit, different answer) · [n] = agreed or trapped · [-] = no run row"
  echo
  printf '%s\n' "$ROWS" | sort > "$TMP_ROWS"
  awk -F'\t' -v rows="$TMP_ROWS" '
    BEGIN { n = split("aarch64 riscv64 wasm", order, " ")
            while ((getline line < rows) > 0) {
              split(line, f, "\t"); flag[f[1] "\t" f[2]] = f[4]; want[f[1]] = f[3] }
            close(rows) }
    /^#/ || NF < 6 || $3 != "run" { next }
    { seen[$2 "\t" $1] = $4 }
    END {
      m = 0; for (p in want) paths[++m] = p
      for (i = 1; i <= m; i++) for (j = i + 1; j <= m; j++)
        if (paths[j] < paths[i]) { t = paths[i]; paths[i] = paths[j]; paths[j] = t }
      for (i = 1; i <= m; i++) {
        p = paths[i]; printf "%-46s x86=%-4s", p, want[p]
        for (k = 1; k <= n; k++) {
          b = order[k]
          if ((p "\t" b) in flag)      printf " %s=%-6s", b, flag[p "\t" b]
          else if ((p "\t" b) in seen) printf " %s=[%s]%*s", b, seen[p "\t" b], 4 - length(seen[p "\t" b]), ""
          else                         printf " %s=[-]   ", b
        }
        printf "\n"
      }
    }' "$MANIFEST"
fi
exit 0
