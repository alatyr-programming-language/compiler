#!/usr/bin/env bash
# scripts/fmt_corpus.sh — the `alatyr fmt` ARBITER over the whole `test/` corpus.
#
# `alatyr fmt` has NO fail-loud channel for a wrong RENDERING: it exits 0 and writes source. So a
# mis-rendered form is a SILENT MISCOMPILE of the user's program. The only honest check is the
# spec's own norm (Tooling §4.2: semantics-preserving + idempotent), applied to every program the
# repo already owns:
#
#     run(fmt(x)) == run(x)        (same exit status AND same stdout)
#     fmt(fmt(x)) == fmt(x)        (idempotence, the acceptance property)
#
# One line per fixture, classified by DAMAGE (worst first — a BEHAVIOUR failure silently changes
# what the program does, a COMPILEFAIL is at least loud, a NONIDEMPOTENT is formatting churn):
#
#   BEHAVIOUR-EXIT  the formatted program runs to a different exit status or stdout
#   BEHAVIOUR-HANG  the formatted program does not terminate (a lost `break` target, …)
#   COMPILEFAIL     the formatted program no longer compiles (the source did)
#   RECOMPILE       the source was REJECTED but the formatted text compiles (a lost reject)
#   NONIDEMPOTENT   a second fmt pass changes the text again
#   FMT-REFUSE      fmt refused a program that COMPILES (fail-loud rather than guess — see below)
#   FMT-REJECT      fmt refused a program the compiler also rejects (the parse failed; benign)
#   NOCOMPILE-BASE  the source is a reject fixture; fmt is still checked for idempotence
#   OK              round-trips
#
# A `FMT-REFUSE` is DELIBERATE where the written form cannot be recovered from the AST at all
# (`embed("path")` keeps the file BYTES, not the path): refusing is the spec's posture, since a
# canonical form is normative and a guess would diverge between implementations. Those live in
# the ALLOW table below with a reason, so the gate stays green on them and turns RED on anything new.
#
# TWO WALKS, and they check different halves of the norm:
#
#   walk 1  `git ls-files 'test/*.al'`        — PROGRAMS: both halves (behaviour + idempotence)
#   walk 2  `git ls-files 'src/*.al' 'lib/*.al'` — the compiler's own MODULES: idempotence ONLY
#
# Walk 2 exists because walk 1 could not see it. `src/`/`lib/` files are modules, not programs:
# they have no `_start`, so `run(fmt(x)) == run(x)` has no meaning and idempotence is the only
# half of §4.2 that applies to them. That half was worth a gate on its own — `fmt` was
# non-idempotent on SIX of the compiler's own modules and nothing noticed until someone ran `fmt`
# by hand, and it was not cosmetic: on the `deref(p) = v` shape the reparse dropped the STORE, so
# `fmt` was silently rewriting the program. Walk 2 costs ~3 s serial (65 files, 128 `fmt`
# invocations) against walk 1's ~10 minutes, so it is unconditional.
#
# Usage:  nix develop -c bash scripts/fmt_corpus.sh [--jobs N] [--filter REGEX] [--all]
#                                                   [--only test|src]
#   --all         print the OK lines too (default: failures + the summary only)
#   --only test   run walk 1 only  ·  --only src   run walk 2 only (both walks by default)
# Exit 0 iff every failure in EVERY walk it ran is in that walk's ALLOW table.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -n "${ALATYR:-}" ]; then
  AL="$ALATYR"
elif [ -x "$ROOT/target/debug/alatyr" ]; then
  AL="$ROOT/target/debug/alatyr"
else
  AL="$ROOT/target/alatyr"
fi
W="$ROOT/target/fmt_corpus"
JOBS=8
FILTER=""
SHOW_OK=0
ONLY=both
while [ $# -gt 0 ]; do
  case "$1" in
    --jobs) JOBS="$2"; shift 2 ;;
    --filter) FILTER="$2"; shift 2 ;;
    --all) SHOW_OK=1; shift ;;
    --only) ONLY="$2"; shift 2 ;;
    *) echo "usage: $0 [--jobs N] [--filter REGEX] [--all] [--only test|src]" >&2; exit 2 ;;
  esac
done
case "$ONLY" in both|test|src) ;; *) echo "usage: --only test|src" >&2; exit 2 ;; esac
ulimit -c 0

# Fixtures whose CURRENT classification is accepted, each with the reason it is not a fmt bug.
# Anything NOT listed here that fails is a regression. Keep this table shrinking, never growing
# without the reason being recorded in the entry's own comment here and in the issue that tracks
# `alatyr fmt` completeness.
# An ARRAY, not a `case`, so an entry that has STOPPED being needed can be NAMED: the report prints
# `allow-unused <entry>` for any line nothing matched, informationally — never as a failure, because
# a lane that FIXES a residual must not be punished with a red gate for it. (When this was first
# enumerable it immediately named three stale entries that the `case` had hidden: `FMT-REFUSE
# embed_missing` and both `while_labels` rows.)
ALLOW=(
  ## `embed("path")` bakes the file BYTES into a StrLit at parse time; the PATH is gone, so
  ## there is nothing to render. Refusing is the spec posture (`fmt_refuses` in e2e locks it).
  ## A bare comptime-match arm has no canonical braced spelling in the current AST. Refuse rather
  ## than invent a block; the existing comptime_match_bare fixture and e2e row lock this boundary.
  "FMT-REFUSE comptime_match_bare"
  "FMT-REFUSE embed_bytes"
  "FMT-REFUSE embed_byte_storage"
  "FMT-REFUSE embed_typed_bytes"
  "FMT-REFUSE accept_call_arg_conform_wide"
  ## `bitcast(T, v)` is IDENTITY-ERASED at parse time for a scalar/`ptr(scalar)` target, so the
  ## written type is simply absent from the AST. Needs the parser to keep the span; see the issues.
  "BEHAVIOUR-EXIT byte_precise"
)
allowed() { # class rel -> 0 if this exact (class, fixture) pair is a known, reasoned residual
  local k="$1 $2" e
  for e in "${ALLOW[@]}"; do [ "$e" = "$k" ] && return 0; done
  return 1
}

[ -x "$AL" ] || { echo "FAIL: no compiler at $AL (build it first: seed/alatyr build package.al)" >&2; exit 2; }
command -v timeout >/dev/null || { echo "FAIL: coreutils \`timeout\` is required" >&2; exit 2; }
rm -rf "$W"; mkdir -p "$W/o"
fail=0

TCC=60   # seconds for one compile
TRUN=10  # seconds for one program run (a lost `break` target spins forever)

# ==========================================================================================
# WALK 1 — the `test/` corpus: PROGRAMS, both halves of the norm.
# ==========================================================================================
if [ "$ONLY" != src ]; then

# One sandbox per job: a full copy of `test/` so a fixture's SIBLING imports still resolve, and so
# the file under test can be replaced by its formatted text IN PLACE (the module name is the file
# stem and becomes a GAS symbol, so the formatted text must keep the same basename). The `test ->
# .` self-symlink makes a path written the way e2e writes it (`embed("test/embed_fixture.bin")`,
# resolved against the compiler's CWD) resolve here too — without it the embed fixtures failed to
# COMPILE in the sandbox and were misfiled as FMT-REJECT instead of the deliberate FMT-REFUSE.
for j in $(seq 1 "$JOBS"); do cp -r "$ROOT/test" "$W/w$j"; ln -s . "$W/w$j/test"; done

one() { # job-index flat-name relative-path
  local w="$W/w$1" nm="$2" rel="$3"
  local src="$ROOT/test/$rel.al" dst="$w/$rel.al"
  local o1="$W/o/$nm.f1.al" o2="$W/o/$nm.f2.al"
  local bout="$W/o/$nm.b.out" fout="$W/o/$nm.f.out" b2="$W/o/$nm.b2.out"
  local brc bexit frc fexit

  ( cd "$w" && timeout $TCC "$AL" -o "$w/$nm.bin" "$dst" ) >/dev/null 2>&1 </dev/null; brc=$?
  if [ "$brc" = 0 ]; then
    ( cd "$w" && timeout $TRUN "$w/$nm.bin" ) >"$bout" 2>/dev/null </dev/null; bexit=$?
  else
    bexit=""
  fi

  if ! ( cd "$w" && timeout $TCC "$AL" fmt "$dst" ) >"$o1" 2>/dev/null </dev/null; then
    if [ "$brc" = 0 ]; then echo "FMT-REFUSE      $rel"; else echo "FMT-REJECT      $rel"; fi
    return
  fi
  if [ ! -s "$o1" ]; then echo "FMT-REFUSE      $rel (empty output)"; return; fi

  cp "$o1" "$dst"
  if ! ( cd "$w" && timeout $TCC "$AL" fmt "$dst" ) >"$o2" 2>/dev/null </dev/null; then
    cp "$src" "$dst"; echo "NONIDEMPOTENT   $rel (re-emit refused its own output)"; return
  fi
  if ! diff -q "$o1" "$o2" >/dev/null 2>&1; then
    cp "$src" "$dst"; echo "NONIDEMPOTENT   $rel"; return
  fi

  ( cd "$w" && timeout $TCC "$AL" -o "$w/$nm.fbin" "$dst" ) >/dev/null 2>&1 </dev/null; frc=$?
  cp "$src" "$dst"
  if [ "$brc" != 0 ]; then
    if [ "$frc" = 0 ]; then echo "RECOMPILE       $rel"; else echo "NOCOMPILE-BASE  $rel"; fi
    return
  fi
  if [ "$frc" != 0 ]; then echo "COMPILEFAIL     $rel"; return; fi
  ( cd "$w" && timeout $TRUN "$w/$nm.fbin" ) >"$fout" 2>/dev/null </dev/null; fexit=$?
  if [ "$fexit" = 124 ] && [ "$bexit" != 124 ]; then echo "BEHAVIOUR-HANG  $rel (formatted does not terminate)"; return; fi
  if [ "$fexit" != "$bexit" ]; then echo "BEHAVIOUR-EXIT  $rel (exit $fexit want $bexit)"; return; fi
  if ! diff -q "$bout" "$fout" >/dev/null 2>&1; then
    # Confirm the SOURCE program's stdout is deterministic before blaming fmt (a fixture that
    # prints an mmap address differs run to run and is not a formatting failure).
    ( cd "$w" && timeout $TRUN "$w/$nm.bin" ) >"$b2" 2>/dev/null </dev/null
    if diff -q "$bout" "$b2" >/dev/null 2>&1; then echo "BEHAVIOUR-EXIT  $rel (stdout differs)"; return; fi
  fi
  echo "OK              $rel"
}
export -f one
export W AL TCC TRUN

# The corpus is the TRACKED `.al` files under `test/`. Deliberately not `find`: an e2e run leaves
# generated, gitignored `.al` files there (`test/link/statstub/package.al`), which would make the
# corpus size — and so the gate — depend on what ran before it.
if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  git -C "$ROOT" ls-files 'test/*.al' | sed 's|^test/||; s|\.al$||' | sort > "$W/list"
else
  ( cd "$ROOT/test" && find . -name '*.al' -type f | sed 's|^\./||; s|\.al$||' | sort ) > "$W/list"
fi
if [ -n "$FILTER" ]; then grep -E "$FILTER" "$W/list" > "$W/list2" || true; mv "$W/list2" "$W/list"; fi

n=0
: > "$W/raw"
while read -r rel; do
  n=$((n+1))
  j=$(( (n % JOBS) + 1 ))
  ( one "$j" "$(echo "$rel" | tr '/' '_')" "$rel" ) >> "$W/raw" &
  if [ $((n % JOBS)) = 0 ]; then wait; fi
done < "$W/list"
wait
sort -o "$W/raw" "$W/raw"

# ---- report -------------------------------------------------------------------------------
: > "$W/regressions"
: > "$W/seen"
while read -r line; do
  cls=${line%% *}
  rel=$(echo "$line" | awk '{print $2}')
  case "$cls" in
    OK|NOCOMPILE-BASE|FMT-REJECT) [ "$SHOW_OK" = 1 ] && echo "$line" ;;
    *) echo "$cls $rel" >> "$W/seen"
       if allowed "$cls" "$rel"; then echo "allow $line"
       else echo "$line" >> "$W/regressions"; echo "REGRESSION $line"; fail=1; fi ;;
  esac
done < "$W/raw"

# Only meaningful over the WHOLE corpus: a `--filter`ed run legitimately touches a fraction of it.
if [ -z "$FILTER" ]; then
  for e in "${ALLOW[@]}"; do
    grep -qxF "$e" "$W/seen" || echo "allow-unused $e (no longer occurs — drop this entry)"
  done
fi

# Proof of work, not just a verdict: a green line with no counts cannot be told apart from a
# walk that silently found nothing to do. `checked=` must equal `fixtures=`, or the run covered
# less than the corpus and says so.
echo "fmt corpus walk=test fixtures=$(wc -l < "$W/list") checked=$(wc -l < "$W/raw") jobs=$JOBS"
awk '{print $1}' "$W/raw" | sort | uniq -c | sort -rn
if [ "$(wc -l < "$W/list")" -lt 1 ]; then
  echo "*** fmt corpus walk=test: the corpus is EMPTY — the walk proved nothing ***"; fail=1
elif [ "$(wc -l < "$W/raw")" != "$(wc -l < "$W/list")" ]; then
  echo "*** fmt corpus walk=test: classified $(wc -l < "$W/raw") of $(wc -l < "$W/list") fixtures —"
  echo "    a fixture produced no line at all, so the walk covered LESS than the corpus ***"; fail=1
elif [ ! -s "$W/regressions" ]; then
  echo "*** fmt corpus walk=test: every failure is a reasoned residual (see the ALLOW table) ***"
else
  echo "*** fmt corpus walk=test: $(wc -l < "$W/regressions") NEW failure(s) — see REGRESSION above ***"
fi

fi  # end walk 1

# ==========================================================================================
# WALK 1b — the existing multi-file package fixture for qualified function values.
#
# The flat walk above deliberately covers only `test/*.al`; package modules live below
# `test/package/`. Keep this one focused package check beside the formatter arbiter so a source
# recovery in `Expr::Var` cannot silently turn `apply(hex::encode, …)` into `apply(encode, …)`.
# It checks the known-good package result, the formatted package result, and formatter idempotence.
# ==========================================================================================
if [ "$ONLY" != src ] && { [ -z "$FILTER" ] || printf '%s\n' 'test/package/fn_value_qualified' | grep -Eq "$FILTER"; }; then
  PW="$W/package/fn_value_qualified"
  rm -rf "$PW"
  mkdir -p "$W/package"
  cp -r "$ROOT/test/package/fn_value_qualified" "$PW"
  PO1="$W/o/fn_value_qualified.package.f1.al"
  PO2="$W/o/fn_value_qualified.package.f2.al"
  PE="$W/o/fn_value_qualified.package.err"
  PB="$W/o/fn_value_qualified.package.base.out"
  PF="$W/o/fn_value_qualified.package.formatted.out"

  pbase_build=0
  if ! ( cd "$PW" && timeout $TCC "$AL" build package.al ) >"$PB" 2>"$PE" </dev/null; then
    echo "PACKAGE-COMPILEFAIL test/package/fn_value_qualified (baseline)"
    fail=1
  else
    pbin="$PW/target/debug/fn-value-qualified"
    if [ ! -x "$pbin" ]; then
      echo "PACKAGE-COMPILEFAIL test/package/fn_value_qualified (missing executable)"
      fail=1
    else
      ( cd "$PW" && timeout $TRUN "$pbin" ) >"$PB" 2>/dev/null </dev/null; pbase_rc=$?
      if [ "$pbase_rc" != 42 ]; then
        echo "PACKAGE-BASE-BEHAVIOUR test/package/fn_value_qualified (exit $pbase_rc want 42)"
        fail=1
      else
        pbase_build=1
      fi
    fi
  fi

  if ! ( cd "$PW" && timeout $TCC "$AL" fmt src/main.al ) >"$PO1" 2>"$PE" </dev/null; then
    echo "PACKAGE-FMT-REFUSE test/package/fn_value_qualified"
    fail=1
  elif [ ! -s "$PO1" ]; then
    echo "PACKAGE-FMT-REFUSE test/package/fn_value_qualified (empty output)"
    fail=1
  else
    if ! grep -qF 'apply(hex::encode, 40)' "$PO1"; then
      echo "PACKAGE-QUALIFIED-PATH test/package/fn_value_qualified (qualified value path lost)"
      fail=1
    fi
    cp "$PO1" "$PW/src/main.al"
    if ! ( cd "$PW" && timeout $TCC "$AL" fmt src/main.al ) >"$PO2" 2>"$PE" </dev/null; then
      echo "PACKAGE-NONIDEMPOTENT test/package/fn_value_qualified (second fmt refused output)"
      fail=1
    elif ! diff -q "$PO1" "$PO2" >/dev/null 2>&1; then
      echo "PACKAGE-NONIDEMPOTENT test/package/fn_value_qualified"
      fail=1
    elif ! ( cd "$PW" && timeout $TCC "$AL" build package.al ) >"$PF" 2>"$PE" </dev/null; then
      echo "PACKAGE-COMPILEFAIL test/package/fn_value_qualified (formatted)"
      fail=1
    elif [ "$pbase_build" = 1 ]; then
      pbin="$PW/target/debug/fn-value-qualified"
      if [ ! -x "$pbin" ]; then
        echo "PACKAGE-COMPILEFAIL test/package/fn_value_qualified (formatted executable missing)"
        fail=1
      else
        ( cd "$PW" && timeout $TRUN "$pbin" ) >"$PF" 2>/dev/null </dev/null; pformatted_rc=$?
        if [ "$pformatted_rc" != 42 ]; then
          echo "PACKAGE-BEHAVIOUR-EXIT test/package/fn_value_qualified (exit $pformatted_rc want 42)"
          fail=1
        else
          echo "PACKAGE-OK        test/package/fn_value_qualified"
        fi
      fi
    fi
  fi
  echo "fmt package fixture=test/package/fn_value_qualified checked=1"

  # The lexer/parser also accept blanks around `::`. Exercise and EXECUTE that spelling in a COPY of
  # the existing fixture so this formatter-only regression needs no new corpus row or oracle update.
  PS="$W/package/fn_value_qualified_spaced"
  rm -rf "$PS"
  cp -r "$ROOT/test/package/fn_value_qualified" "$PS"
  sed -i \
    -e '/^main := fn() -> u64 {/i\
spaced_value := fn() -> u64 {\
  apply(hex :: encode, 40)\
}' \
  -e '/^  if direct == 41 and indirect == 41 { 42 } else { 0 }$/c\
  spaced := spaced_value()\
  if direct == 41 and indirect == 41 and spaced == 41 { 42 } else { 0 }' \
  "$PS/src/main.al"
  PSO1="$W/o/fn_value_qualified.package.spaced.f1.al"
  PSO2="$W/o/fn_value_qualified.package.spaced.f2.al"
  PSE="$W/o/fn_value_qualified.package.spaced.err"
  PSB="$W/o/fn_value_qualified.package.spaced.build.out"
  if ! ( cd "$PS" && timeout $TCC "$AL" build package.al ) >"$PSB" 2>"$PSE" </dev/null; then
    echo "PACKAGE-SPACED-COMPILEFAIL test/package/fn_value_qualified"
    fail=1
  elif ! ( cd "$PS" && timeout $TCC "$AL" fmt src/main.al ) >"$PSO1" 2>"$PSE" </dev/null; then
    echo "PACKAGE-SPACED-FMT-REFUSE test/package/fn_value_qualified"
    fail=1
  elif [ ! -s "$PSO1" ]; then
    echo "PACKAGE-SPACED-FMT-REFUSE test/package/fn_value_qualified (empty output)"
    fail=1
  else
    if ! grep -qF 'apply(hex :: encode, 40)' "$PSO1"; then
      echo "PACKAGE-SPACED-QUALIFIED-PATH test/package/fn_value_qualified (qualified value path lost)"
      fail=1
    fi
    cp "$PSO1" "$PS/src/main.al"
    if ! ( cd "$PS" && timeout $TCC "$AL" fmt src/main.al ) >"$PSO2" 2>"$PSE" </dev/null; then
      echo "PACKAGE-SPACED-NONIDEMPOTENT test/package/fn_value_qualified (second fmt refused output)"
      fail=1
    elif ! diff -q "$PSO1" "$PSO2" >/dev/null 2>&1; then
      echo "PACKAGE-SPACED-NONIDEMPOTENT test/package/fn_value_qualified"
      fail=1
    elif ! ( cd "$PS" && timeout $TCC "$AL" build package.al ) >"$PSB" 2>"$PSE" </dev/null; then
      echo "PACKAGE-SPACED-COMPILEFAIL test/package/fn_value_qualified (formatted)"
      fail=1
    else
      psbin="$PS/target/debug/fn-value-qualified"
      if [ ! -x "$psbin" ]; then
        echo "PACKAGE-SPACED-COMPILEFAIL test/package/fn_value_qualified (formatted executable missing)"
        fail=1
      else
        ( cd "$PS" && timeout $TRUN "$psbin" ) >"$PSB" 2>/dev/null </dev/null; pspaced_rc=$?
        if [ "$pspaced_rc" != 42 ]; then
          echo "PACKAGE-SPACED-BEHAVIOUR test/package/fn_value_qualified (exit $pspaced_rc want 42)"
          fail=1
        else
          echo "PACKAGE-SPACED-OK test/package/fn_value_qualified"
        fi
      fi
    fi
  fi
  echo "fmt package fixture=test/package/fn_value_qualified checked=2"

  # A line comment ending in `::` must not become the head of the next Var. This variant is
  # sandbox-only: it keeps the corpus and all three oracles unchanged and accepts a deliberate
  # fail-loud refusal for the ambiguous source.
  PC="$W/package/fn_value_qualified_comment"
  rm -rf "$PC"
  cp -r "$ROOT/test/package/fn_value_qualified" "$PC"
  sed -i \
    -e 's/^  direct := hex::encode(40)$/  x := 41/' \
    -e '/^  indirect := apply(hex::encode, 40)$/d' \
    -e '/^  if direct == 41 and indirect == 41 { 42 } else { 0 }$/c\
  ## a comment ending in a path-looking separator ::\
  x' "$PC/src/main.al"
  PCO1="$W/o/fn_value_qualified.package.comment.f1.al"
  PCO2="$W/o/fn_value_qualified.package.comment.f2.al"
  PCE="$W/o/fn_value_qualified.package.comment.err"
  PCB="$W/o/fn_value_qualified.package.comment.build.out"
  if ! ( cd "$PC" && timeout $TCC "$AL" build package.al ) >"$PCB" 2>"$PCE" </dev/null; then
    echo "PACKAGE-COMMENT-COMPILEFAIL test/package/fn_value_qualified"
    fail=1
  elif ! ( cd "$PC" && timeout $TCC "$AL" fmt src/main.al ) >"$PCO1" 2>"$PCE" </dev/null; then
    echo "PACKAGE-COMMENT-REFUSED test/package/fn_value_qualified"
  elif ! grep -qE '^  x$' "$PCO1" || grep -qF 'separator ::' "$PCO1"; then
    echo "PACKAGE-COMMENT-PATH test/package/fn_value_qualified (comment altered next Var)"
    fail=1
  else
    cp "$PCO1" "$PC/src/main.al"
    if ! ( cd "$PC" && timeout $TCC "$AL" fmt src/main.al ) >"$PCO2" 2>"$PCE" </dev/null; then
      echo "PACKAGE-COMMENT-NONIDEMPOTENT test/package/fn_value_qualified (second fmt refused output)"
      fail=1
    elif ! diff -q "$PCO1" "$PCO2" >/dev/null 2>&1; then
      echo "PACKAGE-COMMENT-NONIDEMPOTENT test/package/fn_value_qualified"
      fail=1
    elif ! ( cd "$PC" && timeout $TCC "$AL" build package.al ) >"$PCB" 2>"$PCE" </dev/null; then
      echo "PACKAGE-COMMENT-COMPILEFAIL test/package/fn_value_qualified (formatted)"
      fail=1
    else
      pcbin="$PC/target/debug/fn-value-qualified"
      if [ ! -x "$pcbin" ]; then
        echo "PACKAGE-COMMENT-COMPILEFAIL test/package/fn_value_qualified (formatted executable missing)"
        fail=1
      else
        ( cd "$PC" && timeout $TRUN "$pcbin" ) >"$PCB" 2>/dev/null </dev/null; pcomment_rc=$?
        if [ "$pcomment_rc" != 41 ]; then
          echo "PACKAGE-COMMENT-BEHAVIOUR test/package/fn_value_qualified (exit $pcomment_rc want 41)"
          fail=1
        else
          echo "PACKAGE-COMMENT-OK test/package/fn_value_qualified"
        fi
      fi
    fi
  fi

  # A string literal containing the comment marker must not be classified as a comment while the
  # formatter looks backward from the following value. This is the exact raw-byte false positive
  # caught by independent review; it is a valid program and must format, build, and run.
  PL="$W/package/fn_value_qualified_literal"
  rm -rf "$PL"
  cp -r "$ROOT/test/package/fn_value_qualified" "$PL"
  sed -i \
    -e 's/^  direct := hex::encode(40)$/  x := 41/' \
    -e '/^  indirect := apply(hex::encode, 40)$/d' \
    -e '/^  if direct == 41 and indirect == 41 { 42 } else { 0 }$/c\
  s := "## ::"\
  x' "$PL/src/main.al"
  PLO1="$W/o/fn_value_qualified.package.literal.f1.al"
  PLO2="$W/o/fn_value_qualified.package.literal.f2.al"
  PLE="$W/o/fn_value_qualified.package.literal.err"
  PLB="$W/o/fn_value_qualified.package.literal.build.out"
  if ! ( cd "$PL" && timeout $TCC "$AL" build package.al ) >"$PLB" 2>"$PLE" </dev/null; then
    echo "PACKAGE-LITERAL-COMPILEFAIL test/package/fn_value_qualified"
    fail=1
  elif ! ( cd "$PL" && timeout $TCC "$AL" fmt src/main.al ) >"$PLO1" 2>"$PLE" </dev/null; then
    echo "PACKAGE-LITERAL-FMT-REFUSE test/package/fn_value_qualified"
    fail=1
  elif ! grep -qF 's := "## ::"' "$PLO1" || ! grep -qE '^  x$' "$PLO1"; then
    echo "PACKAGE-LITERAL-PATH test/package/fn_value_qualified (literal altered or next Var lost)"
    fail=1
  else
    cp "$PLO1" "$PL/src/main.al"
    if ! ( cd "$PL" && timeout $TCC "$AL" fmt src/main.al ) >"$PLO2" 2>"$PLE" </dev/null; then
      echo "PACKAGE-LITERAL-NONIDEMPOTENT test/package/fn_value_qualified (second fmt refused output)"
      fail=1
    elif ! diff -q "$PLO1" "$PLO2" >/dev/null 2>&1; then
      echo "PACKAGE-LITERAL-NONIDEMPOTENT test/package/fn_value_qualified"
      fail=1
    elif ! ( cd "$PL" && timeout $TCC "$AL" build package.al ) >"$PLB" 2>"$PLE" </dev/null; then
      echo "PACKAGE-LITERAL-COMPILEFAIL test/package/fn_value_qualified (formatted)"
      fail=1
    else
      plbin="$PL/target/debug/fn-value-qualified"
      if [ ! -x "$plbin" ]; then
        echo "PACKAGE-LITERAL-COMPILEFAIL test/package/fn_value_qualified (formatted executable missing)"
        fail=1
      else
        ( cd "$PL" && timeout $TRUN "$plbin" ) >"$PLB" 2>/dev/null </dev/null; pliteral_rc=$?
        if [ "$pliteral_rc" != 41 ]; then
          echo "PACKAGE-LITERAL-BEHAVIOUR test/package/fn_value_qualified (exit $pliteral_rc want 41)"
          fail=1
        else
          echo "PACKAGE-LITERAL-OK test/package/fn_value_qualified"
        fi
      fi
    fi
  fi
  # The lexer accepts multiline separators, but the current formatter/lowering boundary cannot
  # safely render their reflowed form. It must refuse rather than silently change runtime behavior.
  PML="$W/package/fn_value_qualified_multiline"
  rm -rf "$PML"
  cp -r "$ROOT/test/package/fn_value_qualified" "$PML"
  sed -i '/^  indirect := apply(hex::encode, 40)$/c\
  indirect := apply(hex\
  ::\
  encode, 40)' "$PML/src/main.al"
  PMLO="$W/o/fn_value_qualified.package.multiline.out"
  PMLE="$W/o/fn_value_qualified.package.multiline.err"
  if ! ( cd "$PML" && timeout $TCC "$AL" fmt src/main.al ) >"$PMLO" 2>"$PMLE" </dev/null; then
    echo "PACKAGE-MULTILINE-REFUSED test/package/fn_value_qualified"
  else
    echo "PACKAGE-MULTILINE-SILENT test/package/fn_value_qualified (multiline path was rewritten)"
    fail=1
  fi

  echo "fmt package fixture=test/package/fn_value_qualified checked=5"
fi

# ==========================================================================================
# WALK 2 — `src/` + `lib/`: the compiler's own MODULES, IDEMPOTENCE ONLY.
#
# A module has no `_start`, so there is no program to run and `run(fmt(x)) == run(x)` is not a
# statement about it. What remains is §4.2's acceptance property, `fmt(fmt(x)) == fmt(x)`, and
# it is the half that was unwatched: `fmt` was non-idempotent on six of these files while walk 1
# stayed green, and one of those non-idempotences DROPPED A STORE on reparse.
#
# Serial on purpose. The whole walk is ~3 s (measured: 3.1 s, 65 files, 128 `fmt` invocations)
# against walk 1's ~10 minutes, so a job pool would buy nothing and cost determinism in the
# order of the output.
#
# Classes (walk 2 only):
#   MOD-IDEM        `fmt(fmt(x)) == fmt(x)`  — the module round-trips
#   MOD-NONIDEM     a second pass changed the text again (or refused its own output)
#   MOD-REFUSE      `fmt` refused the module outright (fail-loud, but it cannot format it)
# ==========================================================================================
if [ "$ONLY" != test ]; then

# The ALLOW list is a table, not a predicate, so an entry that has STOPPED being needed can be
# named. Each line is `CLASS path` and carries a located reason above it. An entry that no
# longer matches anything is reported as `allow-unused` and does NOT fail: a live lane fixing
# one of these must not turn this gate red as its reward. Keep the list shrinking.
MOD_ALLOW=(
  ## `selfhost: fmt — non-braced comptime match arm not modelled`. The renderer has no spelling
  ## for a `comptime match` arm without braces, and refuses rather than guess a canonical form
  ## (the spec posture: a canonical form is normative, so a guess would diverge between
  ## implementations). Needs the arm form modelled in `src/fmt.al`.
  "MOD-REFUSE lib/alloc/fmt.al"
)
mod_allowed() { # class rel -> 0 if this exact (class, path) pair is a reasoned residual
  local k="$1 $2" e
  for e in "${MOD_ALLOW[@]}"; do [ "$e" = "$k" ] && return 0; done
  return 1
}

MW="$W/mod"
rm -rf "$MW"; mkdir -p "$MW/src" "$MW/o"
if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  git -C "$ROOT" ls-files 'src/*.al' 'lib/*.al' | sort > "$MW/list"
else
  ( cd "$ROOT" && find src lib -name '*.al' -type f | sort ) > "$MW/list"
fi
if [ -n "$FILTER" ]; then grep -E "$FILTER" "$MW/list" > "$MW/list2" || true; mv "$MW/list2" "$MW/list"; fi

# `INV` counts `fmt` invocations, so the proof-of-work line reports work actually done rather
# than files merely listed — a `fmt` that refused everything instantly would otherwise print the
# same green summary as a walk that did 128 real renders.
INV=0
: > "$MW/raw"
while read -r rel; do
  [ -n "$rel" ] || continue
  d="$MW/src/$(dirname "$rel")"; mkdir -p "$d"
  cp "$ROOT/$rel" "$MW/src/$rel"
  nm="$(echo "$rel" | tr '/' '_')"
  o1="$MW/o/$nm.f1.al"; o2="$MW/o/$nm.f2.al"; er="$MW/o/$nm.err"
  INV=$((INV+1))
  if ! ( cd "$MW/src" && timeout $TCC "$AL" fmt "$rel" ) >"$o1" 2>"$er" </dev/null; then
    echo "MOD-REFUSE      $rel ($(tr -d '\r' < "$er" | grep -v '^$' | tail -1 | cut -c1-90))" >> "$MW/raw"
    continue
  fi
  if [ ! -s "$o1" ]; then echo "MOD-REFUSE      $rel (empty output)" >> "$MW/raw"; continue; fi
  # Format the SANDBOX COPY IN PLACE: the module's name is its file stem and becomes a GAS
  # symbol, so the second pass has to read a file with the same basename, never a temp name.
  cp "$o1" "$MW/src/$rel"
  INV=$((INV+1))
  if ! ( cd "$MW/src" && timeout $TCC "$AL" fmt "$rel" ) >"$o2" 2>/dev/null </dev/null; then
    echo "MOD-NONIDEM     $rel (re-emit refused its own output)" >> "$MW/raw"; continue
  fi
  if ! diff -q "$o1" "$o2" >/dev/null 2>&1; then
    echo "MOD-NONIDEM     $rel ($(diff "$o1" "$o2" | grep -c '^[<>]') differing line(s))" >> "$MW/raw"
    continue
  fi
  echo "MOD-IDEM        $rel" >> "$MW/raw"
done < "$MW/list"
sort -o "$MW/raw" "$MW/raw"

: > "$MW/regressions"
: > "$MW/seen"
while read -r line; do
  cls=${line%% *}
  rel=$(echo "$line" | awk '{print $2}')
  case "$cls" in
    MOD-IDEM) [ "$SHOW_OK" = 1 ] && echo "$line" ;;
    *) echo "$cls $rel" >> "$MW/seen"
       if mod_allowed "$cls" "$rel"; then echo "allow $line"
       else echo "$line" >> "$MW/regressions"; echo "REGRESSION $line"; fail=1; fi ;;
  esac
done < "$MW/raw"

# An ALLOW entry nobody hit is either a fixed defect or a forgotten one. Say which entries they
# are — informational, never fatal, so a lane that FIXES one is not punished for it.
for e in "${MOD_ALLOW[@]}"; do
  grep -qxF "$e" "$MW/seen" || echo "allow-unused $e (no longer occurs — drop this entry)"
done

echo "fmt corpus walk=src modules=$(wc -l < "$MW/list") checked=$(wc -l < "$MW/raw") fmt_invocations=$INV allow=${#MOD_ALLOW[@]}"
awk '{print $1}' "$MW/raw" | sort | uniq -c | sort -rn
if [ "$(wc -l < "$MW/list")" -lt 1 ]; then
  echo "*** fmt corpus walk=src: no modules found — the walk proved nothing ***"; fail=1
elif [ "$(wc -l < "$MW/raw")" != "$(wc -l < "$MW/list")" ]; then
  echo "*** fmt corpus walk=src: classified $(wc -l < "$MW/raw") of $(wc -l < "$MW/list") modules —"
  echo "    a module produced no line at all, so the walk covered LESS than src/+lib/ ***"; fail=1
elif [ "$INV" -lt "$(wc -l < "$MW/list")" ]; then
  echo "*** fmt corpus walk=src: $INV fmt invocations for $(wc -l < "$MW/list") modules — fewer than"
  echo "    one per module, so the walk did not actually format everything it listed ***"; fail=1
elif [ ! -s "$MW/regressions" ]; then
  echo "*** fmt corpus walk=src: idempotent on every module bar the reasoned residuals ***"
else
  echo "*** fmt corpus walk=src: $(wc -l < "$MW/regressions") NEW failure(s) — see REGRESSION above ***"
fi

fi  # end walk 2

exit $fail
