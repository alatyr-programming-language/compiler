#!/usr/bin/env bash
# scripts/callee_module_check.sh — the whole-program EMITTED-CALLEE invariant (Modules §3).
#
# Why this exists: a bare call binding to an unrelated module's same-named private duplicate is
# INVISIBLE to every other gate. `scripts/fixpoint.sh` compares the tree's GAS against itself, the
# corpus manifest compares exit codes, `scripts/e2e.sh` and all three sweeps were green while
# `driver.al`'s bare `streq` emitted `call aarch64__streq` (a DIFFERENT body — no length-first reject,
# no rebased-handle-safe pointer arithmetic) and `riscv64.al`'s bare `param_find` emitted
# `call aarch64__param_find`. Nothing compared a CALL against the declaration the caller may name.
#
# The invariant, read straight off the emitted GAS + the source declaration table:
#
#   for every `call <sym>` inside function F, let P be the callee's declared name and M its module.
#   If F's own module, or any ANCESTOR of it, declares a function named P, then M must be the NEAREST
#   such module. Anything else means the emitter walked PAST a declaration Modules §3 makes visible
#   and picked one it does not.
#
# It deliberately does NOT forbid a cross-module call as such: `lower` calling `rt__push_str` is
# legitimate (neither `lower` nor its ancestors declare `push_str`). It only forbids SKIPPING a
# visible declaration — which is exactly the defect class, and the only one a GAS-level check can
# separate from a legitimate import.
#
# A call is EXEMPT when the calling module's source spells the callee's module explicitly — a
# qualified call `M::P(...)`, a listed member projection `(… P …) := M`, or an alias `P := M::P`.
# Those say which module they mean, so they are answers, not accidents.
#
# Usage:  scripts/callee_module_check.sh [--strict] [<gas-file>] [<srcdir> ...]
#   default gas-file: target/gas1.s (written by scripts/fixpoint.sh); default srcdirs: src lib
# Exit 0 = invariant holds. Exit 1 = violations (each printed as caller -> callee).
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1
STRICT=0
if [ "${1:-}" = "--strict" ]; then STRICT=1; shift; fi
GAS="${1:-target/gas1.s}"
shift 2>/dev/null || true
DIRS=("$@")
[ "${#DIRS[@]}" = 0 ] && DIRS=(src lib)
[ -s "$GAS" ] || { echo "callee_module_check: no GAS at $GAS (run scripts/fixpoint.sh first)"; exit 2; }

# The source table: one line per declared function `<module> <name>`, plus one line per
# module-explicit spelling `<callermodule> <name> <namedmodule>` (a qualified call / projection /
# alias). A module's name is its path under the source dir with `/` -> `__` (MOD-6 / MOD-12).
TBL="$(mktemp)"; trap 'rm -f "$TBL"' EXIT
for d in "${DIRS[@]}"; do
  [ -d "$d" ] || continue
  while IFS= read -r f; do
    rel="${f#"$d"/}"; mod="${rel%.al}"; mod="${mod//\//__}"
    gawk -v mod="$mod" '
      { line = $0
        sub(/##.*$/, "", line)
        gsub(/"([^"\\]|\\.)*"/, "\"\"", line) }
      # a declared function
      match(line, /^(pub )?[A-Za-z_][A-Za-z0-9_]* := (@[A-Za-z_(),]+ )?fn[ (]/) {
        ispub = (line ~ /^pub /) ? 1 : 0
        s = line; sub(/^pub /, "", s); sub(/ :=.*$/, "", s)
        print "D " mod " " s " " ispub; next
      }
      # a listed member projection `(a, b) := M` (each listed name is bound to M)
      match(line, /^(pub )?\([^)]*\) := [A-Za-z_][A-Za-z0-9_:]*[ \t]*$/) {
        s = line; sub(/^pub /, "", s)
        head = s; sub(/^\([^)]*\)[ \t]*:=[ \t]*/, "", head); gsub(/[ \t]/, "", head)
        gsub(/::/, "__", head)
        names = s; sub(/^\(/, "", names); sub(/\).*$/, "", names)
        n = split(names, A, ",")
        for (i = 1; i <= n; i++) { gsub(/[ \t]/, "", A[i]); if (A[i] != "") print "E " mod " " A[i] " " head }
        next
      }
      # a single alias `f := M::g`
      match(line, /^(pub )?[A-Za-z_][A-Za-z0-9_]* := [A-Za-z_][A-Za-z0-9_]*(::[A-Za-z_][A-Za-z0-9_]*)+[ \t]*$/) {
        s = line; sub(/^pub /, "", s)
        rhs = s; sub(/^[^:]*:=[ \t]*/, "", rhs); gsub(/[ \t]/, "", rhs)
        tail = rhs; sub(/^.*::/, "", tail)
        head = rhs; sub(/::[^:]*$/, "", head); gsub(/::/, "__", head)
        print "E " mod " " tail " " head; next
      }
      # any QUALIFIED call/reference `M::…::name(` spelled in this module
      { rest = line
        while (match(rest, /[A-Za-z_][A-Za-z0-9_]*(::[A-Za-z_][A-Za-z0-9_]*)+[ \t]*\(/)) {
          tok = substr(rest, RSTART, RLENGTH); rest = substr(rest, RSTART + RLENGTH)
          sub(/[ \t]*\($/, "", tok)
          tail = tok; sub(/^.*::/, "", tail)
          head = tok; sub(/::[^:]*$/, "", head); gsub(/::/, "__", head)
          print "E " mod " " tail " " head
        } }
    ' "$f"
  done < <(find "$d" -name '*.al' | sort)
done > "$TBL"

gawk -v tbl="$TBL" -v strict="$STRICT" '
BEGIN {
  while ((getline l < tbl) > 0) {
    n = split(l, F, " ")
    if (F[1] == "D") { DECL[F[2] SUBSEP F[3]] = 1; PUB[F[2] SUBSEP F[3]] = F[4] + 0; MOD[F[2]] = 1 }
    else if (F[1] == "E") { EXEMPT[F[2] SUBSEP F[3] SUBSEP F[4]] = 1 }
  }
  close(tbl)
}
# the module of a symbol: the LONGEST known module that prefixes it as `<mod>__`
function modof(sym,   m, best, cand) {
  best = ""
  for (m in MOD) { if (index(sym, m "__") == 1 && length(m) > length(best)) best = m }
  return best
}
# the DECLARED name a symbol carries inside module m: the longest prefix of the remainder that is a
# declared name there (a generic instance appends `__<typetag>`, so the remainder is not the name)
function nameof(sym, m,   r, p) {
  r = (m == "" ? sym : substr(sym, length(m) + 3))
  p = r
  while (p != "") { if (DECL[m SUBSEP p]) return p; if (!sub(/__[^_]([A-Za-z0-9_]*)$/, "", p)) return "" }
  return ""
}
$0 ~ /^[A-Za-z_][A-Za-z0-9_.]*:$/ { fn = substr($0, 1, length($0) - 1); next }
$1 == "call" {
  sym = $2
  if (sym ~ /^[*%]/) next                     # an indirect call — no symbol to attribute
  if (fn == "") next
  if (fn == "_start" || fn == "main") next    # the synthesized entry wrapper is in no module
  cm = modof(fn); tm = modof(sym)
  nm = nameof(sym, tm)
  if (nm == "") next                          # a synthesized / extern / runtime symbol
  # the nearest module on the calling chain that declares this name
  chain = cm; nearest = "@"
  while (1) {
    if (DECL[chain SUBSEP nm]) { nearest = chain; break }
    if (chain == "") break
    if (!sub(/__[A-Za-z0-9_]+$/, "", chain)) chain = ""
  }
  if (nearest == "@") {
    # CLASS 2 (reported, not fatal): nothing on the calling chain declares the name, and the callee
    # is NOT `pub` — so Modules §3 makes it unnameable from here in any spelling, yet the emitter
    # reached it. That is the residual hole the bare-name UNIQUE-declaration fallback leaves open
    # (the leniency the whole compiler leans on for `m := path` bindings); it is reported so it
    # cannot grow silently, and it is fatal only under --strict.
    if (cm != "" && tm != "" && tm != cm && !PUB[tm SUBSEP nm] && !EXEMPT[cm SUBSEP nm SUBSEP tm]) {
      k2 = fn " -> " sym " (`" tm "::" nm "` is not `pub`, and `" cm "` is not nested in `" tm "`)"
      if (!(k2 in seen2)) { seen2[k2] = 1; print "NONPUB " k2; nonpub++ }
    }
    next
  }
  if (nearest == tm) next                      # the emitter picked the nearest visible one
  if (EXEMPT[cm SUBSEP nm SUBSEP tm]) next     # the module SAID which module it means
  key = fn " -> " sym " (module `" cm "` sees `" nearest "::" nm "`)"
  if (!(key in seen)) { seen[key] = 1; print "VIOLATION " key }
  bad++
}
END {
  if (nonpub + 0 > 0) { print "callee_module_check: " nonpub " distinct NONPUB reach(es) (Modules §3 hole, reported)" }
  if (bad + 0 == 0) {
    print "callee_module_check: OK — every emitted call resolves to the nearest module Modules §3 makes visible"
    if (strict + 0 == 1 && nonpub + 0 > 0) { exit 1 }
  }
  else { print "callee_module_check: " bad " violating call site(s)"; exit 1 }
}
' "$GAS"
