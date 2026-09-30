#!/usr/bin/env bash
# scripts/xbackend_diff.sh — EVERY cross-backend disagreement in the corpus manifest, classified (#683).
#
# `scripts/corpus.manifest` records each tracked source on all four backends, and each row is only
# ever compared with its own recorded past. `scripts/xbackend_report.sh` asks ONE question of the
# four rows — does a twin exit NORMALLY with a different, quiet, undeclared answer? — and is wired
# into the gate as a reporting line. This script asks the wider one #683's goal needs: on which
# sources do the four rows disagree AT ALL in (phase, exit), and why? A trap on a twin where x86_64
# runs is acceptable to AGENTS.md's "a trap is acceptable, a wrong value is not", but it is still a
# program that works on one backend and not on another, and #683 now counts it as a disagreement to
# eliminate — either by implementing the lowering or by a LOCATED compile-time refusal.
#
# Like the report, it runs NO compiler and executes NO program by default: it is a join over the
# committed manifest. `--sites` is the one exception and is opt-in (see there).
#
# ## The comparison
#
# Each row's (phase, exit) is reduced to a STATE before comparing, because the backends spell the
# same outcome differently:
#
#   C      refused while building: `compile` (x86_64's `compile` covers its assemble AND link too,
#          which is why x86_64 has no `assemble`/`link` rows), or any `*_timeout` build phase
#   A / L  the twin's `assemble` / `link` step failed — the compiler emitted text its toolchain refused
#   V<n>   `run`, normal exit n
#   K      `run`, a DELIBERATE trap: exit 129..192 is death by signal 1..64, and each backend's own
#          trap instruction is one of them — x86_64 `ud2` → SIGILL 132 (and SIGFPE 136 for a division),
#          aarch64 `brk #0` and riscv64 `ebreak` → SIGTRAP 133, wasm `unreachable` → wasmtime 134
#   S      `run`, death by a signal that is NOT the twin's trap (e.g. 139, SIGSEGV): a memory fault,
#          not a located refusal. On x86_64 every signal is K; the distinction is about the twins.
#   T      `run_timeout`
#
# Exit 255 is deliberately a VALUE, not a signal: it is exit(-1), which is exactly what a `match` with
# no arm taken returns (AGENTS.md, #544). Folding it into K would hide that silent class.
#
# ## The classes (per twin row, against the x86_64 row), in priority order
#
#   WRONG-VALUE   x86 V<a>, twin V<b>, a != b, quiet       — the twin answers something else
#   MISSING-TRAP  x86 K,    twin V<b>, quiet               — x86 refuses at run time, the twin answers
#   CRASH         x86 V,    twin S                         — a fault, not a trap
#   LOUD-EXIT     x86 V|K,  twin V<b> != x86, with stderr  — the RUNNER failed and said so. Measured
#                 on wasm: wasmtime exits 1 both for an `unknown import` at instantiation (an FFI or
#                 bodyless extern the twin cannot satisfy) and for `exit with invalid exit status
#                 outside of [0..126)` — a program whose exit value wasmtime refuses to deliver, which
#                 HIDES the value and so may itself be a wrong value. `--sites` prints which.
#   TRAP          x86 V,    twin K                         — unimplemented lowering (fail-loud stub)
#   TIMEOUT       x86 V|K,  twin T  (or the reverse)
#   ASSEMBLE      x86 V|K,  twin A                         — the twin emitted text `as` refuses
#   LINK          x86 V|K,  twin L                         — e.g. a runtime symbol the twin lacks
#   REFUSED       x86 V|K,  twin C                         — the twin refuses to compile what x86 runs;
#                                                            the acceptable end state IF it is located
#   ACCEPTS       x86 C,    twin V|K|S|T                   — a twin builds a program x86_64 refuses
#   HW-DEFINED    a MISSING-TRAP row on a path in the `HW_DEFINED` list below: `unchecked` division by
#                 zero / `MIN / -1`, which the specification makes target-specific (Concurrency §6.2).
#                 Listed and counted (`hw-defined=`), but not part of `paths=`/`rows=`.
#
# Not a disagreement: equal states (V<a>/V<a>, K/K, C/C), and x86 C against twin A, L or a loud
# exit — every backend refused, only at a different step. `--all` lists those as REFUSED-LATE.
#
# "quiet"/"loud" is the twin row's stderr digest: empty or not. A runner that exited and printed why
# is a loud failure, not a silent answer (#683's triage measured that split on the wasm column).
# A path is listed under its highest-priority class; `--count` counts rows (path × twin) and paths.
#
# ## Usage
#
#   scripts/xbackend_diff.sh [--all] [--class C] [<manifest>]   per-path table, grouped by class
#   scripts/xbackend_diff.sh --count [<manifest>]               counts only, per class and backend
#   scripts/xbackend_diff.sh --rows [--all] [<manifest>]        machine rows: class TAB backend TAB path TAB x86 TAB twin TAB tag
#   scripts/xbackend_diff.sh --sites <compiler> [--class C] [<manifest>]
#       for every TRAP/CRASH row, rebuild that source for that twin with every trap instruction
#       rewritten into `exit(k)` (k = the site's ordinal), run it, and print WHICH site fired and the
#       emitter's own comment at it — the feature the backend is missing. For a LOUD-EXIT row it prints
#       the runner's reason, and for an ASSEMBLE/LINK row the toolchain's first error line. Needs the cross toolchains
#       and runners on PATH (`nix develop`); `<compiler>` must be an absolute path inside a checkout
#       (the compiler finds `lib/` relative to itself). Output: backend TAB path TAB
#       SITE|NOSITE|LOUD|ASSEMBLE|LINK|REJ|BUILD-FAIL TAB detail TAB function.
#   scripts/xbackend_diff.sh --self-test
#
# Exit 0 = ran (findings or not; this is REPORTING ONLY). 2 = manifest missing/malformed or bad usage.
# 3 = --self-test failed: this script is broken and its output means nothing.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

MODE=table
ALL=0
CLASS=""
SITES_CC=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --count)     MODE=count; shift ;;
    --rows)      MODE=rows; shift ;;
    --all)       ALL=1; shift ;;
    --class)     [ "$#" -ge 2 ] || { echo "xbackend_diff: --class needs a class name" >&2; exit 2; }
                 CLASS="$2"; shift 2 ;;
    --sites)     [ "$#" -ge 2 ] || { echo "xbackend_diff: --sites needs a compiler path" >&2; exit 2; }
                 MODE=sites; SITES_CC="$2"; shift 2 ;;
    --self-test) MODE=selftest; shift ;;
    -h|--help)   sed -n '2,/^set -u/p' "$0" | sed -e 's/^# \{0,1\}//' -e '$d'; exit 0 ;;
    -*)          echo "xbackend_diff: unknown option: $1" >&2; exit 2 ;;
    *)           break ;;
  esac
done
MANIFEST="${1:-$ROOT/scripts/corpus.manifest}"
SHA_EMPTY=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
CLASS_ORDER="WRONG-VALUE MISSING-TRAP CRASH LOUD-EXIT TRAP TIMEOUT ASSEMBLE LINK REFUSED ACCEPTS HW-DEFINED REFUSED-LATE"

## ── the documented hardware-defined divergences ───────────────────────────────────────────────
## Specification (pin b4e7979), Concurrency §6.2 "Inside an `unchecked` scope: wrap":
##
##   "The remaining members of the family are dropped to **hardware behaviour**, which is *not* the
##    same thing and *not* uniform: **division by zero**, an **over-width shift**, and **`MIN ÷ -1`**
##    do whatever the target does — `x86_64` faults on `MIN ÷ -1` and on a zero divisor (`#DE`),
##    `aarch64` yields `MIN` and `0` respectively, and an over-width shift is masked on some ISAs and
##    not others. Writing them under `unchecked` is therefore target-specific by construction (I11:
##    hardware-defined, never UB — but never portable either)."
##
## So a program that divides by zero, or `MIN / -1`, inside `unchecked` is REQUIRED to disagree:
## x86_64 faults (SIGFPE, exit 136) where aarch64 and riscv64 answer their ISA's defined value. The
## paths below are exactly such fixtures, each registered per backend in scripts/e2e.sh with its own
## hardware answer. They are NOT hidden: a listed path's rows are classed HW-DEFINED, printed in the
## table and counted on the headline line as `hw-defined=`, and excluded only from `paths=`/`rows=`,
## the count #683 drives to zero. The exemption is narrow on purpose — it applies ONLY to the
## MISSING-TRAP shape (x86_64 traps, the twin exits quietly with a value); any other disagreement on a
## listed path (a twin that crashes, answers where x86_64 answers differently, …) keeps its own class.
## Add a path here only with a fixture whose operation is one the paragraph above names.
HW_DEFINED='test/unchecked_div_zero.al
test/unchecked_udiv_zero.al
test/unchecked_rem_zero.al
test/unchecked_div_min_neg1.al'

## The join. Reads a manifest, writes one line per disagreeing (path, twin):
##   class TAB backend TAB path TAB x86-state TAB twin-state TAB tag
## `all=1` also emits REFUSED-LATE. Kept a function so the self-test feeds it synthetic manifests.
xb_rows() { # manifest all [hw-defined-list]
  awk -F'\t' -v all="$2" -v empty="$SHA_EMPTY" -v hwl="$(printf '%s' "${3-$HW_DEFINED}" | tr '\n' ' ')" '
    BEGIN { nh = split(hwl, hl, " "); for (i = 1; i <= nh; i++) if (hl[i] != "") hw[hl[i]] = 1 }
    function state(be, ph, ex) {
      if (ph ~ /_timeout$/) return (ph == "run_timeout") ? "T" : "C"
      if (ph == "compile") return "C"
      if (ph == "assemble") return "A"
      if (ph == "link") return "L"
      if (ph != "run") return "?" ph
      ex += 0
      if (ex >= 129 && ex <= 192) {
        if (be == "x86_64") return "K"
        if ((be == "aarch64" || be == "riscv64") && ex == 133) return "K"
        if (be == "wasm" && ex == 134) return "K"
        return "S"
      }
      return "V" ex
    }
    function klass(x, t, loud) {
      if (x == t) return ""
      xv = (x ~ /^V/); tv = (t ~ /^V/)
      if (tv && loud)                     return (x == "C") ? "REFUSED-LATE" : "LOUD-EXIT"
      if (xv && tv)                       return "WRONG-VALUE"
      if (x == "K" && tv)                 return "MISSING-TRAP"
      if (x == "K" && t == "S")           return ""            # both die by signal: both loud
      if (xv && t == "S")                 return "CRASH"
      if (xv && t == "K")                 return "TRAP"
      if (x == "T" || t == "T")           return (x == "C") ? "ACCEPTS" : "TIMEOUT"
      if (x == "C" && (t == "A" || t == "L")) return "REFUSED-LATE"
      if (x == "C")                       return "ACCEPTS"
      if (t == "A")                       return "ASSEMBLE"
      if (t == "L")                       return "LINK"
      if (t == "C")                       return "REFUSED"
      return "UNCLASSIFIED"
    }
    /^#/ || NF < 6 { next }
    $1 != "x86_64" && $1 != "aarch64" && $1 != "riscv64" && $1 != "wasm" { next }
    { st[$2 "\t" $1] = state($1, $3, $4); se[$2 "\t" $1] = $6; if (!($2 in seen)) { seen[$2] = 1; order[++n] = $2 } }
    END {
      split("aarch64 riscv64 wasm", tw, " ")
      for (i = 1; i <= n; i++) {
        p = order[i]
        if (!((p "\t" "x86_64") in st)) continue
        x = st[p "\t" "x86_64"]
        for (j = 1; j <= 3; j++) {
          b = tw[j]; k = p "\t" b
          if (!(k in st)) continue
          c = klass(x, st[k], se[k] != empty)
          if (c == "MISSING-TRAP" && (p in hw)) c = "HW-DEFINED"
          if (c == "" || (c == "REFUSED-LATE" && all != 1)) continue
          tag = (st[k] ~ /^V/) ? ((se[k] == empty) ? "quiet" : "loud") : "-"
          printf "%s\t%s\t%s\t%s\t%s\t%s\n", c, b, p, x, st[k], tag
        }
      }
    }' "$1"
}

## The site rewrite: the k-th trap instruction of a twin's emission becomes exit(k), so the run's own
## exit status names the site that fired. Sites past 250 share codes (k mod 250) and are marked
## ambiguous by the caller. Comments are skipped for wasm: the emitters write `unreachable` in prose.
rewrite_gas() { # backend < in.s > out.s
  if [ "$1" = aarch64 ]; then
    awk '/^[ \t]*brk #0/ { n++; printf "  mov x0, #%d\n  mov x8, #93\n  svc #0\n", (n - 1) % 250 + 1; next } { print }'
  else
    awk '/^[ \t]*ebreak/ { n++; printf "  li a0, %d\n  li a7, 93\n  ecall\n", (n - 1) % 250 + 1; next } { print }'
  fi
}
gas_site_line() { # backend k < in.s  — prints "<lineno>" of the k-th trap instruction
  local pat='^[[:space:]]*brk #0'; [ "$1" = riscv64 ] && pat='^[[:space:]]*ebreak'
  grep -nE "$pat" | sed -n "${2}p" | cut -d: -f1
}
gas_site_count() { # backend < in.s
  local pat='^[[:space:]]*brk #0'; [ "$1" = riscv64 ] && pat='^[[:space:]]*ebreak'
  grep -cE "$pat"
}
WAT_SITE_RE='(\(;.*?;\))|\(unreachable\)|\bunreachable\b'
rewrite_wat() { # < in.wat > out.wat
  perl -e 'local $/; my $s = <STDIN>; my $n = 0;
    $s =~ s{'"$WAT_SITE_RE"'}{ defined $1 ? $1 : do { $n++; "(call \$proc_exit (i32.const " . (($n - 1) % 250 + 1) . ")) (unreachable)" } }gse;
    print $s'
}
wat_site_count() { # < in.wat
  perl -e 'local $/; my $s = <STDIN>; my $n = 0; while ($s =~ /'"$WAT_SITE_RE"'/gs) { $n++ unless defined $1 } print "$n\n"'
}
wat_site_info() { # k < in.wat — prints "comment TAB function" for the k-th site
  perl -e 'my $k = shift; local $/; my $s = <STDIN>; my $n = 0;
    while ($s =~ /'"$WAT_SITE_RE"'/gs) { next if defined $1; next unless ++$n == $k;
      my $p = pos($s); my $rest = substr($s, $p, 400); $rest =~ s/\n.*//s;
      my ($c) = $rest =~ /^\s*(\(;.*?;\))/; $c //= "(bare)";
      my ($f) = substr($s, 0, $p) =~ /.*\(func (\$\S+)/s; $f //= "?";
      print "$c\t$f\n"; last }' "$1"
}

if [ "$MODE" = selftest ]; then
  T="$(mktemp -d)" || exit 3
  trap 'rm -rf "$T"' EXIT
  fails=0; ran=0
  E="$SHA_EMPTY"; L=1111111111111111111111111111111111111111111111111111111111111111
  H='columns=backend	path	phase	exit	stdout_sha256	stderr_sha256'
  ok() { ran=$((ran + 1)); if [ "$2" = "$3" ]; then echo "  ok    $1"; else
         echo "  FAIL  $1: expected [$3], got [$2]"; fails=$((fails + 1)); fi; }
  rows_of() { printf '%s\n' "$H" "$@" > "$T/m"; xb_rows "$T/m" "${ALLX:-0}" | cut -f1,2 | tr '\t\n' ': ' | sed 's/ $//'; }
  q() { printf '%s\t%s\t%s\t%s\t%s\t%s' "$1" test/p.al "$2" "$3" "$E" "${4:-$E}"; }
  ok "agreement is silent" "$(rows_of "$(q x86_64 run 42)" "$(q aarch64 run 42)" "$(q riscv64 run 42)" "$(q wasm run 42)")" ""
  ok "each backend's own trap signal is the SAME trap" \
     "$(rows_of "$(q x86_64 run 132)" "$(q aarch64 run 133)" "$(q riscv64 run 133)" "$(q wasm run 134)")" ""
  ok "a planted wrong value is seen, on the twin that has it" \
     "$(rows_of "$(q x86_64 run 42)" "$(q aarch64 run 42)" "$(q riscv64 run 24)" "$(q wasm run 42)")" "WRONG-VALUE:riscv64"
  ok "a trap where x86_64 runs is a disagreement" \
     "$(rows_of "$(q x86_64 run 42)" "$(q aarch64 run 133)" "$(q wasm run 134)")" "TRAP:aarch64 TRAP:wasm"
  ok "a value where x86_64 traps is MISSING-TRAP" "$(rows_of "$(q x86_64 run 132)" "$(q aarch64 run 44)")" "MISSING-TRAP:aarch64"
  ok "a foreign signal on a twin is a CRASH, not a trap" "$(rows_of "$(q x86_64 run 42)" "$(q aarch64 run 139)" "$(q wasm run 133)")" \
     "CRASH:aarch64 CRASH:wasm"
  ok "exit 255 is exit(-1), a VALUE" "$(rows_of "$(q x86_64 run 42)" "$(q riscv64 run 255)")" "WRONG-VALUE:riscv64"
  ok "build-step failures are named by step" \
     "$(rows_of "$(q x86_64 run 42)" "$(q aarch64 assemble 1)" "$(q riscv64 link 1)" "$(q wasm compile 1)")" \
     "ASSEMBLE:aarch64 LINK:riscv64 REFUSED:wasm"
  ok "all four refusing at compile is silent" \
     "$(rows_of "$(q x86_64 compile 1)" "$(q aarch64 compile 1)" "$(q riscv64 compile 1)" "$(q wasm compile 1)")" ""
  ok "refusing at a later build step is silent by default" "$(rows_of "$(q x86_64 compile 14)" "$(q aarch64 link 1)")" ""
  ok "... and listed as REFUSED-LATE under --all" "$(ALLX=1 rows_of "$(q x86_64 compile 14)" "$(q aarch64 link 1)")" "REFUSED-LATE:aarch64"
  ok "a twin that builds what x86_64 refuses is ACCEPTS" \
     "$(rows_of "$(q x86_64 compile 1)" "$(q aarch64 run 7)" "$(q wasm run 134)")" "ACCEPTS:aarch64 ACCEPTS:wasm"
  ok "a build timeout is a refusal, a run timeout is TIMEOUT" \
     "$(rows_of "$(q x86_64 run 42)" "$(q aarch64 compile_timeout 124)" "$(q wasm run_timeout 124)")" "REFUSED:aarch64 TIMEOUT:wasm"
  ok "no x86_64 row, no verdict" "$(rows_of "$(q aarch64 run 1)")" ""
  ## The hardware-defined list: it reclasses ONLY the MISSING-TRAP shape of a LISTED path.
  hq() { printf '%s\t%s\t%s\t%s\t%s\t%s' "$1" test/hw.al "$2" "$3" "$E" "$E"; }
  printf '%s\n' "$H" "$(hq x86_64 run 136)" "$(hq aarch64 run 41)" "$(hq riscv64 run 42)" "$(hq wasm run 134)" > "$T/m"
  ok "a listed hardware-defined path is HW-DEFINED" "$(xb_rows "$T/m" 0 test/hw.al | cut -f1,2 | tr '\t\n' ': ' | sed 's/ $//')" \
     "HW-DEFINED:aarch64 HW-DEFINED:riscv64"
  ok "... and the same rows unlisted stay MISSING-TRAP" "$(xb_rows "$T/m" 0 test/other.al | cut -f1 | sort -u)" "MISSING-TRAP"
  printf '%s\n' "$H" "$(hq x86_64 run 42)" "$(hq aarch64 run 41)" "$(hq riscv64 run 139)" > "$T/m"
  ok "the list never excuses a wrong value or a crash on a listed path" \
     "$(xb_rows "$T/m" 0 test/hw.al | cut -f1,2 | tr '\t\n' ': ' | sed 's/ $//')" "WRONG-VALUE:aarch64 CRASH:riscv64"
  ok "the committed list names only fixtures that exist" \
     "$(printf '%s\n' "$HW_DEFINED" | while read -r f; do [ -f "$ROOT/$f" ] || echo "$f"; done)" ""
  printf '%s\n' "$H" "$(q x86_64 run 42)" "$(q wasm run 1 "$L")" "$(q aarch64 run 3)" > "$T/m"
  ok "a differing exit is WRONG-VALUE when quiet, LOUD-EXIT when the runner said why" \
     "$(xb_rows "$T/m" 0 | cut -f1,2,6 | tr '\t\n' ': ' | sed 's/ $//')" "WRONG-VALUE:aarch64:quiet LOUD-EXIT:wasm:loud"
  printf '%s\n' "$H" "$(q x86_64 compile 14)" "$(q wasm run 1 "$L")" > "$T/m"
  ok "a loud exit where x86_64 refused is REFUSED-LATE, not ACCEPTS" "$(xb_rows "$T/m" 1 | cut -f1)" "REFUSED-LATE"
  ## The site rewrite: numbering must follow the instruction order and skip prose.
  printf 'f:\n  brk #0 // one\n  mov x0, x1\n  brk #0 // two\n// brk #0 in a comment line\n' > "$T/a.s"
  ok "aarch64 sites counted" "$(gas_site_count aarch64 < "$T/a.s")" 2
  ok "aarch64 site 2 is exit(2)" "$(rewrite_gas aarch64 < "$T/a.s" | grep -c 'mov x0, #2$')" 1
  ok "aarch64 site 2 maps back to its line" "$(gas_site_line aarch64 2 < "$T/a.s")" 4
  printf 'f:\n  ebreak\n  ebreak\n  ebreak\n' > "$T/r.s"
  ok "riscv64 site 3 is exit(3)" "$(rewrite_gas riscv64 < "$T/r.s" | grep -c 'li a0, 3$')" 1
  printf '(func $main (; unreachable in prose ;)\n  (return (unreachable) (; why one ;))\n  unreachable\n)\n' > "$T/w.wat"
  ok "wat sites skip comments" "$(wat_site_count < "$T/w.wat")" 2
  ok "wat site 1 carries its comment" "$(wat_site_info 1 < "$T/w.wat")" "$(printf '(; why one ;)\t$main')"
  ok "wat site 2 is exit(2)" "$(rewrite_wat < "$T/w.wat" | grep -c 'i32.const 2)')" 1
  ok "wat prose is untouched" "$(rewrite_wat < "$T/w.wat" | grep -c '(; unreachable in prose ;)')" 1
  if [ "$fails" = 0 ]; then echo "xbackend_diff self-test: $ran/$ran ok"; exit 0; fi
  echo "xbackend_diff self-test: $fails of $ran check(s) FAILED — this script's output proves nothing"
  exit 3
fi

[ -s "$MANIFEST" ] && grep -q '^columns=' "$MANIFEST" || {
  echo "xbackend_diff: no usable manifest at $MANIFEST (expected a 'columns=' header)" >&2; exit 2; }

ROWS="$(xb_rows "$MANIFEST" "$ALL")"
[ -n "$CLASS" ] && ROWS="$(printf '%s\n' "$ROWS" | awk -F'\t' -v c="$CLASS" '$1 == c')"
[ -n "$ROWS" ] || ROWS=""

if [ "$MODE" = rows ]; then
  [ -n "$ROWS" ] && printf '%s\n' "$ROWS"
  exit 0
fi

if [ "$MODE" = sites ]; then
  case "$SITES_CC" in /*) ;; *) echo "xbackend_diff: --sites needs an ABSOLUTE compiler path" >&2; exit 2 ;; esac
  [ -x "$SITES_CC" ] || { echo "xbackend_diff: no executable compiler at $SITES_CC" >&2; exit 2; }
  W="$(mktemp -d)" || exit 2
  trap 'rm -rf "$W"' EXIT
  cd "$ROOT" || exit 2
  runq() { (exec 2>/dev/null; cd "$W" && timeout 10 env -i LC_ALL=C TZ=UTC HOME=/nonexistent PATH=/usr/bin:/bin "$@" >/dev/null 2>&1 </dev/null); }
  printf '%s\n' "$ROWS" | awk -F'\t' '$1 ~ /^(TRAP|CRASH|LOUD-EXIT|ASSEMBLE|LINK)$/' | while IFS=$'\t' read -r c b p _x _t _g; do
    if [ "$c" = ASSEMBLE ] || [ "$c" = LINK ]; then
      ## No program ran: report the toolchain's own first complaint, with the scratch path removed.
      if [ "$b" = wasm ]; then
        "$SITES_CC" wat "$p" > "$W/p.wat" 2>/dev/null; wat2wasm "$W/p.wat" -o "$W/p.wasm" 2>"$W/err" >/dev/null
      else
        "$SITES_CC" "$b" "$p" > "$W/p.s" 2>/dev/null
        "$b-unknown-linux-gnu-as" "$W/p.s" -o "$W/p.o" 2>"$W/err" >/dev/null \
          && "$b-unknown-linux-gnu-ld" "$W/p.o" -o "$W/p.elf" 2>"$W/err" >/dev/null
      fi
      printf '%s\t%s\t%s\t%s\t-\n' "$b" "$p" "$c" "$(grep -m1 -iE 'error|undefined' "$W/err" | sed "s|$W/||g" | cut -c1-160)"
      continue
    fi
    if [ "$c" = LOUD-EXIT ]; then
      ## No site to find: the runner refused. Report ITS reason, which separates an import the twin
      ## cannot satisfy from an exit value the runner would not deliver.
      [ "$b" = wasm ] || { printf '%s\t%s\tLOUD\t-\t-\n' "$b" "$p"; continue; }
      "$SITES_CC" wat "$p" > "$W/p.wat" 2>/dev/null && wat2wasm "$W/p.wat" -o "$W/p.wasm" 2>/dev/null \
        || { printf '%s\t%s\tBUILD-FAIL\t-\t-\n' "$b" "$p"; continue; }
      (cd "$W" && timeout 10 env -i LC_ALL=C TZ=UTC HOME=/nonexistent PATH=/usr/bin:/bin "$(command -v wasmtime)" -C cache=n "$W/p.wasm" \
        >/dev/null 2>"$W/err" </dev/null)
      printf '%s\t%s\tLOUD\t%s\t-\n' "$b" "$p" "$(grep -E '^ *[0-9]+: ' "$W/err" | grep -v 'wasm backtrace\|failed to (invoke|run|instantiate)\|<unknown>' | tail -1 | sed -E 's/^ *[0-9]+: //')"
      continue
    fi
    case "$b" in
      aarch64|riscv64)
        "$SITES_CC" "$b" "$p" > "$W/p.s" 2>/dev/null || { printf '%s\t%s\tREJ\t-\t-\n' "$b" "$p"; continue; }
        n="$(gas_site_count "$b" < "$W/p.s")"
        rewrite_gas "$b" < "$W/p.s" > "$W/q.s"
        "$b-unknown-linux-gnu-as" "$W/q.s" -o "$W/q.o" 2>/dev/null && "$b-unknown-linux-gnu-ld" "$W/q.o" -o "$W/q.elf" 2>/dev/null \
          || { printf '%s\t%s\tBUILD-FAIL\t-\t-\n' "$b" "$p"; continue; }
        runq "$(command -v "qemu-$b")" "$W/q.elf"; rc=$?
        if [ "$rc" -ge 1 ] && [ "$rc" -le "$n" ] && [ "$rc" -le 250 ]; then
          ln="$(gas_site_line "$b" "$rc" < "$W/p.s")"
          c="$(sed -n "${ln}p" "$W/p.s" | sed -E 's/^[[:space:]]*(brk #0|ebreak)[[:space:]]*((\/\/|#)[[:space:]]*)?//')"
          [ -n "$c" ] || c="(bare)"
          [ "$n" -gt 250 ] && c="$c [ambiguous: $n sites]"
          fn="$(head -n "$ln" "$W/p.s" | grep -E '^[A-Za-z_$][^ ]*:$' | tail -1)"
          printf '%s\t%s\tSITE\t%s\t%s\n' "$b" "$p" "$c" "${fn%:}"
        else
          printf '%s\t%s\tNOSITE\trc=%s sites=%s\t-\n' "$b" "$p" "$rc" "$n"
        fi ;;
      wasm)
        "$SITES_CC" wat "$p" > "$W/p.wat" 2>/dev/null || { printf '%s\t%s\tREJ\t-\t-\n' "$b" "$p"; continue; }
        n="$(wat_site_count < "$W/p.wat")"
        rewrite_wat < "$W/p.wat" > "$W/q.wat"
        wat2wasm "$W/q.wat" -o "$W/q.wasm" 2>/dev/null || { printf '%s\t%s\tBUILD-FAIL\t-\t-\n' "$b" "$p"; continue; }
        runq "$(command -v wasmtime)" -C cache=n "$W/q.wasm"; rc=$?
        if [ "$rc" -ge 1 ] && [ "$rc" -le "$n" ] && [ "$rc" -le 250 ]; then
          info="$(wat_site_info "$rc" < "$W/p.wat")"
          [ "$n" -gt 250 ] && info="${info%%	*} [ambiguous: $n sites]	${info#*	}"
          printf '%s\t%s\tSITE\t%s\n' "$b" "$p" "$info"
        else
          printf '%s\t%s\tNOSITE\trc=%s sites=%s\t-\n' "$b" "$p" "$rc" "$n"
        fi ;;
    esac
  done
  exit 0
fi

nrows=0; npaths=0; nhw=0
if [ -n "$ROWS" ]; then
  ## The headline counts what #683 must drive to zero; the documented hardware-defined rows are
  ## counted beside it, never silently dropped.
  nrows="$(printf '%s\n' "$ROWS" | awk -F'\t' '$1 != "HW-DEFINED"' | wc -l | tr -d ' ')"
  npaths="$(printf '%s\n' "$ROWS" | awk -F'\t' '$1 != "HW-DEFINED"' | cut -f3 | sort -u | wc -l | tr -d ' ')"
  nhw="$(printf '%s\n' "$ROWS" | awk -F'\t' '$1 == "HW-DEFINED"' | wc -l | tr -d ' ')"
fi
nsrc="$(awk -F'\t' '!/^#/ && NF >= 6 && $1 == "x86_64"' "$MANIFEST" | wc -l | tr -d ' ')"
echo "xbackend diff: paths=$npaths rows=$nrows sources=$nsrc hw-defined=$nhw"
[ -n "$ROWS" ] || exit 0

## A path's class is its highest-priority row's class.
PATHCLASS="$(printf '%s\n' "$ROWS" | awk -F'\t' -v ord="$CLASS_ORDER" '
  BEGIN { n = split(ord, o, " "); for (i = 1; i <= n; i++) r[o[i]] = i }
  { k = ($1 in r) ? r[$1] : 99; if (!($3 in best) || k < best[$3]) { best[$3] = k; cls[$3] = $1 } }
  END { for (p in cls) printf "%s\t%s\n", cls[p], p }')"

printf '  %-14s %6s %6s   %7s %7s %7s\n' class paths rows aarch64 riscv64 wasm
for c in $CLASS_ORDER UNCLASSIFIED; do
  r="$(printf '%s\n' "$ROWS" | awk -F'\t' -v c="$c" '$1 == c')"
  [ -n "$r" ] || continue
  pp="$(printf '%s\n' "$PATHCLASS" | awk -F'\t' -v c="$c" '$1 == c' | wc -l | tr -d ' ')"
  printf '  %-14s %6s %6s   %7s %7s %7s\n' "$c" "$pp" "$(printf '%s\n' "$r" | wc -l | tr -d ' ')" \
    "$(printf '%s\n' "$r" | awk -F'\t' '$2 == "aarch64"' | wc -l | tr -d ' ')" \
    "$(printf '%s\n' "$r" | awk -F'\t' '$2 == "riscv64"' | wc -l | tr -d ' ')" \
    "$(printf '%s\n' "$r" | awk -F'\t' '$2 == "wasm"' | wc -l | tr -d ' ')"
done
echo "  (paths: each path counted once, under its highest-priority class; rows: path x twin)"
[ "$MODE" = count ] && exit 0

## The table: every disagreeing path with all four states, so "agreed", "trapped" and "never ran"
## stay distinguishable. `*` marks the twin states that disagree with x86_64.
echo
for c in $CLASS_ORDER UNCLASSIFIED; do
  pp="$(printf '%s\n' "$PATHCLASS" | awk -F'\t' -v c="$c" '$1 == c' | cut -f2 | sort)"
  [ -n "$pp" ] || continue
  echo "## $c"
  printf '%s\n' "$pp" | while read -r p; do
    printf '%s\n' "$ROWS" | awk -F'\t' -v p="$p" '
      $3 == p { x = $4; t[$2] = $5 (($6 != "-") ? "(" $6 ")" : "") "*" }
      END { printf "  %-60s x86=%-5s", p, x
            split("aarch64 riscv64 wasm", b, " ")
            for (i = 1; i <= 3; i++) printf " %s=%-12s", b[i], ((b[i] in t) ? t[b[i]] : "=") ; printf "\n" }'
  done
done
exit 0
