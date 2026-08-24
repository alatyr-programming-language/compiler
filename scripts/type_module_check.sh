#!/usr/bin/env bash
# scripts/type_module_check.sh — the whole-program EMITTED-TYPE invariant (Modules §3 + Types §4.1).
#
# The sibling of `scripts/callee_module_check.sh`, for the other half of the same defect family. That
# one checks CALL edges; this one checks every emitted reference that came from a TYPE declaration.
#
# Why it exists: before TYPE-ANCESTOR, `lower_layout::struct_decl_of`/`enum_decl_of` took NO naming
# module at all and settled same-named candidates by DECLARATION ORDER (the LAST one won — the opposite
# tie-break of the callee fallback). Nothing compared an emitted type identity against the declaration
# the referencing module may actually see: `scripts/fixpoint.sh` compares the tree's GAS against
# itself, the corpus manifest compares exit codes, and `scripts/e2e.sh` plus all three sweeps were
# green while a child module's `Box.size()` sized a SIBLING's `Box` (measured: 50 instead of 42).
#
# The invariant, read straight off the emitted GAS + the source declaration table:
#
#   for every emitted symbol of the monomorphized form `<mod>__<generic>__<Targ>`, let T be the TYPE
#   ARGUMENT `<Targ>`. If `<mod>`'s own module or any ANCESTOR of it declares a type named T, that is
#   the declaration Modules §3 binds and the reference is answered. Otherwise the reference is only
#   sound when T is UNAMBIGUOUS (declared exactly once in the program) or `<mod>` SPELLED the module
#   it means (a qualified path `M::T`, a listed projection `(… T …) := M`, an alias `T := M::T`).
#   Two or more off-chain declarations with no explicit spelling means the emitter GUESSED which
#   type's layout to use — the defect class, and a silent wrong size/offset/variant tag.
#
# The mangled instance is the ONE emitted symbol that carries a type identity in its NAME. The other
# two type-derived emissions are keyed by SOURCE OFFSET, not by name — `typeinfo` is comptime-folded
# (no runtime descriptor survives into the GAS) and a struct/enum field-name rodata label is
# `.Lfld<modidx>_<off>`. Those are covered by CLASS C below, which resolves each field label to the
# module whose block DEFINES it and reports every cross-module reference, so a field-name table
# crossing a module boundary cannot start happening silently.
#
# Usage:  scripts/type_module_check.sh [--strict] [<gas-file>] [<srcdir> ...]
#   default gas-file: target/gas1.s (written by scripts/fixpoint.sh); default srcdirs: src lib
# Exit 0 = invariant holds. Exit 1 = violations (or, under --strict, any reported class).
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1
STRICT=0
if [ "${1:-}" = "--strict" ]; then STRICT=1; shift; fi
GAS="${1:-target/gas1.s}"
shift 2>/dev/null || true
DIRS=("$@")
[ "${#DIRS[@]}" = 0 ] && DIRS=(src lib)
[ -s "$GAS" ] || { echo "type_module_check: no GAS at $GAS (run scripts/fixpoint.sh first)"; exit 2; }

# The source table: one `T <module> <TypeName> <ispub>` line per declared TYPE (struct / enum / raw
# union / brand / `@require` contract / type alias / generic type-function), plus one
# `E <callermodule> <TypeName> <namedmodule>` line per module-explicit spelling. A module's name is
# its path under the source dir with `/` -> `__` (MOD-6 / MOD-12).
TBL="$(mktemp)"; trap 'rm -f "$TBL"' EXIT
for d in "${DIRS[@]}"; do
  [ -d "$d" ] || continue
  while IFS= read -r f; do
    rel="${f#"$d"/}"; mod="${rel%.al}"; mod="${mod//\//__}"
    # EVERY module is registered, not only the ones that declare a type: `<mod>` is what splits a
    # mangled instance symbol, and most instances live in modules that declare no type at all
    # (`comptime__node_ptr__Arg`, `lower_ctx__node_ptr__Expr`). Without this the scan silently
    # inspected 18 of the tree's 25 instances — the exact way this gate could have gone half-vacuous.
    printf 'M %s\n' "$mod"
    gawk -v mod="$mod" '
      { line = $0
        sub(/##.*$/, "", line)
        gsub(/"([^"\\]|\\.)*"/, "\"\"", line) }
      # a declared TYPE: `Name := [attrs] struct|enum|union|brand(|@require(|fn(… : type) -> type`
      # or a plain one-line ALIAS to another Capitalised type name.
      match(line, /^(pub )?[A-Z][A-Za-z0-9_]* := (@[A-Za-z_0-9(),.]+ )*(struct|enum|union|brand\(|fn *\(.*-> *type)/) ||
      match(line, /^(pub )?[A-Z][A-Za-z0-9_]* := (@require\([A-Za-z_0-9]+\) )/) ||
      match(line, /^(pub )?[A-Z][A-Za-z0-9_]* := [A-Za-z_][A-Za-z0-9_]*(::[A-Za-z_][A-Za-z0-9_]*)*(\(.*\))?[ \t]*$/) {
        ispub = (line ~ /^pub /) ? 1 : 0
        s = line; sub(/^pub /, "", s); sub(/ :=.*$/, "", s)
        print "T " mod " " s " " ispub; next
      }
      # a listed member projection `(A, B) := M` — each listed name is bound to M
      match(line, /^(pub )?\([^)]*\) := [A-Za-z_][A-Za-z0-9_:]*[ \t]*$/) {
        s = line; sub(/^pub /, "", s)
        head = s; sub(/^\([^)]*\)[ \t]*:=[ \t]*/, "", head); gsub(/[ \t]/, "", head)
        gsub(/::/, "__", head)
        names = s; sub(/^\(/, "", names); sub(/\).*$/, "", names)
        n = split(names, A, ",")
        for (i = 1; i <= n; i++) { gsub(/[ \t]/, "", A[i]); if (A[i] != "") print "E " mod " " A[i] " " head }
        next
      }
      # a single alias `T := M::U` (binds the LOCAL name to M, and also names U in M)
      match(line, /^(pub )?[A-Za-z_][A-Za-z0-9_]* := [A-Za-z_][A-Za-z0-9_]*(::[A-Za-z_][A-Za-z0-9_]*)+[ \t]*$/) {
        s = line; sub(/^pub /, "", s)
        lhs = s; sub(/ :=.*$/, "", lhs); gsub(/[ \t]/, "", lhs)
        rhs = s; sub(/^[^:]*:=[ \t]*/, "", rhs); gsub(/[ \t]/, "", rhs)
        tail = rhs; sub(/^.*::/, "", tail)
        head = rhs; sub(/::[^:]*$/, "", head); gsub(/::/, "__", head)
        print "E " mod " " tail " " head
        print "E " mod " " lhs " " head
        next
      }
      # any QUALIFIED type path `M::…::T` spelled anywhere in this module (a signature, an
      # annotation, a generic argument, a construction) — the module SAID which module it means.
      { rest = line
        while (match(rest, /[A-Za-z_][A-Za-z0-9_]*(::[A-Za-z_][A-Za-z0-9_]*)+/)) {
          tok = substr(rest, RSTART, RLENGTH); rest = substr(rest, RSTART + RLENGTH)
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
    if (F[1] == "M") { MOD[F[2]] = 1 }
    else if (F[1] == "T") { TDECL[F[2] SUBSEP F[3]] = 1; TPUB[F[2] SUBSEP F[3]] = F[4] + 0
                       TN[F[3]]++; TWHERE[F[3]] = TWHERE[F[3]] " " F[2]; MOD[F[2]] = 1 }
    else if (F[1] == "E") { EXEMPT[F[2] SUBSEP F[3] SUBSEP F[4]] = 1; ESAID[F[2] SUBSEP F[3]] = 1 }
  }
  close(tbl)
  # every module that owns at least one declaration of any kind (needed to split a symbol)
}
# the module of a symbol: the LONGEST known module that prefixes it as `<mod>__`
function modof(sym,   m, best) {
  best = ""
  for (m in MOD) { if (index(sym, m "__") == 1 && length(m) > length(best)) best = m }
  return best
}
# is ANY declaration of type t marked `pub`?
function anypub(t,   w, n, A, i) {
  w = TWHERE[t]; sub(/^ /, "", w)
  n = split(w, A, " ")
  for (i = 1; i <= n; i++) { if (TPUB[A[i] SUBSEP t]) return 1 }
  return 0
}
# the nearest module on `cm`s §3 chain that declares type t, or "@" if none
function nearest_type(cm, t,   chain) {
  chain = cm
  while (1) {
    if (TDECL[chain SUBSEP t]) return chain
    if (chain == "") return "@"
    if (!sub(/__[A-Za-z0-9_]+$/, "", chain)) chain = ""
  }
}
# --- CLASS C bookkeeping: which module block DEFINES each `.Lfld<m>_<off>` label
/^\.Lfld[0-9]+_[0-9]+:$/ { lbl = substr($0, 1, length($0) - 1); FLDOWNER[lbl] = curmod; next }
/^[A-Za-z_][A-Za-z0-9_.]*:$/ {
  fn = substr($0, 1, length($0) - 1)
  m = modof(fn); if (m != "") curmod = m
  # --- CLASS A/B: a monomorphized instance DEFINITION, viewed from the module that owns it (the
  # instance BODY spells the substituted type, so the module that owns the instance must be able to name it).
  check_instance(fn, modof(fn))
  next
}
{ # --- CLASS A/B: a monomorphized instance REFERENCE (a call or a leaq/movq operand), viewed from the
  # REFERENCING module — the type ARGUMENT was spelled at this use site, so this is the module whose
  # section-3 chain decides which declaration the tag stands for.
  rest = $0
  while (match(rest, /[A-Za-z_][A-Za-z0-9_]*__[A-Za-z_][A-Za-z0-9_]*__[A-Za-z_][A-Za-z0-9_]*/)) {
    tok = substr(rest, RSTART, RLENGTH); rest = substr(rest, RSTART + RLENGTH)
    check_instance(tok, curmod)
  }
  # --- CLASS C: a field-name rodata label referenced from a function
  rest2 = $0
  while (match(rest2, /\.Lfld[0-9]+_[0-9]+/)) {
    tok2 = substr(rest2, RSTART, RLENGTH); rest2 = substr(rest2, RSTART + RLENGTH)
    FLDREF[tok2 SUBSEP curmod] = 1
  }
}
function check_instance(sym, cm,   sm, rem, targ, nearest, k) {
  sm = modof(sym); if (sm == "") return
  rem = substr(sym, length(sm) + 3)
  if (rem !~ /__/) return
  targ = rem; sub(/^.*__/, "", targ)          # the TYPE ARGUMENT is the last segment
  if (!(targ in TN)) return                   # a builtin (`u8`) / not a declared type name
  if (cm == "") cm = sm                       # a reference from outside any module: fall back
  if (seen_sym[sym SUBSEP cm]) return
  seen_sym[sym SUBSEP cm] = 1
  if (!seen_inst[sym]) { seen_inst[sym] = 1; ninst++ }
  nearest = nearest_type(cm, targ)
  if (nearest != "@") return                  # §3 binds it: the nearest visible declaration
  if (TN[targ] >= 2) {
    if (ESAID[cm SUBSEP targ]) return         # the module SAID which module it means
    # Split exactly the way the resolver splits it. NO candidate is `pub` => section 3 makes every one
    # of them unnameable from here in ANY spelling, so no lost qualified head can explain the
    # reference: the emitter guessed, and that is the fatal class. At least one candidate IS `pub` =>
    # a path could legitimately have meant it (the parser keeps only the last segment of a qualified
    # value path), so the compiler keeps the historical tail-only answer and this is REPORTED instead
    # — a namespace hazard that must not grow silently, not a proven wrong binding.
    if (anypub(targ)) {
      k = sym " (type `" targ "` is declared in" TWHERE[targ] "; `" cm "` may name none of them directly, and the tail-only answer decides)"
      if (!(k in seenP)) { seenP[k] = 1; print "AMBIGPUB " k; ambigpub++ }
      return
    }
    k = sym " (type `" targ "` is declared in" TWHERE[targ] ", none of them `pub`, and `" cm "` may name none of them)"
    if (!(k in seenA)) { seenA[k] = 1; print "VIOLATION " k; bad++ }
    return
  }
  # exactly one declaration, off the chain: sound only through a `pub` path
  w = TWHERE[targ]; gsub(/^ /, "", w)
  if (!TPUB[w SUBSEP targ] && !ESAID[cm SUBSEP targ]) {
    k = sym " (`" w "::" targ "` is not `pub`, and `" cm "` is not nested in `" w "`)"
    if (!(k in seenB)) { seenB[k] = 1; print "NONPUB " k; nonpub++ }
  }
}
END {
  for (r in FLDREF) {
    split(r, P, SUBSEP)
    owner = FLDOWNER[P[1]]
    if (owner != "" && P[2] != "" && owner != P[2]) {
      k = P[1] " referenced from module `" P[2] "` but defined in `" owner "`"
      if (!(k in seenC)) { seenC[k] = 1; print "FIELDLABEL " k; fldx++ }
    }
  }
  print "type_module_check: " ninst + 0 " distinct monomorphized instance symbol(s) inspected"
  if (nonpub + 0 > 0) { print "type_module_check: " nonpub " distinct NONPUB type reach(es) (Modules §3 hole, reported)" }
  if (ambigpub + 0 > 0) { print "type_module_check: " ambigpub " tail-only `pub` ambiguity/ambiguities (namespace hazard, reported)" }
  if (fldx + 0 > 0) { print "type_module_check: " fldx " cross-module field-name label reference(s) (reported)" }
  if (bad + 0 == 0) {
    print "type_module_check: OK — every emitted type identity names a declaration Modules §3 makes visible"
    if (strict + 0 == 1 && nonpub + ambigpub + fldx + 0 > 0) { exit 1 }
  }
  else { print "type_module_check: " bad " ambiguous type binding(s)"; exit 1 }
}
' "$GAS"
