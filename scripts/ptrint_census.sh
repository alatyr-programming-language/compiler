#!/usr/bin/env bash
# scripts/ptrint_census.sh — the Issue #529 step-2 usize↔ptr(T) CENSUS.
#
# `src/sema.al` carries a measurement instrument that COUNTS, and never refuses, the places where the
# `ptrint_seam` predicate — the int(1)↔pointer(5) pair `tag_compat` accepts in both directions — is
# what decides a type-compatibility verdict. Types §4.3 makes **reinterpret** always explicit and
# Memory §4.5 makes fabricating a pointer from an integer ill-formed outside an `unchecked` grant, so
# every place this script counts is a place #529 step 3 has to bring to explicit form.
#
# It writes one row per finding to file descriptor 98, which an ordinary invocation does not have
# open — so the instrument is silent, and the compiler's exit status, diagnostics and emitted GAS are
# the uninstrumented ones. This script is what opens the channel. 98, not the #299 brand census's 99,
# on purpose: the two censuses never share a stream, `scripts/brand_census.sh`'s row counts keep
# meaning what they meant, and both can be opened in one invocation.
#
# Usage (inside `nix develop`):
#   bash scripts/ptrint_census.sh census  [<compiler>]          # count over src/, lib/ and test/
#   bash scripts/ptrint_census.sh neutral <base-cc> <probe-cc>  # rc + diagnostic + GAS bytes must agree
#   bash scripts/ptrint_census.sh planted <compiler>            # prove the counter can fire
#
# WHAT THE NUMBER MEANS, and what it does not. A row is a place where the seam CHANGED the verdict:
# both tags known, different, and one of them the pointer. A pointer passed to a pointer parameter is
# not a row — `tag_compat` returns on `x == y` before the seam is consulted — and neither is anything
# either side of which sema left unknown. That is the whole point of measuring instead of grepping:
# #452's lesson is that `src : ptr(u8)` is declared 1821 times in `src/` against `src : usize` once,
# and neither number bounds this one, because a grep counts FORMS and the type comes from the
# enclosing declaration the grep never read.
#
# `census` prints the per-class × per-direction table (every class, zero rows included), the
# src/lib/test tier split, and the per-FILE breakdown sorted descending so #529 step 3 can cut slices
# with the largest file last. `neutral` is the companion the #507 caveat requires: an instrumented
# census can report confidently and wrongly, so "this build only counts" is proved separately, by
# comparing every tracked fixture's exit status, normalized diagnostic bytes AND emitted GAS between
# the two compilers with the input tree held fixed. `planted` is the non-vacuity proof: a census that
# reports zero has to show that its counter could have fired at all.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT" || exit 1
ulimit -c 0
MODE="${1:-census}"
OUT="$ROOT/target/ptrint_census"; mkdir -p "$OUT"

# The classes the instrument can emit, listed HERE so a class with no place is still a row of the
# report. A table that silently omits its empty classes cannot be told from one whose hook is dead.
CLASSES="ARG BIND REASSIGN FIELD-LIT FIELD-STORE ELEM-STORE PLACE-NESTED PLACE-ARRNESTED RESULT-RET RESULT-TAIL OP-CMP OP-IF OP-MATCH"
DIRS="i2p p2i sym"

# One `alatyr check` with the census channel open. The redirection order matters: `98>` must name a
# real file, never a duplicate of an already-redirected stdout (`>/dev/null 98>&1` sends the rows to
# /dev/null and reads as an empty census).
probe_one() { # $1 compiler  $2 source  $3 rows-file
  "$1" check "$2" 98>"$3" >/dev/null 2>"$3.err"
  echo $?
}

# A row is `#529 <CLS> <DIR> <SITE> <off> <MODULE> <DECL> |<source line>`; a summary is
# `#529 SUMMARY calls=… unequal=… seam=… rows=… break=… arith_ptr_operand=… lost=…`.
census() {
  local CC="${2:-$ROOT/target/debug/alatyr}"
  [ -x "$CC" ] || { echo "ptrint_census: no compiler at $CC" >&2; exit 1; }
  : > "$OUT/rows.txt"; : > "$OUT/summaries.txt"

  echo "=== src/ (the compiler's own package: src/*.al plus every ambiently injected lib module) ==="
  local rc; rc=$(probe_one "$CC" package.al "$OUT/src.rows")
  echo "package.al check rc=$rc"
  awk '!/ SUMMARY /' "$OUT/src.rows" | sed 's#^#src package.al #' >> "$OUT/rows.txt"
  awk '/ SUMMARY /' "$OUT/src.rows" | sed "s#^#src package.al rc=$rc #" >> "$OUT/summaries.txt"
  awk '/ SUMMARY /{print "  "$0}' "$OUT/src.rows"

  echo "=== lib/ (per module; a module that does not check standalone is reported, not counted) ==="
  local n_ok=0 n_bad=0
  while read -r f; do
    rc=$(probe_one "$CC" "$f" "$OUT/one.rows")
    if [ "$rc" = 0 ]; then n_ok=$((n_ok+1)); else n_bad=$((n_bad+1)); echo "  NOT-STANDALONE rc=$rc $f"; fi
    awk -v p="$f" '!/ SUMMARY /{print "lib "p" "$0}' "$OUT/one.rows" >> "$OUT/rows.txt"
    awk -v p="$f" -v r="$rc" '/ SUMMARY /{print "lib "p" rc="r" "$0}' "$OUT/one.rows" >> "$OUT/summaries.txt"
  done < <(git ls-files 'lib/**/*.al' 'lib/*.al')
  echo "  lib modules: standalone-checkable=$n_ok not-standalone=$n_bad"

  echo "=== test/ (every tracked fixture) ==="
  local n=0
  while read -r f; do
    n=$((n+1))
    rc=$(probe_one "$CC" "$f" "$OUT/one.rows")
    awk -v p="$f" -v r="$rc" '!/ SUMMARY /{print "test "p" rc="r" "$0}' "$OUT/one.rows" >> "$OUT/rows.txt"
    awk -v p="$f" -v r="$rc" '/ SUMMARY /{print "test "p" rc="r" "$0}' "$OUT/one.rows" >> "$OUT/summaries.txt"
  done < <(git ls-files 'test/*.al')
  echo "  fixtures checked: $n"

  report
}

# The report is a separate function so it can be re-derived from an existing rows.txt without paying
# for the walk again. Every count is taken from the rows, never from a remembered running total.
report() {
  # Rows carry the tier and path prepended by the walk, so the instrument's own fields start at $4
  # for `src`/`lib` (tier path #529 …) and at $5 for `test` (tier path rc=N #529 …). Normalize once,
  # into a flat `tier<TAB>path<TAB>class<TAB>dir<TAB>site<TAB>off<TAB>module<TAB>decl` table, and read
  # every number below off THAT — one parse, not eight.
  awk '{
    tier=$1; path=$2; i=3;
    if ($3 ~ /^rc=/) i=4;
    if ($i != "#529") next;
    print tier"\t"path"\t"$(i+1)"\t"$(i+2)"\t"$(i+3)"\t"$(i+4)"\t"$(i+5)"\t"$(i+6);
  }' "$OUT/rows.txt" > "$OUT/flat.tsv"

  # A PLACE is one (tier, path, class, offset). Two traversals of the same expression reach some
  # sites twice — `expr_has_unbound` and `check_expr` both walk a call's arguments — so the raw row
  # count is an upper bound and this is the number #529 step 3 has to pay. `offset 0` is a synthetic
  # span (a desugar rebased the AST handle): it cannot be a distinct place, so those rows are counted
  # apart instead of collapsing into one fake place.
  awk -F'\t' '$6 != 0' "$OUT/flat.tsv" | cut -f1,2,3,6,7 | sort -u > "$OUT/places.tsv"
  awk -F'\t' '$6 == 0' "$OUT/flat.tsv" > "$OUT/synthetic.tsv"

  echo
  echo "=== rows, places and the instrument's own accounting ==="
  printf '  raw rows                        %s\n' "$(wc -l < "$OUT/flat.tsv")"
  printf '  distinct places (tier,path,class,offset)  %s\n' "$(wc -l < "$OUT/places.tsv")"
  printf '  rows at a SYNTHETIC span (offset 0, no place) %s\n' "$(wc -l < "$OUT/synthetic.tsv")"
  # A synthetic span is a real PLACE whose source position sema cannot give (a parse-time desugar
  # rebased an AST-arena address into a `src`-relative handle, so `ast::span_is_synthetic` holds and
  # even the driver's own renderer reports line 0). It must not be collapsed into one fake place by
  # its shared offset 0, and it must not be dropped either — so it is named by its owning declaration
  # here, which is where #529 step 3 has to go and read.
  if [ -s "$OUT/synthetic.tsv" ]; then
    echo "    they belong to these declarations (step 3 must locate them by reading the function):"
    awk -F'\t' '{print "      "$1" "$7"::"$8"  "$3" "$4}' "$OUT/synthetic.tsv" | sort | uniq -c | sed 's/^/  /'
  fi
  echo "  seam invocations vs classified rows, per program (a difference is the census's blind spot):"
  awk '{for(i=1;i<=NF;i++){if($i ~ /^seam=/) s=substr($i,6); if($i ~ /^rows=/) r=substr($i,6)}
        if (s != r) {print "    BLIND "$0}} END{}' "$OUT/summaries.txt" | head -20
  awk '{for(i=1;i<=NF;i++){if($i ~ /^seam=/) s=substr($i,6); if($i ~ /^rows=/) r=substr($i,6)}
        if (s == r) k++; else b++} END{printf "    programs with seam==rows: %d   with a blind spot: %d\n", k+0, b+0}' "$OUT/summaries.txt"

  echo
  echo "=== ENTRY PROBE (non-vacuity): could the counter have fired at all? ==="
  # `unequal` counts every `tag_compat` invocation whose two tags are both KNOWN and DIFFERENT, i.e.
  # every invocation that reached the seam test. This is the #299 `prelude=` discipline: a census
  # reporting zero must show its scanner arrived. `calls` bounds it from above.
  awk '{for(i=1;i<=NF;i++){if($i ~ /^calls=/) c=substr($i,7); if($i ~ /^unequal=/) u=substr($i,9); if($i ~ /^seam=/) s=substr($i,6)}
        C+=c; U+=u; S+=s; if (c+0 > 0) pc++; if (u+0 > 0) pu++; n++}
        END{printf "  programs reporting a summary: %d\n", n;
            printf "  total tag_compat invocations: %d   (programs with calls>0: %d)\n", C, pc;
            printf "  reached the seam test (both tags known and different): %d   (programs: %d)\n", U, pu;
            printf "  the seam decided the verdict: %d\n", S}' "$OUT/summaries.txt"

  echo
  echo "=== the count by CLASS x DIRECTION (distinct places; every class listed, zero included) ==="
  printf '  %-16s %8s %8s %8s %8s\n' CLASS i2p p2i sym total
  # The direction is not part of a place's identity (a place has one), so it is joined back on from
  # the rows. Reading it from `flat.tsv` and de-duplicating on (tier,path,class,dir,offset) gives the
  # same set as `places.tsv` unless a single offset were reported in both directions — which cannot
  # happen for one place, and the totals line below is what would show it if it ever did.
  awk -F'\t' '$6 != 0' "$OUT/flat.tsv" | cut -f1,2,3,4,6 | sort -u > "$OUT/places_dir.tsv"
  for c in $CLASSES; do
    line="$(awk -F'\t' -v c="$c" '$3==c{n[$4]++; t++} END{printf "%d %d %d %d", n["i2p"]+0, n["p2i"]+0, n["sym"]+0, t+0}' "$OUT/places_dir.tsv")"
    # shellcheck disable=SC2086
    printf '  %-16s %8s %8s %8s %8s\n' "$c" $line
  done
  awk -F'\t' '{n[$4]++; t++} END{printf "  %-16s %8d %8d %8d %8d\n", "ALL", n["i2p"]+0, n["p2i"]+0, n["sym"]+0, t+0}' "$OUT/places_dir.tsv"
  echo "  (a place counted in two directions would make ALL exceed the distinct-place count above)"

  echo
  echo "=== the count by TIER (src/ and lib/ are the price of conforming; test/ is fixtures to rewrite) ==="
  awk -F'\t' '{n[$1]++} END{for (k in n) printf "  %-6s %6d places\n", k, n[k]}' "$OUT/places.tsv" | sort
  echo "  fixtures (tracked test/*.al) carrying at least one place:"
  awk -F'\t' '$1=="test"{p[$2]=1} END{print "    "length(p)}' "$OUT/places.tsv"

  echo
  echo "=== the count by FILE, descending (this is #529 step 3's slicing order: largest LAST) ==="
  # For `src/` and the ambiently injected `lib/` modules the rows all come from ONE `check package.al`
  # invocation over the CONCATENATED source buffer, so the invocation cannot name a file. The
  # instrument reports each row's owning MODULE (`Decl.mod_start/mod_len`, the identity the parser
  # stamps from the driver's per-file stem) and its owning DECLARATION instead, and the module name
  # maps to a path mechanically: `lower__place` → `src/lower/place.al`, `std__io` → `lib/std/io.al`.
  # That is a recovered fact, not a text match: `_ => { s = 0 }` occurs verbatim in a dozen modules,
  # so attributing by the quoted line would be the #452 trap one level up.
  awk -F'\t' '$1!="test"{print $5}' "$OUT/places.tsv" | sort | uniq -c | sort -rn |
    while read -r cnt m; do
      # A module identity is the driver's per-file stem with `/` mangled to `__`, so the path is
      # recovered by unmangling and then ASKING THE TREE which of the two roots actually holds it —
      # never by printing both and letting the reader guess.
      local cand="${m//__//}.al" path=""
      for root in src lib; do [ -f "$root/$cand" ] && path="$root/$cand"; done
      case "$m" in
        -) printf '  %6s  %s\n' "$cnt" "(no module identity — the anonymous package root)" ;;
        *) printf '  %6s  %s\n' "$cnt" "${path:-UNRESOLVED module \`$m\`}" ;;
      esac
    done
  echo "  --- test/ fixtures, descending ---"
  awk -F'\t' '$1=="test"{print $2}' "$OUT/places.tsv" | sort | uniq -c | sort -rn | head -40 |
    while read -r cnt f; do printf '  %6s  %s\n' "$cnt" "$f"; done

  echo
  echo "=== the top DECLARATIONS, descending (a slice is usually a function, not a file) ==="
  awk -F'\t' '$1!="test"{print $7"::"$8}' "$OUT/flat.tsv" | sort | uniq -c | sort -rn | head -25 | sed 's/^/  /'

  echo
  echo "=== ADJACENT and deliberately NOT in the count above ==="
  # `Expr::Bin` arithmetic accepts a POINTER operand directly, without consulting `tag_compat` at all,
  # and yields tag 1. Deleting the seam does not touch it, and it is the manufacturer of many of the
  # tag-1 values the seam then accepts at a pointer sink. Step 4 needs the number; step 2 must not
  # fold it into its own.
  awk '{for(i=1;i<=NF;i++) if($i ~ /^arith_ptr_operand=/) t+=substr($i,20)} END{printf "  arithmetic with a pointer operand (no tag_compat involved): %d\n", t+0}' "$OUT/summaries.txt"
  awk '{for(i=1;i<=NF;i++) if($i ~ /^break=/) t+=substr($i,7)} END{printf "  loop-break value merges hitting the seam (counter only, no row): %d\n", t+0}' "$OUT/summaries.txt"
  awk '{for(i=1;i<=NF;i++) if($i ~ /^lost=/) t+=substr($i,6)} END{printf "  census rows the channel did not accept in full (lost): %d\n", t+0}' "$OUT/summaries.txt"

  echo
  echo "rows: $OUT/rows.txt   places: $OUT/places.tsv   summaries: $OUT/summaries.txt"
}

# The neutrality proof. Two compilers, the SAME input tree, and three things compared per input: the
# exit status, the sha256 of the diagnostic bytes, and the sha256 of the emitted GAS. rc alone is not
# enough — a changed diagnostic with an unchanged status is exactly the silent difference an
# instrumented build can introduce.
neutral() {
  local BASE="$2" PROBE="$3"
  [ -x "$BASE" ] && [ -x "$PROBE" ] || { echo "ptrint_census: need two executables" >&2; exit 1; }
  local ddiag=0 dgas=0 n=0
  : > "$OUT/neutral.txt"

  # (0) the compiler's OWN sources, both paths: `check package.al` and the full self-build's GAS.
  # A census over `src/` that changed the self-build would be caught here and nowhere else in this
  # function, because `package.al` is not a tracked `test/*.al`.
  "$BASE"  check package.al >"$OUT/b.out" 2>"$OUT/b.err"; local brc=$?
  "$PROBE" check package.al >"$OUT/p.out" 2>"$OUT/p.err"; local prc=$?
  local bh ph
  bh=$(sha256sum < "$OUT/b.err" | cut -d' ' -f1); ph=$(sha256sum < "$OUT/p.err" | cut -d' ' -f1)
  if [ "$brc" != "$prc" ] || [ "$bh" != "$ph" ]; then
    ddiag=$((ddiag+1)); echo "DIAG package.al base_rc=$brc probe_rc=$prc base_sha=$bh probe_sha=$ph" >> "$OUT/neutral.txt"
  fi
  "$BASE"  package.al >"$OUT/b.s" 2>/dev/null; local bg=$?
  "$PROBE" package.al >"$OUT/p.s" 2>/dev/null; local pg=$?
  bh=$(sha256sum < "$OUT/b.s" | cut -d' ' -f1); ph=$(sha256sum < "$OUT/p.s" | cut -d' ' -f1)
  if [ "$bg" != "$pg" ] || [ "$bh" != "$ph" ]; then
    dgas=$((dgas+1)); echo "GAS  package.al base_rc=$bg probe_rc=$pg base_sha=$bh probe_sha=$ph" >> "$OUT/neutral.txt"
  fi
  echo "self-build compared: check rc $brc/$prc, GAS rc $bg/$pg"

  # (1) every `lib/` module, and (2) every tracked fixture.
  while read -r f; do
    n=$((n+1))
    "$BASE"  check "$f" >"$OUT/b.out" 2>"$OUT/b.err"; brc=$?
    "$PROBE" check "$f" >"$OUT/p.out" 2>"$OUT/p.err"; prc=$?
    bh=$(sha256sum < "$OUT/b.err" | cut -d' ' -f1); ph=$(sha256sum < "$OUT/p.err" | cut -d' ' -f1)
    if [ "$brc" != "$prc" ] || [ "$bh" != "$ph" ]; then
      ddiag=$((ddiag+1)); echo "DIAG $f base_rc=$brc probe_rc=$prc base_sha=$bh probe_sha=$ph" >> "$OUT/neutral.txt"
    fi
    "$BASE"  "$f" >"$OUT/b.s" 2>/dev/null; bg=$?
    "$PROBE" "$f" >"$OUT/p.s" 2>/dev/null; pg=$?
    bh=$(sha256sum < "$OUT/b.s" | cut -d' ' -f1); ph=$(sha256sum < "$OUT/p.s" | cut -d' ' -f1)
    if [ "$bg" != "$pg" ] || [ "$bh" != "$ph" ]; then
      dgas=$((dgas+1)); echo "GAS  $f base_rc=$bg probe_rc=$pg base_sha=$bh probe_sha=$ph" >> "$OUT/neutral.txt"
    fi
  done < <(git ls-files 'lib/**/*.al' 'lib/*.al' 'test/*.al')

  echo "neutrality: inputs=$((n+1)) differing_diagnostics=$ddiag differing_gas=$dgas"
  sed 's/^/  /' "$OUT/neutral.txt"
  if [ "$ddiag" = 0 ] && [ "$dgas" = 0 ]; then
    echo "*** ptrint census: the probe build changes no exit status, no diagnostic byte and no emitted GAS byte ***"
    return 0
  fi
  return 1
}

# The non-vacuity proof, and the reason a zero would be publishable. `planted` writes a program with
# ONE artificial differing place per direction and shows the counter reports them. A census whose
# counter is dead reports zero for every tree, and the entry probe alone cannot tell a dead counter
# from a clean one when both tags happen never to differ.
planted() {
  local CC="${2:-$ROOT/target/debug/alatyr}"
  [ -x "$CC" ] || { echo "ptrint_census: no compiler at $CC" >&2; exit 1; }
  local P="$OUT/planted.al"
  cat > "$P" <<'AL'
## Issue #529 census non-vacuity fixture, GENERATED by scripts/ptrint_census.sh — not a `test/`
## fixture and not tracked. Every place below is DELIBERATELY spelled WITHOUT the `unchecked bitcast`
## the specification requires, because that is what the seam IS: an integer and a pointer meeting at
## a compatibility site with no explicit conversion. Writing the casts in makes the two tags AGREE and
## the counter then correctly reports nothing — the first version of this fixture did exactly that and
## reported zero, which is the trap this proof exists to catch.
##
## The exact SPELLING of each place is load-bearing and was found by measurement, not by taste. sema
## recovers a value's type from several sources of differing reliability, so at the same class the
## same conversion is visible in one spelling and invisible in another: a bare `Var` naming an
## annotated POINTER local is seen (so `p2i` fires), while a bare `Var` naming an annotated INTEGER
## local is NOT (its recovered tag is unknown), and the `i2p` direction has to be spelled with a
## LITERAL or a declared-result CALL to be seen at all. That asymmetry is a property of the checker,
## not of this instrument, and it is why the census reports each class in both directions separately.
take_ptr := fn(p : ptr(u8)) -> usize { return unchecked bitcast(usize, p) }
take_int := fn(h : usize) -> usize { return h }
give_ptr := fn() -> ptr(u8) { return unchecked bitcast(ptr(u8), 4096) }
give_int := fn() -> usize { return 4096 }
Holder := struct { p : ptr(u8), h : usize }
Inner := struct { p : ptr(u8) }
Outer := struct { i : Inner }

## RESULT-RET, both directions: the declared result and an early `return` value differ.
ret_i2p := fn() -> ptr(u8) { return give_int() }
ret_p2i := fn() -> usize { pp : ptr(u8) = give_ptr() ; return pp }
## RESULT-TAIL, both directions: the declared result and the tail expression differ.
tail_i2p := fn() -> ptr(u8) { give_int() }
tail_p2i := fn() -> usize { give_ptr() }

pub main := fn() -> i32 {
  p : ptr(u8) = give_ptr()
  ## ARG: an integer at a pointer parameter (literal and declared-result call), and the reverse.
  a0 := take_ptr(4096)
  a1 := take_ptr(give_int())
  a2 := take_int(p)
  ## BIND: an annotated binding whose initializer is the other kind.
  b0 : ptr(u8) = 0
  b1 : usize = p
  ## REASSIGN: a `=` write of the other kind into an existing local.
  mut r0 : ptr(u8) = give_ptr()
  r0 = 0
  mut r1 : usize = 1
  r1 = p
  ## FIELD-STORE: a direct `root.f = v` store, both directions.
  mut s0 := Holder(p = give_ptr(), h = 1)
  s0.p = 4096
  s0.h = p
  ## ELEM-STORE: an `xs[i] = v` element store, both directions.
  mut ap : [ptr(u8); 2] = [give_ptr(), give_ptr()]
  ap[0] = 4096
  mut ah : [usize; 2] = [1, 2]
  ah[0] = p
  ## PLACE-NESTED: the bounded `root.first.second = v` store.
  mut o0 := Outer(i = Inner(p = give_ptr()))
  o0.i.p = 4096
  ## RESULT-RET / RESULT-TAIL, through the four helpers above.
  c0 := ret_i2p()
  c1 := ret_p2i()
  c2 := tail_i2p()
  c3 := tail_p2i()
  if a0 + a1 + a2 + b1 + r1 + c1 + c3 == 0 { return 1 }
  0
}
AL
  local rc; rc=$(probe_one "$CC" "$P" "$OUT/planted.rows")
  echo "planted program check rc=$rc  (must be 0: the instrument counts, it does not refuse)"
  echo "  the artificial places the counter reported:"
  sed 's/^/    /' "$OUT/planted.rows"
  awk '!/ SUMMARY /{print $2"\t"$3}' "$OUT/planted.rows" | sort -u > "$OUT/planted_cov.tsv"

  echo
  echo "  per-CLASS coverage — which hook has been PROVEN able to fire, and in which direction:"
  local unproven=0
  for c in $CLASSES; do
    local got
    got="$(awk -F'\t' -v c="$c" '$1==c{printf "%s ", $2}' "$OUT/planted_cov.tsv")"
    if [ -n "$got" ]; then printf '    %-16s PROVEN  %s\n' "$c" "$got"
    else printf '    %-16s NOT PROVEN — a zero for this class over the real tree means NO COVERAGE, not clean\n' "$c"; unproven=$((unproven+1)); fi
  done
  echo "    classes whose hook this proof could not make fire: $unproven of $(set -- $CLASSES; echo $#)"
  echo "    (the five OP-*/FIELD-LIT/ARG-callarm hooks live in check_expr's big \`match deref(e)\`"
  echo "     region, which sema's own header records as NOT DISPATCHED under the bootstrap seed"
  echo "     (scar #2) — so at those sites neither this census NOR the checker's own conformance"
  echo "     test runs today. That is a gap in the CHECKER, reported here rather than hidden.)"

  local hits i2p p2i
  hits=$(awk '!/ SUMMARY /' "$OUT/planted.rows" | wc -l)
  i2p=$(awk -F'\t' '$2=="i2p"' "$OUT/planted_cov.tsv" | wc -l)
  p2i=$(awk -F'\t' '$2=="p2i"' "$OUT/planted_cov.tsv" | wc -l)
  echo
  echo "  planted rows=$hits   classes proven in i2p=$i2p   classes proven in p2i=$p2i"
  if [ "$rc" != 0 ]; then
    echo "*** ptrint census: the planted program was REFUSED (rc=$rc) — the instrument must only count ***"
    return 1
  fi
  if [ "$hits" -gt 0 ] && [ "$i2p" -gt 0 ] && [ "$p2i" -gt 0 ]; then
    echo "*** ptrint census: the counter fires, in both directions, across $(wc -l < "$OUT/planted_cov.tsv") class/direction"
    echo "    combinations, on a program that is still ACCEPTED — so a zero anywhere above is a"
    echo "    measurement and not a silence ***"
    return 0
  fi
  echo "*** ptrint census: the counter reported nothing on a program built to trip it — a ZERO over the"
  echo "    real tree would be MEANINGLESS until this passes ***"
  return 1
}

case "$MODE" in
  census)  census "$@" ;;
  report)  report ;;
  neutral) neutral "$@" ;;
  planted) planted "$@" ;;
  *) echo "usage: ptrint_census.sh census|report|neutral|planted" >&2; exit 2 ;;
esac
