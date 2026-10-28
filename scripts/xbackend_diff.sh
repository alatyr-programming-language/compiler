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
# ## The classes (per judged backend, against the REFERENCE row), in priority order
#
# The reference is x86_64 WHEN IT RAN. When x86_64 abstained (`compile/1`, a refusal), the reference
# is the FIRST twin, in the fixed order aarch64, riscv64, wasm, that answered a value quietly — and
# the tag names which backend that was. This is the owner's decision on #1014: a value disagreement
# between two backends is WRONG-VALUE no matter which backend abstained. Before it, the reference was
# hard-wired to x86_64, so every path x86_64 refused fell into ACCEPTS however much the twins
# disagreed, and `test/naked_a64.al` — aarch64 42, riscv64 40, a real silent wrong value — was
# invisible to the class. The reference is chosen by a fixed order, never by data, so the verdict is
# reproducible (FND-3) and does not depend on manifest row order.
#
# The backend column names the backend being JUDGED. On paths where the reference moved to a twin, that
# includes x86_64 itself: it is judged in a second pass, because it is not one of the twins and would
# otherwise never be compared with anything. A count that reaches zero by not looking at a backend does
# not mean zero disagreements (I4) — it means the counter went blind, which is exactly what the first
# cut of #1018 did to 10 over-refusal paths.
#
#   WRONG-VALUE   ref V<a>, twin V<b>, a != b, quiet       — the twin answers something else
#   MISSING-TRAP  ref K,    twin V<b>, quiet               — the reference refuses at run time, the twin answers
#   CRASH         ref V,    twin S                         — a fault, not a trap
#   LOUD-EXIT     ref V|K,  twin V<b> != ref, with stderr  — the RUNNER failed and said so. Measured
#                 on wasm: wasmtime exits 1 both for an `unknown import` at instantiation (an FFI or
#                 bodyless extern the twin cannot satisfy) and for `exit with invalid exit status
#                 outside of [0..126)` — a program whose exit value wasmtime refuses to deliver, which
#                 HIDES the value and so may itself be a wrong value. `--sites` prints which.
#   TRAP          ref V,    twin K                         — unimplemented lowering (fail-loud stub)
#   TIMEOUT       ref V|K,  twin T  (or the reverse)
#   ASSEMBLE      ref V|K,  twin A                         — the twin emitted text `as` refuses
#   LINK          ref V|K,  twin L                         — e.g. a runtime symbol the twin lacks
#   REFUSED       ref V|K,  backend C                      — the judged backend refuses to compile what the
#                                                            reference runs; the acceptable end state IF it is
#                                                            located. On x86_64 this is an OVER-refusal: three
#                                                            twins compiled and ran it (the #1014 fallback).
#   ACCEPTS       ref C,    twin V|K|S|T                   — a twin builds a program the reference refuses
#   HW-DEFINED    a MISSING-TRAP row on a path in the `HW_DEFINED` list below: `unchecked` division by
#                 zero / `MIN / -1`, which the specification makes target-specific (Concurrency §6.2).
#                 Listed and counted (`hw-defined=`), but not part of `paths=`/`rows=`.
#   RAW-ESCAPE    a WRONG-VALUE or MISSING-TRAP row on a path in the `RAW_ASM` list below: the
#                 disagreement is the target assembler's reading of text the raw escape passes to `as`
#                 VERBATIM (Assembly §4, Grammar §130 "only `as` validates"), not a lowering the
#                 compiler chose. Listed and counted (`raw-escape=`), never part of `paths=`/`rows=`.
#   N/A-TARGET    a row on a fixture that DECLARES the architecture its `asm()` body is written for
#                 (a `## @target(<arch>)` header line, read from the fixture itself by
#                 `xb_declared_targets`, #1041) where the judged backend is not that architecture.
#                 The fixture never claimed to answer there, so the divergence is the walk's question,
#                 not the compiler's. Counted (`target-na=`), never part of `paths=`/`rows=`, and
#                 NEVER applied on the declared target itself. Decided BEFORE RAW-ESCAPE: a fact in the
#                 file outranks a list maintained here, and the latter can drift from the former.
#
# Not a disagreement: equal states (V<a>/V<a>, K/K, C/C), and ref C against twin A, L or a loud
# exit — every backend refused, only at a different step. `--all` lists those as REFUSED-LATE.
#
# "quiet"/"loud" is the twin row's stderr digest: empty or not. A runner that exited and printed why
# is a loud failure, not a silent answer (#683's triage measured that split on the wasm column). When
# the reference is a twin, the tag carries ` ref=<backend>` as well, so a reader of `--rows` can see
# what the row was compared against without recomputing it.
# A path is listed under its highest-priority class; `--count` counts rows (path × twin) and paths.
#
# ## Usage
#
#   scripts/xbackend_diff.sh [--all] [--class C] [<manifest>]   per-path table, grouped by class
#   scripts/xbackend_diff.sh --count [<manifest>]               counts only, per class and backend
#   scripts/xbackend_diff.sh --rows [--all] [<manifest>]        machine rows: class TAB backend TAB path TAB ref TAB twin TAB tag
#       `ref` is the x86_64 state when x86_64 ran, otherwise the value of the twin taken as reference
#       (#1014); the tag then carries ` ref=<backend>` so the row says what it was judged against.
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
## The fixture-declaration oracle, shared with `ir_diff.sh` (#683): one reader of `## build_reject`
## and `## Expected exit: N`, because two readers of the same declaration drift apart — the very
## defect class the IR removes from the emitters, applied to the tools that judge the emitters.
. "$(dirname "${BASH_SOURCE[0]}")/fixture_oracle.sh"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

MODE=table
ALL=0
CLASS=""
SITES_CC=""
RATCHET=0
RATCHET_WRITE=0
RATCHET_FILE="$ROOT/scripts/xbackend_diff.baseline"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --count)     MODE=count; shift ;;
    --ratchet)   MODE=count; RATCHET=1; shift ;;
    --write)     RATCHET_WRITE=1; shift ;;
    --baseline)  [ "$#" -ge 2 ] || { echo "xbackend_diff: --baseline needs a file" >&2; exit 2; }
                 RATCHET_FILE="$2"; shift 2 ;;
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
CLASS_ORDER="WRONG-VALUE MISSING-TRAP CRASH LOUD-EXIT TRAP TIMEOUT ASSEMBLE LINK REFUSED ACCEPTS HW-DEFINED RAW-ESCAPE N/A-TARGET REFUSED-LATE"

## ── the documented raw-escape divergences ─────────────────────────────────────────────────────
## Specification (pin v1.1.0), Assembly §4 and the grammar's escape row:
##
##   §4  "The text outside placeholders is passed to `as` **verbatim**."
##   §4  "It is a **compile error** if a placeholder index has no operand, an operand is
##        unreferenced, or an operand is not a valid operand kind."   — and NOTHING else.
##   §130 "asm( string, expr, … ) — raw GAS escape (§4); requires an unchecked grant;
##         **only `as` validates**"
##
## So the raw escape is uncurated BY DEFINITION: the compiler checks the placeholder structure and
## hands the text to the target assembler, which is the only thing that decides what it means. The
## corpus shows the rule working — of the 13 fixtures that use the escape with a foreign arch's
## mnemonics, 12 land in ASSEMBLE because `as` refuses them, exactly as §4 says it is the one that
## validates. `test/naked_a64.al` is the thirteenth: `add x0, x0, x1` is AArch64 intent written in
## a spelling RISC-V's assembler ALSO accepts, where x0 is the hardwired zero register — so it
## assembles, does nothing, and `ret` leaves a0 at 40. The compiler refused nothing it should have
## and emitted nothing it was told not to; a LOCATED refusal is impossible here without an arch
## validator the spec forbids ("only `as` validates"), and a `when(target.arch == …)` gate would
## leave `main` calling an unresolved function, which is a refusal no one wrote.
##
## This is NOT hidden: the row keeps printing, under RAW-ESCAPE, and is counted on the headline as
## `raw-escape=`; it leaves only `paths=`/`rows=`, the count #683 drives to ZERO, because it is not
## a divergence the compiler can close. Add a path here ONLY with a fixture whose disagreement is the
## assembler's reading of raw text — never for a path where the compiler chose a wrong lowering.
RAW_ASM='test/naked_a64.al'

## Fixtures that DECLARE the architecture their `asm()` body is written for. The declaration is read
## from the FIXTURE's own header — a machine-readable `## @target(<arch>)` line — and never from a list
## here, so the claim cannot drift from the file it describes (#1041, owner's decision: respect the
## fixture's declared target). Why this is not an exemption of convenience: `spec/80-assembly.md` §4
## and CG-3 say the raw escape "needs an `unchecked` grant and is validated only by `as`, with none of
## the compiler's checks or guards". So when riscv64 assembles AArch64 text — `add x0,x0,x1` is legal
## RV64, x0/x1 being aliases for zero/ra — and answers 40 where AArch64 answers 42, the compiler
## conformed and the fixture, which declares "on AArch64", was asked a question it never claimed to
## answer. The divergence is the walk's, not the compiler's, and it is reported as `N/A-TARGET`:
## visible in the table, counted on the headline as `target-na=`, excluded from `paths=`/`rows=`.
## A fixture with no marker is judged on every backend exactly as before; this widens nothing.
xb_declared_targets() { # — path TAB arch, for each declaring fixture; paths are relative
  ## ONE grep over the glob, not two processes per fixture: the loop form cost ~3 800 subprocesses
  ## and took the self-test from 1 s to 148 s, because `xb_rows` calls this on every invocation.
  ## Output is byte-identical (path TAB arch, manifest-relative), measured ~95x faster.
  ## ONE awk process over the glob, header-scoped, through the single fixture-declaration reader
  ## (`oracle_targets` in fixture_oracle.sh) — not a second copy of the pattern here, and not two
  ## subprocesses per fixture (that cost ~3 800 processes and 147 s of self-test time).
  ( cd "$ROOT" && oracle_targets test/*.al )
  return 0
}

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
xb_ratchet() { # baseline-file paths rows hw-defined raw-escape unexplained target-na — 0 held, 1 GREW, 2 unusable
  ## The ratchet (#922): the counters used to be REPORTING ONLY — `--count` ended in `exit 0`
  ## whatever it had just printed, so a PR that ADDED a cross-backend disagreement passed the gate
  ## and the only trace was a number in a log nobody reads. That is how `paths` reached 950.
  ## This holds the line WITHOUT pretending the backlog is empty: the count may not GROW, and it
  ## never demands zero. The 833 TRAP paths are unimplemented lowerings (IR slices 3–8), not
  ## defects this change introduced; demanding zero today would make the gate permanently red and
  ## teach everyone to ignore it, which is the failure mode being repaired.
  ## `unexplained` (#683, criterion 3) is the ONE counter that DOES demand zero, and it is held
  ## separately for that reason: a quiet normal-exit disagreement that nothing declares is a program
  ## two backends answer differently with no stated cause, which is not a backlog item but a live wrong
  ## value. Documented hardware-defined rows never reach it (they are filtered before it is counted).
  local f="$1" bp br bh bn bu bt mut_note
  [ -s "$f" ] || { echo "xbackend ratchet: NO baseline at $f — a ratchet cannot hold a line it does" \
    ; echo "  not have. Write one with: scripts/xbackend_diff.sh --ratchet --write" >&2; return 2; }
  bp="$(awk -F= '/^paths=/{print $2}' "$f" | head -1)"
  br="$(awk -F= '/^rows=/{print $2}' "$f" | head -1)"
  bh="$(awk -F= '/^hw-defined=/{print $2}' "$f" | head -1)"
  ## `raw-escape=` arrived with this class, so an older baseline simply has none of them recorded:
  ## absent reads as 0, which is the strictest reading (any path newly claimed is then reported).
  bn="$(awk -F= '/^raw-escape=/{print $2}' "$f" | head -1)"; bn="${bn:-0}"
  bu="$(awk -F= '/^unexplained=/{print $2}' "$f" | head -1)"; bu="${bu:-0}"
  bt="$(awk -F= '/^target-na=/{print $2}' "$f" | head -1)"; bt="${bt:-0}"
  case "$bp$br$bh$bn$bu$bt" in ''|*[!0-9]*) echo "xbackend ratchet: baseline at $f is malformed" >&2; return 2 ;; esac
  ## `target-na=` is held OUTSIDE the paths/rows condition, and that placement is the whole point
  ## (#1041). A fixture newly declaring `## @target(aarch64)` makes its foreign-backend rows leave
  ## `paths=` and `rows=` — the numbers go DOWN, so a check that fires only on growth never sees it,
  ## and the counter would reach zero by the walk asking fewer questions. That is I4's blind-counter
  ## failure in a new costume: the exemption is a claim written into a fixture by the same person
  ## whose disagreement it excuses, so a new one is a review event, not a quiet win. The declared
  ## target itself stays judged either way (Assembly §4 / CG-3).
  mut_note=0
  case "${7:-}" in ''|*[!0-9]*) ;; *) mut_note="${7}" ;; esac
  if [ "$mut_note" -gt "$bt" ]; then
    echo "xbackend ratchet: FAIL — target-na GREW past the baseline ($bt -> $mut_note)."
    echo "  A fixture that newly declares a target stops being judged on the other three backends."
    echo "  Legitimate ONLY where its asm() body really is written for the declared arch: name the"
    echo "  fixture and the arch in review, or fix the disagreement on the declared target."
    return 1
  fi
  ## The unexplained ceiling first, and it fails on its own: a growing backlog that happens to shrink
  ## `paths` must not carry a live wrong value past the gate.
  if [ "${6:-0}" -gt "$bu" ]; then
    echo "xbackend ratchet: FAIL — UNEXPLAINED quiet disagreements GREW $bu -> ${6:-0}."
    echo "  A backend exited NORMALLY, quietly, with an answer different from the reference's, and neither"
    echo "  the fixture's header nor a hardware-defined citation says why. Criterion 3 holds this at zero:"
    echo "  fix the lowering, refuse it at compile time with a located diagnostic, or declare the expected"
    echo "  exit in the fixture — do NOT raise this ceiling."
    return 1
  fi
  if [ "$2" -gt "$bp" ] || [ "$3" -gt "$br" ]; then
    echo "xbackend ratchet: FAIL — the disagreement count GREW past the baseline."
    echo "    paths $bp -> $2   rows $br -> $3"
    if [ "$4" -gt "$bh" ]; then
      echo "    hw-defined $bh -> $4 — a row newly claimed hardware-defined is a documented platform"
      echo "      difference, not a fix; justify it in review."
    fi
    if [ "$5" -gt "$bn" ]; then
      echo "    raw-escape $bn -> $5 — a row newly claimed RAW-ESCAPE leaves `paths=` on the strength"
      echo "      of Assembly §4 (\"only \`as\` validates\"). That is a real exemption only while the"
      echo "      disagreement IS the assembler's reading of verbatim text; justify it in review."
    fi
    echo "  Each new path is a program that answers differently on two backends (#683). Either fix"
    echo "  the lowering, or refuse it at compile time with a located diagnostic. Do NOT raise the"
    echo "  baseline to make this pass."
    return 1
  fi
  if [ "$2" -lt "$bp" ] || [ "$3" -lt "$br" ]; then
    echo "xbackend ratchet: held, and LOWER than the baseline ($bp -> $2 paths, $br -> $3 rows)."
    echo "  Lower the baseline so the next change cannot creep back up:"
    echo "      scripts/xbackend_diff.sh --ratchet --write"
    return 0
  fi
  echo "xbackend ratchet: held at the baseline ($bp paths, $br rows)."
  return 0
}

xb_rows() { # manifest all [hw-defined-list] [raw-escape-list] [declared-target-list]
  ## The declared-target list is the FIFTH argument, not the fourth: #1050 first took the fourth slot
  ## for it while main had already taken that slot for the raw-escape list (#683). Two meanings in one
  ## positional slot is how a judging tool silently judges the wrong thing.
  awk -F'\t' -v all="$2" -v empty="$SHA_EMPTY" -v hwl="$(printf '%s' "${3-$HW_DEFINED}" | tr '\n' ' ')" -v rawl="$(printf '%s' "${4-$RAW_ASM}" | tr '\n' ' ')" \
      -v tdl="$(printf '%s' "${5-$(xb_declared_targets)}" | tr '\n' '|')" '
    BEGIN { nh = split(hwl, hl, " "); for (i = 1; i <= nh; i++) if (hl[i] != "") hw[hl[i]] = 1
            nr = split(rawl, rl, " "); for (i = 1; i <= nr; i++) if (rl[i] != "") raw[rl[i]] = 1
            nt = split(tdl, tl, "|"); for (i = 1; i <= nt; i++) { if (tl[i] == "") continue
              split(tl[i], kv, "\t"); if (kv[1] != "" && kv[2] != "") td[kv[1]] = kv[2] } }
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
        ## THE REFERENCE (#1014). x86_64 when it ran. When it abstained (compile/1), the first twin
        ## in this FIXED order that answered a value QUIETLY — a loud exit is a runner failure that
        ## hid its value, not an answer to compare against. Fixed order, never data: the verdict is
        ## reproducible and does not depend on manifest row order (FND-3).
        ref = x; refbe = "x86_64"
        if (x == "C") {
          for (j = 1; j <= 3; j++) {
            b = tw[j]; k = p "\t" b
            if ((k in st) && st[k] ~ /^V/ && se[k] == empty) { ref = st[k]; refbe = b; break }
          }
        }
        for (j = 1; j <= 3; j++) {
          b = tw[j]; k = p "\t" b
          if (!(k in st)) continue
          if (b == refbe) continue
          c = klass(ref, st[k], se[k] != empty)
          if (c == "MISSING-TRAP" && (p in hw)) c = "HW-DEFINED"
          ## A fixture that declares its target is not judged on a foreign one (#1041); decided before
          ## RAW-ESCAPE so the source-declared class names the row. On the declared target it IS judged.
          ## Scoped to the shapes the declaration actually excuses — the precedent in this file:
          ## HW-DEFINED applies ONLY to MISSING-TRAP, RAW-ESCAPE only to WRONG-VALUE|MISSING-TRAP.
          ## `@target(aarch64)` says the asm() body is AArch64 GAS; what that excuses is the FOREIGN
          ## FOREIGN ASSEMBLER reading of that verbatim text — a wrong value, a missing trap, or `as`
          ## refusing it. It does NOT excuse decisions the compiler made itself on a foreign backend:
          ## (wasm running where CG-4 wants a compile error), REFUSED (the #1014 over-refusal queue),
          ## CRASH and TIMEOUT stay judged. `c != ""` keeps AGREEING backends out of the table —
          ## without it, FIXING a foreign lowering prints a row and grows `target-na=`, failing the
          ## ratchet for having fixed a bug.
          if ((p in td) && b != td[p] && c != "" && (c == "WRONG-VALUE" || c == "MISSING-TRAP" || c == "ASSEMBLE")) {
            printf "%s\t%s\t%s\t%s\t%s\tdeclared=%s\n", "N/A-TARGET", b, p, ref, st[k], td[p]; continue
          }
          ## A raw-escape path is a disagreement over how the assembler reads verbatim text (§4),
          ## not a lowering the compiler chose; the row keeps printing under its own class and only
          ## leaves `paths=`, the count #683 drives to zero.
          if ((c == "WRONG-VALUE" || c == "MISSING-TRAP") && (p in raw)) c = "RAW-ESCAPE"
          if (c == "" || (c == "REFUSED-LATE" && all != 1)) continue
          tag = (st[k] ~ /^V/) ? ((se[k] == empty) ? "quiet" : "loud") : "-"
          if (refbe != "x86_64") tag = tag " ref=" refbe
          printf "%s\t%s\t%s\t%s\t%s\t%s\n", c, b, p, ref, st[k], tag
        }
        ## ...AND x86_64 ITSELF, when the reference moved away from it. x86_64 is not in `tw`: it is
        ## only ever the reference, so the loop above never judges it. Without this second step a path
        ## where x86_64 refuses and the three twins agree on one quiet value produces NO row at all and
        ## leaves the counter — ten such paths did when #1018 first landed, and they are the over-
        ## refusals the corpus names for what they are (`accept_issue623_nested_array_field_store`,
        ## `packed_ret_value`, …): three backends compile and run it, x86_64 will not. A count that
        ## reaches zero by not looking at a backend does not mean zero disagreements (I4); it means the
        ## counter went blind. So x86_64 is judged against the reference like any other backend, and the
        ## REFUSED row names the backend that actually refused — which the old ACCEPTS rows, blaming a
        ## twin for the abstention of x86_64, did not.
        if (refbe != "x86_64") {
          k = p "\t" "x86_64"
          c = klass(ref, x, se[k] != empty)
          if (c == "MISSING-TRAP" && (p in hw)) c = "HW-DEFINED"
          ## `continue`, NOT `next`: this block sits inside the `for (i)` loop in awk END, and
          ## `next` from END is illegal — awk aborts the whole program (rc=2) at the FIRST declaring
          ## fixture, silently dropping every later path while `unexplained=0` still prints. The
          ## self-test missed it because every planted declaring manifest holds ONE path, so the
          ## abort lands after the asserted row; the two-path case below is what catches it.
          if ((p in td) && td[p] != "x86_64" && c != "" && (c == "WRONG-VALUE" || c == "MISSING-TRAP" || c == "ASSEMBLE")) {
            printf "%s\t%s\t%s\t%s\t%s\tdeclared=%s\n", "N/A-TARGET", "x86_64", p, ref, x, td[p]
            continue
          }
          ## A raw-escape path is a disagreement over how the assembler reads verbatim text (§4),
          ## not a lowering the compiler chose; the row keeps printing under its own class and only
          ## leaves `paths=`, the count #683 drives to zero.
          if ((c == "WRONG-VALUE" || c == "MISSING-TRAP") && (p in raw)) c = "RAW-ESCAPE"
          if (c != "" && !(c == "REFUSED-LATE" && all != 1))
            printf "%s\t%s\t%s\t%s\t%s\t%s\n", c, "x86_64", p, ref, x,
              ((x ~ /^V/) ? ((se[k] == empty) ? "quiet" : "loud") : "-") " ref=" refbe
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
  ok "x86 refuses and NO twin answers quietly: both are ACCEPTS (#1014 keeps this)" \
     "$(rows_of "$(q x86_64 compile 1)" "$(q aarch64 run 133)" "$(q wasm run 134)")" "ACCEPTS:aarch64 ACCEPTS:wasm"
  ## THE TWIN REFERENCE (#1014, owner decision). When x86_64 abstains, the reference is the FIRST
  ## twin in the fixed order that answered a value QUIETLY, and the remaining twins are judged
  ## against IT. Before this, every path x86_64 refused fell into ACCEPTS however much the twins
  ## disagreed — `test/naked_a64.al` (aarch64 42, riscv64 40) was invisible to WRONG-VALUE.
  ok "x86 abstains, twins disagree on a value: WRONG-VALUE, not ACCEPTS" \
     "$(rows_of "$(q x86_64 compile 1)" "$(q aarch64 run 42)" "$(q riscv64 run 40)")" \
     "WRONG-VALUE:riscv64 REFUSED:x86_64"
  ok "a twin that traps where the reference answers is TRAP, not ACCEPTS" \
     "$(rows_of "$(q x86_64 compile 1)" "$(q aarch64 run 7)" "$(q wasm run 134)")" "TRAP:wasm REFUSED:x86_64"
  ## x86_64 is never in `tw`, so it is judged in a second step (see the END block): its refusal is a
  ## disagreement with the twin that ran, and it names the backend that actually refused. Without that
  ## step, a path where x86 refuses and the twins AGREE produces no row at all and leaves the counter —
  ## ten such paths did on the first cut of #1018, all of them over-refusals (`packed_ret_value`,
  ## `accept_issue623_nested_array_field_store`, …): three backends compile and run it, x86_64 will not.
  ## A count that reaches zero by not looking at a backend is not a count of zero disagreements (I4).
  ok "twins agreeing while x86 abstains: the twins are silent, the refusal of x86 is NOT" \
     "$(rows_of "$(q x86_64 compile 1)" "$(q aarch64 run 42)" "$(q riscv64 run 42)" "$(q wasm run 42)")" \
     "REFUSED:x86_64"
  ok "...and the row names the twin it refused, so the reader knows what x86_64 said no to" \
     "$(printf '%s\n' "$H" "$(q x86_64 compile 1)" "$(q aarch64 run 42)" "$(q riscv64 run 42)" "$(q wasm run 42)" > "$T/m2"; xb_rows "$T/m2" 0 | awk -F'\t' '$2 == "x86_64" { print $1 "\t" $4 "\t" $5 "\t" $6 }')" \
     "REFUSED	V42	C	- ref=aarch64"
  ## The reference is chosen by FIXED ORDER, never by data, so the verdict does not depend on the
  ## order of rows in the manifest (FND-3). A LOUD twin is never the reference: a runner that
  ## printed why it failed hid its value, so it cannot vouch for one.
  ok "the reference is the first QUIET value in fixed order, not the first row" \
     "$(rows_of "$(q x86_64 compile 1)" "$(q wasm run 9)" "$(q aarch64 run 42)")" \
     "WRONG-VALUE:wasm REFUSED:x86_64"
  ## The row says WHICH backend the value was compared against, so a reader can tell that the
  ## reference was aarch64 and not the x86_64 that abstained.
  printf '%s\n' "$H" "$(q x86_64 compile 1)" "$(q wasm run 9)" "$(q aarch64 run 42)" > "$T/m"
  ok "...and the row names the backend it was compared against" \
     "$(xb_rows "$T/m" 0 | awk -F'\t' '$1 == "WRONG-VALUE" { print $2 "\t" $4 "\t" $5 "\t" $6 }')" \
     "wasm	V42	V9	quiet ref=aarch64"
  ok "a loud twin cannot be the reference: a quiet one is, and the loud one is LOUD-EXIT" \
     "$(rows_of "$(q x86_64 compile 1)" "$(q aarch64 run 42 "$L")" "$(q riscv64 run 41)")" \
     "LOUD-EXIT:aarch64 REFUSED:x86_64"
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
  ## RAW-ESCAPE (#683, Assembly §4): the assembler decides what verbatim text MEANS, so a twin
  ## that assembles a foreign arch's mnemonic and answers a different value is not a lowering the
  ## compiler chose wrong. The row survives, under its own class; only `paths=` lets it go.
  rq() { printf '%s\t%s\t%s\t%s\t%s\t%s' "$1" test/raw.al "$2" "$3" "$E" "$E"; }
  printf '%s\n' "$H" "$(rq x86_64 compile 1)" "$(rq aarch64 run 42)" "$(rq riscv64 run 40)" "$(rq wasm run 134)" > "$T/m"
  ok "a listed raw-escape path is RAW-ESCAPE, not WRONG-VALUE" \
     "$(xb_rows "$T/m" 0 '' test/raw.al | awk -F'\t' '$1 != "REFUSED" { print $1 "\t" $2 "\t" $5 }' | tr '\n' ' ' | sed 's/ $//' | tr '\t' ':')" \
     "RAW-ESCAPE:riscv64:V40 TRAP:wasm:K"
  ok "... and the same row unlisted stays WRONG-VALUE" \
     "$(xb_rows "$T/m" 0 '' test/other.al | awk -F'\t' '$1 != "REFUSED" { print $1 "\t" $2 }' | tr '\n' ' ' | sed 's/ $//' | tr '\t' ':')" \
     "WRONG-VALUE:riscv64 TRAP:wasm"
  ## The exemption is the assembler's reading and NOTHING else: a twin that faults, or that traps
  ## where the reference answered, keeps its class even on a listed path.
  printf '%s\n' "$H" "$(rq x86_64 run 42)" "$(rq riscv64 run 139)" > "$T/m"
  ok "the raw-escape list never excuses a crash" \
     "$(xb_rows "$T/m" 0 '' test/raw.al | cut -f1,2 | tr '\t\n' ': ' | sed 's/ $//')" "CRASH:riscv64"
  printf '%s\n' "$H" "$(rq x86_64 run 132)" "$(rq riscv64 run 40)" > "$T/m"
  ok "a listed raw path excuses a MISSING-TRAP too, since §4 is about the text, not the trap" \
     "$(xb_rows "$T/m" 0 '' test/raw.al | cut -f1,2 | tr '\t\n' ': ' | sed 's/ $//')" "RAW-ESCAPE:riscv64"
  ok "the committed raw-escape list names only fixtures that exist" \
     "$(printf '%s\n' "$RAW_ASM" | while read -r f; do [ -f "$ROOT/$f" ] || echo "$f"; done)" ""
  ## A fixture that DECLARES its target is not judged on a foreign one (#1041) — and IS judged on the
  ## target it declared. Both directions are driven, or the exemption would be a rubber stamp: a marker
  ## that excused every backend would empty the counter by making the counter blind, which is exactly
  ## what the reference rule at #1014 refuses.
  tq() { printf '%s\t%s\t%s\t%s\t%s\t%s' "$1" test/decl.al "$2" "$3" "$E" "$E"; }
  printf '%s\n' "$H" "$(tq x86_64 compile 1)" "$(tq aarch64 run 42)" "$(tq riscv64 run 40)" "$(tq wasm run 134)" > "$T/m"
  ok "a foreign-target pair is N/A-TARGET while the DECLARED target is still judged" \
     "$(xb_rows "$T/m" 0 "" "" "test/decl.al	riscv64" | cut -f1,2 | tr '\t\n' ': ' | sed 's/ $//')" \
     "WRONG-VALUE:riscv64 TRAP:wasm REFUSED:x86_64"
  ok "... and on a fixture declaring aarch64, every other backend is N/A-TARGET" \
     "$(xb_rows "$T/m" 0 "" "" "test/decl.al	aarch64" | cut -f1,2 | sort | tr '\t\n' ': ' | sed 's/ $//')" \
     "N/A-TARGET:riscv64 REFUSED:x86_64 TRAP:wasm"
  printf '%s\n' "$H" "$(tq x86_64 run 42)" "$(tq aarch64 run 41)" > "$T/m"
  ok "the marker never excuses a wrong value ON the target it declares" \
     "$(xb_rows "$T/m" 0 "" "" "test/decl.al	aarch64" | cut -f1,2 | tr '\t\n' ': ' | sed 's/ $//')" \
     "WRONG-VALUE:aarch64"
  printf '%s\n' "$H" "$(tq x86_64 compile 1)" "$(tq aarch64 run 42)" "$(tq riscv64 run 40)" "$(tq wasm run 134)" > "$T/m"
  ok "... and an UNMARKED fixture is judged on every backend, unchanged" \
     "$(xb_rows "$T/m" 0 | cut -f1,2 | sort | tr '\t\n' ': ' | sed 's/ $//')" \
     "REFUSED:x86_64 TRAP:wasm WRONG-VALUE:riscv64"
  ## TWO-PATH case — the blind spot that hid an illegal `next` in awk END (#1041). Every other
  ## planted declaring manifest here holds ONE path, so an abort inside the END loop lands AFTER the
  ## asserted row: the check passes, the join is truncated, and `unexplained=0` still prints over half
  ## the corpus never examined. Here a second disagreeing path FOLLOWS the declaring fixture, so a
  ## truncation loses rows this check asserts on.
  q2() { printf '%s\t%s\t%s\t%s\t%s\t%s' "$1" test/p.al "$2" "$3" "$E" "$E"; }
  ## x86_64 is the reference here, so the exemption fires in the TWIN loop — the reachable site.
  ## (Two earlier versions of this case were vacuous and are recorded as such: one made x86_64 the
  ## reference with a plain value, so the exempt branch never ran; the other made x86_64 refuse, and
  ## REFUSED is deliberately NOT excused — it is the #1014 over-refusal queue.)
  printf '%s\n' "$H" "$(tq x86_64 run 42)" "$(tq aarch64 run 99)" "$(tq riscv64 run 40)" \
    "$(q2 x86_64 run 42)" "$(q2 aarch64 run 7)" > "$T/m2"
  ok "a disagreeing path AFTER a declaring fixture is still judged (END must not abort)" \
     "$(xb_rows "$T/m2" 0 "" "" "test/decl.al\triscv64" | grep -c 'test/p.al')" "1"
  ok "... and xb_rows exits 0 — a truncated join must not pass silently" \
     "$(xb_rows "$T/m2" 0 "" "" "test/decl.al\triscv64" >/dev/null 2>&1; echo $?)" "0"
  ok "... and the declaring fixture really reached the exempt path (the case is not vacuous)" \
     "$(xb_rows "$T/m2" 0 "" "" "test/decl.al\triscv64" | awk -F'\t' '$3=="test/decl.al" && $2=="aarch64" {print $1}')" \
     "N/A-TARGET"
  ## ASSEMBLE IS excused: `as` refusing foreign text is the walk asking a question the fixture never
  ## claimed to answer (Assembly §4 — only `as` validates). TRAP is NOT (CG-4: on a structured
  ## backend asm is a compile error, not a runtime trap) — asserted above via wasm.
  printf '%s\n' "$H" "$(tq x86_64 run 42)" "$(tq riscv64 assemble 1)" > "$T/m3"
  ok "a declared target excuses ASSEMBLE on the foreign backend" \
     "$(xb_rows "$T/m3" 0 "" "" "test/decl.al\taarch64" | awk -F'\t' '$2=="riscv64" {print $1}')" \
     "N/A-TARGET"
  ok "the declarations read from the fixtures name only existing fixtures and a known arch" \
     "$(xb_declared_targets | while IFS=$'\t' read -r p a; do
          { [ -f "$ROOT/$p" ] && case "$a" in x86_64|aarch64|riscv64|wasm) ;; *) echo "bad-arch $p";; esac; } || echo "missing $p"
        done)" ""
  ok "every declaring fixture carries its marker in the header, not in a list here" \
     "$(xb_declared_targets | while IFS=$'\t' read -r p a; do
          grep -qE "^##[[:space:]]*@target\($a\)" "$ROOT/$p" || echo "drift $p ($a)"
        done)" ""
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
  ## The ratchet (#922): it must fail on growth, hold at the line, and refuse to hold nothing.
  printf 'paths=10\nrows=20\nhw-defined=1\nraw-escape=1\n' > "$T/base"
  ok "ratchet: held at the line"        "$(xb_ratchet "$T/base" 10 20 1 1 >/dev/null; echo $?)" 0
  ok "ratchet: held when LOWER"         "$(xb_ratchet "$T/base" 9 18 1 1 >/dev/null; echo $?)" 0
  ok "ratchet: FAIL on one more path"   "$(xb_ratchet "$T/base" 11 20 1 1 >/dev/null; echo $?)" 1
  ok "ratchet: FAIL on one more row"    "$(xb_ratchet "$T/base" 10 21 1 1 >/dev/null; echo $?)" 1
  ok "ratchet: a missing baseline is not a pass" "$(xb_ratchet "$T/nope" 10 20 1 1 >/dev/null 2>&1; echo $?)" 2
  ## An older baseline records no raw-escape: absent reads as ZERO, so a path newly claimed
  ## RAW-ESCAPE against it is still reported rather than passing unseen.
  printf 'paths=10\nrows=20\nhw-defined=1\n' > "$T/old"
  ok "ratchet: a pre-raw-escape baseline holds at 0" "$(xb_ratchet "$T/old" 10 20 1 0 >/dev/null; echo $?)" 0
  printf 'paths=abc\nrows=20\nhw-defined=1\n' > "$T/bad"
  ok "ratchet: a malformed baseline is not a pass" "$(xb_ratchet "$T/bad" 10 20 1 1 >/dev/null 2>&1; echo $?)" 2
  ## The UNEXPLAINED ceiling (#683, criterion 3) — the one counter that demands zero, and it fails on
  ## its own: a change that shrinks the backlog while introducing ONE quiet wrong value must not pass.
  printf 'paths=10\nrows=20\nhw-defined=1\nraw-escape=1\nunexplained=0\n' > "$T/u"
  ok "ratchet: unexplained held at zero"        "$(xb_ratchet "$T/u" 10 20 1 1 0 >/dev/null; echo $?)" 0
  ok "ratchet: unexplained FAIL on one more"    "$(xb_ratchet "$T/u" 10 20 1 1 1 >/dev/null; echo $?)" 1
  ok "ratchet: one quiet wrong value fails even when paths and rows SHRINK" \
     "$(xb_ratchet "$T/u" 4 8 1 1 1 >/dev/null; echo $?)" 1
  ## A baseline predating this counter reads as ZERO — the strictest reading, so a quiet wrong value
  ## introduced after it cannot pass unseen because the line was never drawn.
  ok "ratchet: a pre-unexplained baseline holds at 0" "$(xb_ratchet "$T/base" 10 20 1 1 0 >/dev/null; echo $?)" 0
  ok "ratchet: a pre-unexplained baseline FAILS on one" "$(xb_ratchet "$T/base" 10 20 1 1 1 >/dev/null; echo $?)" 1
  ## target-na is held even while paths/rows SHRINK — the exemption itself is what is watched (#1041)
  printf 'paths=10\nrows=20\nhw-defined=1\nraw-escape=1\nunexplained=0\ntarget-na=2\n' > "$T/tn"
  ok "ratchet: target-na held at the line"      "$(xb_ratchet "$T/tn" 10 20 1 1 0 2 >/dev/null; echo $?)" 0
  ok "ratchet: target-na FAILS on one more"     "$(xb_ratchet "$T/tn" 10 20 1 1 0 3 >/dev/null 2>&1; echo $?)" 1
  ok "ratchet: a newly declared target FAILS even as paths and rows SHRINK" \
     "$(xb_ratchet "$T/tn" 4 8 1 1 0 3 >/dev/null 2>&1; echo $?)" 1
  ok "ratchet: a pre-declaration baseline holds at 0" "$(xb_ratchet "$T/base" 10 20 1 1 0 0 >/dev/null; echo $?)" 0
  ok "ratchet: a pre-declaration baseline FAILS on one declared fixture" \
     "$(xb_ratchet "$T/base" 10 20 1 1 0 1 >/dev/null 2>&1; echo $?)" 1
  if [ "$fails" = 0 ]; then echo "xbackend_diff self-test: $ran/$ran ok"; exit 0; fi
  echo "xbackend_diff self-test: $fails of $ran check(s) FAILED — this script's output proves nothing"
  exit 3
fi

[ -s "$MANIFEST" ] && grep -q '^columns=' "$MANIFEST" || {
  echo "xbackend_diff: no usable manifest at $MANIFEST (expected a 'columns=' header)" >&2; exit 2; }

ROWS="$(xb_rows "$MANIFEST" "$ALL")" || { echo "xbackend diff: FAIL — the join aborted (rc=$?); every count below is TRUNCATED, not clean" >&2; exit 3; }
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

nrows=0; npaths=0; nhw=0; nraw=0; ntna=0
if [ -n "$ROWS" ]; then
  ## The headline counts what #683 must drive to zero; the documented hardware-defined and raw-escape
  ## rows are counted beside it, never silently dropped.
  nrows="$(printf '%s\n' "$ROWS" | awk -F'\t' '$1 != "HW-DEFINED" && $1 != "RAW-ESCAPE" && $1 != "N/A-TARGET"' | wc -l | tr -d ' ')"
  npaths="$(printf '%s\n' "$ROWS" | awk -F'\t' '$1 != "HW-DEFINED" && $1 != "RAW-ESCAPE" && $1 != "N/A-TARGET"' | cut -f3 | sort -u | wc -l | tr -d ' ')"
  nhw="$(printf '%s\n' "$ROWS" | awk -F'\t' '$1 == "HW-DEFINED"' | wc -l | tr -d ' ')"
  nraw="$(printf '%s\n' "$ROWS" | awk -F'\t' '$1 == "RAW-ESCAPE"' | wc -l | tr -d ' ')"
  ntna="$(printf '%s\n' "$ROWS" | awk -F'\t' '$1 == "N/A-TARGET"' | wc -l | tr -d ' ')"
fi
nsrc="$(awk -F'\t' '!/^#/ && NF >= 6 && $1 == "x86_64"' "$MANIFEST" | wc -l | tr -d ' ')"
## ── attribution: which disagreements does something already explain? (#683, criterion 3) ──────────
## `paths=`/`rows=` is #683's elimination queue and it counts a TRAP on a twin as a disagreement, which
## AGENTS.md explicitly permits ("a trap is acceptable, a wrong value is not"). Criterion 3 asks a
## different question, and conflating the two is how a gate either cries wolf or says nothing: it wants
## ZERO *unexplained* disagreements, with only documented hardware-defined ones remaining. So the quiet
## rows are attributed here, row by row:
##   HW-DEFINED / RAW-ESCAPE  — documented in this script, by spec citation, and excluded from paths=.
##   DECLARED                 — the fixture's own header states this exit code (`oracle`, shared with
##                              ir_diff through scripts/fixture_oracle.sh). The file said it would.
##   UNEXPLAINED              — a backend exited NORMALLY, quietly, with an answer different from the
##                              reference's, and nothing says why. THIS is the number criterion 3 drives
##                              to zero and the gate holds; a trap, a refusal and an assembler complaint are
##                              loud and are not in it.
nquiet=0; nattrib=0; nunexpl=0
if [ -n "$ROWS" ]; then
  while IFS=$'\t' read -r rcls rbe rpath rref rst rtag; do
    [ "$rtag" = quiet ] || continue
    ## N/A-TARGET is explained by the fixture's own header; the other two by spec citations here.
    case "$rcls" in HW-DEFINED|RAW-ESCAPE|N/A-TARGET) continue ;; esac
    nquiet=$((nquiet + 1))
    if oracle_explains "$rpath" "${rst#V}"; then
      nattrib=$((nattrib + 1))
    else
      nunexpl=$((nunexpl + 1))
      printf '  UNEXPLAINED %s  %s answered %s where the reference answered otherwise, quietly  (oracle: %s)\n' \
        "$rpath" "$rbe" "$rst" "$(oracle "$rpath")"
    fi
  done <<< "$ROWS"
fi
echo "xbackend diff: paths=$npaths rows=$nrows sources=$nsrc hw-defined=$nhw raw-escape=$nraw target-na=$ntna quiet=$nquiet attributed=$nattrib unexplained=$nunexpl"
if [ "$RATCHET_WRITE" = 1 ]; then
  ## Writing the baseline is a deliberate, reviewable act: it moves the line the gate holds. The
  ## file records the manifest it was measured from, so a baseline cannot be moved without the
  ## manifest that justifies it being in the same diff.
  printf 'paths=%s\nrows=%s\nhw-defined=%s\nraw-escape=%s\ntarget-na=%s\nunexplained=%s\n' "$npaths" "$nrows" "$nhw" "$nraw" "$ntna" "$nunexpl" > "$RATCHET_FILE" || exit 2
  echo "xbackend ratchet: WROTE $RATCHET_FILE (paths=$npaths rows=$nrows hw-defined=$nhw raw-escape=$nraw)"
  exit 0
fi
if [ "$RATCHET" = 1 ]; then
  xb_ratchet "$RATCHET_FILE" "$npaths" "$nrows" "$nhw" "$nraw" "$nunexpl" "$ntna"
  rc=$?
  [ "$MODE" = count ] && exit $rc
fi
[ -n "$ROWS" ] || exit 0

## A path's class is its highest-priority row's class.
PATHCLASS="$(printf '%s\n' "$ROWS" | awk -F'\t' -v ord="$CLASS_ORDER" '
  BEGIN { n = split(ord, o, " "); for (i = 1; i <= n; i++) r[o[i]] = i }
  { k = ($1 in r) ? r[$1] : 99; if (!($3 in best) || k < best[$3]) { best[$3] = k; cls[$3] = $1 } }
  END { for (p in cls) printf "%s\t%s\n", cls[p], p }')"

printf '  %-14s %6s %6s   %7s %7s %7s %7s\n' class paths rows x86_64 aarch64 riscv64 wasm
for c in $CLASS_ORDER UNCLASSIFIED; do
  r="$(printf '%s\n' "$ROWS" | awk -F'\t' -v c="$c" '$1 == c')"
  [ -n "$r" ] || continue
  pp="$(printf '%s\n' "$PATHCLASS" | awk -F'\t' -v c="$c" '$1 == c' | wc -l | tr -d ' ')"
  printf '  %-14s %6s %6s   %7s %7s %7s %7s\n' "$c" "$pp" "$(printf '%s\n' "$r" | wc -l | tr -d ' ')" \
    "$(printf '%s\n' "$r" | awk -F'\t' '$2 == "x86_64"' | wc -l | tr -d ' ')" \
    "$(printf '%s\n' "$r" | awk -F'\t' '$2 == "aarch64"' | wc -l | tr -d ' ')" \
    "$(printf '%s\n' "$r" | awk -F'\t' '$2 == "riscv64"' | wc -l | tr -d ' ')" \
    "$(printf '%s\n' "$r" | awk -F'\t' '$2 == "wasm"' | wc -l | tr -d ' ')"
done
echo "  (paths: each path counted once, under its highest-priority class; rows: path x judged backend."
echo "   x86_64 is a JUDGED backend once the reference moves to a twin (#1014): REFUSED there means x86_64"
echo "   refused what a twin compiled and ran — the over-refusal worth fixing, which ACCEPTS used to hide.)"
[ "$MODE" = count ] && exit 0

## The table: every disagreeing path with all four states, so "agreed", "trapped" and "never ran"
## stay distinguishable. `ref=` names the reference — x86_64 when it ran, otherwise the twin the
## classifier fell back to (#1014). `*` marks the BACKENDS that disagree with that reference; x86_64
## is one of them once the reference has moved, and its REFUSED row is an over-refusal worth fixing.
echo
for c in $CLASS_ORDER UNCLASSIFIED; do
  pp="$(printf '%s\n' "$PATHCLASS" | awk -F'\t' -v c="$c" '$1 == c' | cut -f2 | sort)"
  [ -n "$pp" ] || continue
  echo "## $c"
  printf '%s\n' "$pp" | while read -r p; do
    printf '%s\n' "$ROWS" | awk -F'\t' -v p="$p" '
      $3 == p { x = $4; tg = $6; sub(/ ref=.*/, "", tg)
                t[$2] = $5 ((tg != "-") ? "(" tg ")" : "") "*"
                if ($6 ~ /ref=/) rb = substr($6, index($6, "ref=") + 4) }
      END { if (rb == "") rb = "x86_64"
            printf "  %-60s ref=%s:%-4s", p, rb, x
            split("x86_64 aarch64 riscv64 wasm", b, " ")
            for (i = 1; i <= 4; i++) printf " %s=%-10s", b[i], ((b[i] in t) ? t[b[i]] : "=") ; printf "\n" }'
  done
done
exit 0
