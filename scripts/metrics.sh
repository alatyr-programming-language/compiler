#!/usr/bin/env bash
# scripts/metrics.sh — the weekly process and correctness report posted on the roadmap issue (#1131).
#
# A plan that cannot see its own trend drifts: between the 2026-10-23 audit and 2026-10-29 the open-issue
# count rose from 261 to 299 and nobody was told, because the numbers had been measured by hand once.
# This script measures them the same way every week. Every number it prints comes from a command below —
# `gh` for the issue and PR queue, `git` for what reached `main`, and the repository's own files for the
# correctness debt — and a quantity whose data does not exist yet prints `n/a` with the issue that will
# supply it, never a guess and never a zero.
#
# Usage:
#   scripts/metrics.sh [--days N] [--repo OWNER/NAME] [--no-fetch] [--list]
#   scripts/metrics.sh --self-test
#
#   --days N     the window, in days (default 7)
#   --repo R     the GitHub repository (default alatyr-programming-language/compiler)
#   --no-fetch   do not `git fetch origin main` first; report on the local origin/main as it is
#   --list       after the block, list the x86_64 rows that disagree with their fixture's header
#   --self-test  run the planted checks of the two local deciders (median, header vs row) and exit
#
# Runs from any checkout with `gh` authenticated, on macOS or Linux: every date is computed inside jq
# (`now`, `fromdateiso8601`), so neither BSD nor GNU `date` syntax is assumed. Needs bash, git, gh, jq,
# awk. It writes only a private `mktemp -d` directory under target/, which it removes.
#
# What each line measures, so that a reader can re-derive it:
#   issues      `gh issue list --state all`: open now; createdAt and closedAt inside the window. PRs are
#               not issues and are not counted. A closed duplicate counts as closed.
#   debt        open issues carrying the label; "older than 30 d" is createdAt more than 30 days ago.
#   landings    `git log --first-parent origin/main --since`: every commit that moved main in the window,
#               and how many of them are merges (a PR landing; the rest are oracle, baseline and reseed
#               commits the landing procedure appends). The window uses committer time.
#   lead time   `gh pr list --state merged`: mergedAt − createdAt for every PR merged in the window; the
#               median of an even count is the mean of the two middle values.
#   x86_64 rows the x86_64 rows of scripts/corpus.manifest whose observed result differs from what the
#               fixture's header declares, as read by scripts/fixture_oracle.sh `oracle` (the one reader
#               of that declaration, #683). A row with no declaration is not compared; the count of
#               fixtures that declare anything is printed beside it, so the denominator is visible. Once
#               scripts/known-deviations.tsv exists (#1126 S2) its rows per backend are reported instead.
#   gate time   `gh run list --workflow gate.yml`: the last five completed (green or red) hosted runs,
#               updatedAt − startedAt. Cancelled runs are skipped: they did not run to a verdict.
set -u
export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 2

DAYS=7
REPO=alatyr-programming-language/compiler
FETCH=1
LIST=0

## median_hours: one duration in seconds per line on stdin -> the median, in hours with one decimal, or
## `n/a` for an empty input. The one decider this script owns about lead time; the self-test drives it.
median_hours() {
  jq -rs 'sort | length as $n
    | if $n == 0 then "n/a"
      elif $n % 2 == 1 then (.[($n - 1) / 2] / 3600 * 10 | round / 10 | tostring)
      else ((.[$n / 2 - 1] + .[$n / 2]) / 2 / 3600 * 10 | round / 10 | tostring) end'
}

## x86_disagreements MANIFEST TESTDIR-PREFIX -> one line per declaring fixture:
##   verdict <TAB> path <TAB> declared <TAB> observed
## verdict is `agree`, `DISAGREE` or `unobserved` (the fixture has no x86_64 row). `declared` is the
## answer of fixture_oracle.sh `oracle`: `reject` or `exit:N`. A `reject` declaration is met by any
## terminal phase other than `run`; `exit:N` only by phase `run` with exit N.
x86_disagreements() { # manifest, glob-root (the directory that holds test/)
  local manifest="$1" root="$2" f o
  # shellcheck source=fixture_oracle.sh
  . "$ROOT/scripts/fixture_oracle.sh"
  # Only a file with a candidate line in its 30-line header can declare anything; `oracle` decides.
  ( cd "$root" && awk 'FNR <= 30 && tolower($0) ~ /^##[[:space:]]*(expected|build_reject)/ { print FILENAME; nextfile }' test/*.al ) |
    while IFS= read -r f; do
      o="$(oracle "$root/$f")"
      [ "$o" = none ] && continue
      printf '%s\t%s\n' "$f" "$o"
    done |
    awk -F'\t' -v OFS='\t' '
      NR == FNR { if ($1 == "x86_64") { phase[$2] = $3; code[$2] = $4 } ; next }
      {
        p = $1; d = $2
        if (!(p in phase)) { print "unobserved", p, d, "-"; next }
        obs = phase[p] "/" code[p]
        if (d == "reject") ok = (phase[p] != "run")
        else { n = d; sub(/^exit:/, "", n); ok = (phase[p] == "run" && code[p] == n) }
        print (ok ? "agree" : "DISAGREE"), p, d, obs
      }' "$manifest" -
}

self_test() {
  local d rc=0 got
  mkdir -p "$ROOT/target" && d="$(mktemp -d "$ROOT/target/metrics-selftest.XXXXXX")" || return 2
  chk() { if [ "$2" = "$3" ]; then echo "  ok   $1"; else echo "  FAIL $1 — got '$2', want '$3'"; rc=1; fi; }
  got="$(printf '' | median_hours)";                    chk "median of nothing is n/a"          "$got" "n/a"
  got="$(printf '3600\n' | median_hours)";              chk "median of one value"               "$got" "1"
  got="$(printf '36000\n3600\n7200\n' | median_hours)"; chk "median of an odd count is sorted"  "$got" "2"
  got="$(printf '3600\n7200\n10800\n360000\n' | median_hours)"
  chk "median of an even count is the mean of the middle two" "$got" "2.5"
  mkdir -p "$d/test"
  printf '## Expected exit: 42.\nmain := fn() -> u64 { return 42 }\n'      > "$d/test/ok.al"
  printf '## Expected exit: 42.\nmain := fn() -> u64 { return 0 }\n'       > "$d/test/wrong.al"
  printf '## build_reject — due\nmain := fn() -> u64 { return 1 }\n'       > "$d/test/rej.al"
  printf '## build_reject — due\nmain := fn() -> u64 { return 1 }\n'       > "$d/test/rej_runs.al"
  printf '## prose only, exit 42 is mentioned\nmain := fn() -> u64 { return 1 }\n' > "$d/test/prose.al"
  printf '## Expected exit: 7.\nmain := fn() -> u64 { return 7 }\n'        > "$d/test/new.al"
  printf '%s\n' \
    "x86_64	test/ok.al	run	42	h	h"       "aarch64	test/wrong.al	run	42	h	h" \
    "x86_64	test/wrong.al	run	0	h	h"   "x86_64	test/rej.al	compile	1	h	h" \
    "x86_64	test/rej_runs.al	run	1	h	h" "x86_64	test/prose.al	run	9	h	h" > "$d/m"
  x86_disagreements "$d/m" "$d" | sort > "$d/out"
  got="$(grep -c '^agree' "$d/out")";      chk "a matching run and a refused build agree"          "$got" "2"
  got="$(awk -F'\t' '$1=="DISAGREE"{print $2}' "$d/out" | tr '\n' ' ')"
  chk "a wrong exit and a build_reject that ran disagree (aarch64 rows ignored)" "$got" "test/rej_runs.al test/wrong.al "
  got="$(awk -F'\t' '$1=="unobserved"{print $2}' "$d/out")"; chk "a fixture with no x86_64 row is unobserved" "$got" "test/new.al"
  got="$(grep -c 'prose' "$d/out")";       chk "a header without a declaration is not compared"    "$got" "0"
  rm -rf "$d"
  [ "$rc" = 0 ] && echo "metrics self-test: 8 checks, 0 failed" || echo "metrics self-test: FAILED"
  return "$rc"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --days) DAYS="${2:-}"; shift 2 ;;
    --repo) REPO="${2:-}"; shift 2 ;;
    --no-fetch) FETCH=0; shift ;;
    --list) LIST=1; shift ;;
    --self-test) self_test; exit $? ;;
    -h|--help) sed -n '2,/^set -u/p' "$ROOT/scripts/metrics.sh" | sed '$d'; exit 0 ;;
    *) echo "metrics.sh: unknown argument '$1' (try --help)" >&2; exit 2 ;;
  esac
done
case "$DAYS" in ''|*[!0-9]*|0) echo "metrics.sh: --days needs a positive integer" >&2; exit 2 ;; esac
for t in git gh jq awk; do
  command -v "$t" >/dev/null 2>&1 || { echo "metrics.sh: '$t' is not on PATH" >&2; exit 2; }
done

mkdir -p "$ROOT/target" && W="$(mktemp -d "$ROOT/target/metrics.XXXXXX")" || exit 2
trap 'rm -rf "$W"' EXIT

if [ "$FETCH" = 1 ]; then
  git fetch -q origin main || { echo "metrics.sh: git fetch origin main failed (use --no-fetch to report on the local ref)" >&2; exit 2; }
fi
MAIN="$(git rev-parse --short origin/main)" || exit 2

## ---- issues ---------------------------------------------------------------------------------------
ISSUE_LIMIT=10000
gh issue list -R "$REPO" --state all -L "$ISSUE_LIMIT" \
  --json number,state,createdAt,closedAt,labels > "$W/issues.json" || { echo "metrics.sh: gh issue list failed" >&2; exit 2; }
n_all="$(jq length "$W/issues.json")"
[ "$n_all" -lt "$ISSUE_LIMIT" ] || { echo "metrics.sh: $n_all issues reached the list limit; the counts would be truncated" >&2; exit 2; }

q() { jq -r --argjson days "$DAYS" "(now - \$days * 86400) as \$cut | (now - 30 * 86400) as \$old | $1" "$W/issues.json"; }
open_n="$(q '[.[] | select(.state == "OPEN")] | length')"
opened_n="$(q '[.[] | select((.createdAt | fromdateiso8601) >= $cut)] | length')"
closed_n="$(q '[.[] | select(.closedAt != null and (.closedAt | fromdateiso8601) >= $cut)] | length')"
lab() { q "[.[] | select(.state == \"OPEN\" and any(.labels[]; .name == \"$1\"))] | length"; }
labold() { q "[.[] | select(.state == \"OPEN\" and any(.labels[]; .name == \"$1\") and (.createdAt | fromdateiso8601) < \$old)] | length"; }
wv_n="$(lab wrong-value)"; wv_old="$(labold wrong-value)"
p0_n="$(lab priority-0)"; p0_old="$(labold priority-0)"
fwv_n="$(lab fails-when-valid)"
week_from="$(jq -rn --argjson days "$DAYS" 'now - $days * 86400 | strftime("%Y-%m-%d %H:%M UTC")')"
today="$(jq -rn 'now | strftime("%Y-%m-%d %H:%M UTC")')"

## ---- landings and lead time ---------------------------------------------------------------------
git log --first-parent --since="$DAYS days ago" --format='%H %P' origin/main > "$W/fp" || exit 2
land_n="$(wc -l < "$W/fp" | tr -d ' ')"
merge_n="$(awk 'NF > 2' "$W/fp" | wc -l | tr -d ' ')"
since_day="$(jq -rn --argjson days "$DAYS" '(now - $days * 86400) | strftime("%Y-%m-%d")')"
gh pr list -R "$REPO" --state merged --search "merged:>=$since_day" -L 1000 \
  --json number,createdAt,mergedAt > "$W/prs.json" || { echo "metrics.sh: gh pr list failed" >&2; exit 2; }
jq -r --argjson days "$DAYS" '(now - $days * 86400) as $cut
  | .[] | select((.mergedAt | fromdateiso8601) >= $cut)
  | (.mergedAt | fromdateiso8601) - (.createdAt | fromdateiso8601)' "$W/prs.json" > "$W/lead"
pr_n="$(wc -l < "$W/lead" | tr -d ' ')"
lead_h="$(median_hours < "$W/lead")"

## ---- correctness debt -----------------------------------------------------------------------------
if [ -f scripts/known-deviations.tsv ]; then
  dev_line="$(awk -F'\t' '!/^#/ && NF >= 4 { n[$1]++; t++ } END {
      printf "%d rows —", t; split("x86_64 aarch64 riscv64 wasm", b, " ")
      for (i = 1; i <= 4; i++) printf " %s %d", b[i], n[b[i]] + 0 }' scripts/known-deviations.tsv)"
  debt_label="known deviations (scripts/known-deviations.tsv)"
else
  x86_disagreements scripts/corpus.manifest "$ROOT" > "$W/x86"
  decl_n="$(wc -l < "$W/x86" | tr -d ' ')"
  dis_n="$(grep -c '^DISAGREE' "$W/x86")"
  unobs_n="$(grep -c '^unobserved' "$W/x86")"
  rows_n="$(awk -F'\t' '$1 == "x86_64"' scripts/corpus.manifest | wc -l | tr -d ' ')"
  dev_line="$dis_n of $decl_n fixtures that declare an outcome in their header ($rows_n x86_64 rows; $unobs_n declaring fixtures have no row)"
  debt_label="x86_64 rows ≠ header expectation"
fi

## ---- gate wall time ------------------------------------------------------------------------------
gate_line="$(gh run list -R "$REPO" --workflow gate.yml -L 40 \
    --json conclusion,status,startedAt,updatedAt 2>/dev/null |
  jq -r '[.[] | select(.status == "completed" and (.conclusion == "success" or .conclusion == "failure"))][:5]
    | map(((.updatedAt | fromdateiso8601) - (.startedAt | fromdateiso8601)) / 60 | round)
    | if length == 0 then "n/a — no completed hosted run"
      else "\(map(tostring + " min") | join(", ")) (last \(length) hosted gate.yml runs, newest first)" end')"
[ -n "$gate_line" ] || gate_line="n/a — gh run list failed"

## ---- the block --------------------------------------------------------------------------------------
cat <<EOF
### Metrics — $today (window: $DAYS days, since $week_from; origin/main $MAIN)

| | |
|---|---|
| open issues | $open_n (opened $opened_n, closed $closed_n in the window) |
| open \`wrong-value\` | $wv_n ($wv_old older than 30 days) |
| open \`priority-0\` | $p0_n ($p0_old older than 30 days) |
| open \`fails-when-valid\` | $fwv_n |
| landings on main (first-parent) | $land_n commits, $merge_n of them merges |
| PRs merged / median lead time | $pr_n / $lead_h h (opened → merged) |
| $debt_label | $dev_line |
| container matrix \`WRONG\` cells | n/a — no matrix report on main yet (#1124) |
| pilots green / red | n/a — no pilot exists on main yet (#1125) |
| full-gate wall time, hosted | $gate_line |
| full-gate wall time, omen | n/a — omen runs are not recorded anywhere this script can read |

<sub>Produced by \`scripts/metrics.sh --days $DAYS\`; every number above comes from a command in that script.</sub>
EOF

if [ "$LIST" = 1 ] && [ -f "$W/x86" ]; then
  echo
  echo "x86_64 rows that disagree with the fixture header (declared vs observed phase/exit):"
  awk -F'\t' '$1 != "agree" { printf "  %-10s %s  declared %s, observed %s\n", $1, $2, $3, $4 }' "$W/x86"
fi
