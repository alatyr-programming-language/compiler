#!/usr/bin/env bash
# twin_coverage.sh — where aarch64/riscv64/wasm do something NO TEST asserts.
#
# WHY. `scripts/e2e.sh`'s `run <name> <want>` compiles with "$CC" — the default target, x86_64 — so it
# declares an answer for x86_64 ONLY. The twins are spoken for by `run_a64` / `run_rv64` / `run_wat`.
# That leaves every corpus program whose x86_64 answer is declared and whose twin behaviour is unregistered
# in a state where a twin can do anything — including answer a different number — and the gate stays green.
# docs/ir-slice-3.md §18 measured 503 such trap sites in one family alone; this looks at the WHOLE corpus.
#
# The data is already committed: `scripts/corpus.manifest` holds (backend, path, phase, exit) for every
# tracked program on all four backends. Nothing here re-runs a compiler — it joins two committed files, so
# the answer is reproducible without a build box and cannot drift from what the gate observed.
#
# Classes, most urgent first:
#   WRONG-VALUE-UNASSERTED  x86_64 declares <want>, a twin RUNS, and its exit differs from <want>.
#                           A silent wrong value on a twin, with no test to catch it. This is the class
#                           AGENTS.md calls unacceptable and criterion 3 exists to empty.
#   TRAP-UNASSERTED         x86_64 declares <want>, a twin TRAPS (128+N). Loud, so not a wrong value;
#                           needs lowering work before it can be promoted to a run assertion.
#   PROMOTABLE-NOW          x86_64 declares <want>, the twin RUNS and answers <want>. The behaviour is
#                           already right and only the declaration is missing — registering it costs nothing
#                           and makes the agreement permanent.
#   ALREADY-DECLARED        a per-backend form names this twin; nothing to do.
#
# Usage: scripts/twin_coverage.sh [<manifest>] [--list CLASS] [--quiet]
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

## Since #1126 S3 the committed scripts/corpus.manifest holds only the sources with no `## expect:`
## directive (and the directive sources that print); the whole corpus is the last walk's observation,
## which `scripts/corpus_manifest.sh --check` leaves in target/. Read that when it exists.
MANIFEST="scripts/corpus.manifest"
[ -f target/corpus-manifest/observed.manifest ] && MANIFEST=target/corpus-manifest/observed.manifest
LIST=""
QUIET=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --list)  [ "$#" -ge 2 ] || { echo "twin_coverage: --list needs a class" >&2; exit 2; }
             LIST="$2"; shift 2 ;;
    --quiet) QUIET=1; shift ;;
    *)       MANIFEST="$1"; shift ;;
  esac
done
[ -f "$MANIFEST" ] || { echo "twin_coverage: no $MANIFEST" >&2; exit 1; }
[ -f scripts/e2e.sh ] || { echo "twin_coverage: no scripts/e2e.sh" >&2; exit 1; }


## Two passes over the manifest: first the x86_64 declarations, then each twin's observation.
awk -F'\t' -v e2e="scripts/e2e.sh" -v list="$LIST" -v quiet="$QUIET" '
## phase matters as much as the exit code: exit 1 at phase=assemble is a BUILD FAILURE, not a value.
## Reading the code without the phase turns "the twin cannot assemble this" into "the twin computed 1",
## which is a different defect and wants a different fix. (Caught by re-reading the manifest row.)
function verdict(b, base, ex, ph,   w) {
  w = ""
  if (b == "aarch64") { if (base in a64) return "ALREADY-DECLARED"; if (base in a64t) return "ALREADY-DECLARED"; w = xwant[base] }
  if (b == "riscv64") { if (base in rv)  return "ALREADY-DECLARED"; if (base in rvt)  return "ALREADY-DECLARED"; w = xwant[base] }
  if (b == "wasm")    { if (base in wat) return "ALREADY-DECLARED"; if (base in watt) return "ALREADY-DECLARED"; w = xwant[base] }
  if (w == "") return "NO-X86-DECLARATION"
  if (ph != "run") return ph "-UNASSERTED"          ## assemble / compile / link: the twin never ran
  if (ex + 0 >= 128) return "TRAP-UNASSERTED"
  if (ex == w) return "PROMOTABLE-NOW"
  return "WRONG-VALUE-UNASSERTED"
}
BEGIN {
  while ((getline l < e2e) > 0) {
    if (l !~ /^[a-z][a-z_0-9]*[ \t]/) continue
    n = split(l, f, /[ \t]+/); if (n < 2) continue
    form = f[1]; name = f[2]
    if (form == "run")                                        xwant[name] = f[3]
    else if (form == "run_a64" || form == "run_a64_out")  a64[name] = 1
    else if (form == "run_rv64" || form == "run_rv64_out") rv[name] = 1
    else if (form == "run_wat" || form == "run_wat_out")   wat[name] = 1
    else if (form == "run_a64_trap") a64t[name] = 1
    else if (form == "run_rv64_trap") rvt[name] = 1
    else if (form == "run_wat_trap")  watt[name] = 1
    else if (form == "build_reject" || form == "build_reject_has") rej[name] = 1
  }
  close(e2e)
}
NR == 1 { next }
$1 == "x86_64" { next }
{
  b = $1; p = $2; ph = $3; ex = $4
  base = p; sub(/^.*\//, "", base); sub(/\.al$/, "", base)
  if (base == "package") { base = p; sub(/\/package\.al$/, "", base); sub(/^.*\//, "", base) }
  if (base in rej) next
  v = verdict(b, base, ex, ph)
  if (v == "NO-X86-DECLARATION") next
  cnt[v]++; bc[v SUBSEP b]++
  if (list != "" && v == list) printf "%-24s %-8s want(x86)=%-5s got=%-5s %s\n", v, b, xwant[base], ex, p
  else if (!quiet) printf "%-24s %-8s want(x86)=%-5s got=%-5s %s\n", v, b, xwant[base], ex, p
}
END {
  printf "\n"
  order[1] = "WRONG-VALUE-UNASSERTED"; order[2] = "TRAP-UNASSERTED"; order[3] = "PROMOTABLE-NOW"; order[4] = "ALREADY-DECLARED"
  for (k in cnt) { if (k != order[1] && k != order[2] && k != order[3] && k != order[4]) { norder[++nn] = k } }
  for (i = 1; i <= nn; i++) { v = norder[i]; printf "%6d  %-24s", cnt[v], v; bs = ""
    if ((v SUBSEP "aarch64") in bc) bs = bs sprintf(" a64=%d", bc[v SUBSEP "aarch64"])
    if ((v SUBSEP "riscv64") in bc) bs = bs sprintf(" rv=%d",  bc[v SUBSEP "riscv64"])
    if ((v SUBSEP "wasm") in bc) bs = bs sprintf(" wasm=%d", bc[v SUBSEP "wasm"])
    printf "%s\n", bs }
  for (i = 1; i <= 4; i++) {
    v = order[i]
    printf "%6d  %-24s", cnt[v] + 0, v
    bs = ""
    if ((v SUBSEP "aarch64") in bc) bs = bs sprintf(" a64=%d", bc[v SUBSEP "aarch64"])
    if ((v SUBSEP "riscv64") in bc) bs = bs sprintf(" rv=%d",  bc[v SUBSEP "riscv64"])
    if ((v SUBSEP "wasm") in bc) bs = bs sprintf(" wasm=%d", bc[v SUBSEP "wasm"])
    printf "%s\n", bs
  }
}
' "$MANIFEST"
