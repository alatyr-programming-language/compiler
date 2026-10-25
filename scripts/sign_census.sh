#!/usr/bin/env bash
# scripts/sign_census.sh — the signedness differential census (`docs/ir.md` §3.8.5; #683, #764–#766).
# REPORTING ONLY: it writes nothing into the tree, reads no oracle, and its exit status says only whether
# the census could be taken.
#
# ## What it compares
#
# For every `/`, `%`, ordering compare (`< > <= >=`) and `shr(x, n)` a compilation meets, two answers:
#
#   * SEMA's — the signedness of the operands' recorded value types (the side table `ir::sty_*`, D6:
#     sema is the single source of types). `lit` is a literal-only operation no context typed; `?` is
#     an operation sema could not type (a sema gap to close, never a default);
#   * each LEGACY EMITTER's — what `x86_64` (`is_signed_expr` / `is_unsigned_cmp`, text and
#     register-allocated paths), `aarch64`, `riscv64` and `wasm` (`*_operand_signed` / `*_cmp_unsigned`)
#     actually chose from the expression's SHAPE.
#
# Both are written by the compiler itself to file descriptor 97 (`ir::sign_row`, `ir::sign_flush_sema`;
# the channel convention of the #299/#529 census instruments), one row per decision:
#
#   #sign <who> <op-byte> <lcol> <rcol> <answer> |<source line>      (op-byte: the AST operator, 0 = shr)
#
# and joined here on (op, columns, source line) within one compilation. A row where sema says `s` and
# the emitter chose `u` (or the reverse) is a #764-class wrong value found mechanically.
#
# ## The sets
#
#   corpus   every tracked `test/*.al`, through all four backends (`alatyr <file>` for x86_64,
#            `alatyr aarch64|riscv64|wat <file>` for the twins). A program the checker refuses has no
#            rows.
#   self     the compiler's OWN source, through x86_64 only (`alatyr package.al`, the GAS dump of the
#            package): this is the answer slice 1 needs in advance — if x86_64 disagrees with sema
#            anywhere in `src/`, moving x86's signedness queries onto sema's table (slice 1, §3.8)
#            changes the compiler's own GAS and slice 1 owes a seed promotion.
#
# ## Usage
#
#   scripts/sign_census.sh [--jobs N] [--only corpus|self] [--list N]
#     --list N   print up to N distinct disagreeing rows per backend (default 40; 0 = none)
#   scripts/sign_census.sh --self-test
#     compiles three planted programs and checks the `#signrec` columns (docs/ir-slice-1.md §8.5): a
#     generic instance's operands are unknown with no context and typed in their instance; a
#     `comptime for` member's are unknown in the instance alone and typed per iteration; a pack
#     element's likewise. Exit 0 only when every check holds.
#
# ## The records x86 can read (`#signrec`, docs/ir-slice-1.md §8.4)
#
# Beside each x86 decision the compiler writes the operands' records three ways: with no context, in
# the instance the emitter is in, and in that instance and the `comptime for` iteration path. An operand
# whose record is `U` (sema could not type it) or `A` (no record in that context) is residue: a decision
# no record answers. The report counts residue rows and distinct lines per context, and the lines the
# iteration key makes known (residue with the instance alone, none with the iteration).
#
# The compiler is `$ALATYR` if set, else this checkout's `target/debug/alatyr`.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 2
AL="${ALATYR:-$ROOT/target/debug/alatyr}"
JOBS=8
ONLY=both
LIST=40
SELFTEST=0
GATE=0
RATCHET_WRITE=0
BASELINE="$ROOT/scripts/sign_census.baseline"
while [ $# -gt 0 ]; do
  case "$1" in
    --self-test) SELFTEST=1; shift ;;
    --gate) GATE=1; shift ;;
    --ratchet-write) RATCHET_WRITE=1; shift ;;
    --jobs) JOBS="$2"; shift 2 ;;
    --only) ONLY="$2"; shift 2 ;;
    --list) LIST="$2"; shift 2 ;;
    *) echo "usage: $0 [--jobs N] [--only corpus|self] [--list N] [--gate] [--ratchet-write] | --self-test" >&2; exit 2 ;;
  esac
done
case "$ONLY" in both|corpus|self) ;; *) echo "usage: --only corpus|self" >&2; exit 2 ;; esac
[ -x "$AL" ] || { echo "sign_census: no compiler at $AL (build it first)" >&2; exit 2; }
ulimit -c 0
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT

# The join, over one compilation's rows: every non-sema row is classified against sema's row for the
# same (op, lcol, rcol, line). Output: one line per emitter row, `<who> <class> <op> <line-key>`.
classify() {
  awk '
    BEGIN { OPN[19] = "/"; OPN[29] = "%"; OPN[24] = "<"; OPN[25] = ">"; OPN[26] = "<="; OPN[27] = ">="; OPN[0] = "shr" }
    /^#sign / {
      who = $2; op = OPN[$3]; lc = $4; rc = $5; ans = $6
      i = index($0, " |"); line = substr($0, i + 2)
      key = op SUBSEP lc SUBSEP rc SUBSEP line
      if (who == "sema") {
        if ((key in sema) && sema[key] != ans) sema[key] = "ambig"; else sema[key] = ans
        next
      }
      n++; W[n] = who; K[n] = key; A[n] = ans; L[n] = op " " lc " " rc " |" line
    }
    END {
      for (j = 1; j <= n; j++) {
        k = K[j]
        if (!(k in sema)) cls = "sema-absent"
        else if (sema[k] == "lit") cls = "sema-lit"
        else if (sema[k] == "?") cls = "sema-unknown"
        else if (sema[k] == "ambig") cls = "sema-ambiguous"
        else if (sema[k] == A[j]) cls = "agree"
        else cls = "DISAGREE(sema=" sema[k] ",emitter=" A[j] ")"
        print W[j] "\t" cls "\t" L[j]
      }
    }' "$1"
}

# The records x86 can read at each of its legacy signedness decisions (`#signrec`, docs/ir-slice-1.md
# §8.4): per operand, the record with no context, in the instance alone, and in the instance and the
# comptime-for iteration path the emitter is in. An operand whose record is `U` (sema could not type it)
# or `A` (no record in that context) is RESIDUE: a decision no record answers. Output, one line per
# decision: `<file>\t<n>\t<i>\t<c>\t<line>`, each of n/i/c `ok` or `res`.
records() { # file-key rows-file
  awk -v f="$1" '
    function res(pair) { return (pair ~ /(^|,)(U|A)(,|$)/) ? "res" : "ok" }
    /^#signrec / {
      i = index($0, " |"); line = substr($0, i + 2)
      print f "\t" res($5) "\t" res($6) "\t" res($7) "\t" $2 " " $3 " " $4 " |" line
    }' "$2"
}

run_corpus() {
  git ls-files 'test/*.al' | sort -u > "$W/corpus.list"
  export AL W
  one() {
    f="$1"; key=$(printf '%s' "$f" | tr '/' '_')
    timeout 60 "$AL" "$f" > /dev/null 2>&1 97> "$W/r.$key.x86"
    timeout 60 "$AL" aarch64 "$f" > /dev/null 2>&1 97> "$W/r.$key.a64"
    timeout 60 "$AL" riscv64 "$f" > /dev/null 2>&1 97> "$W/r.$key.rv"
    timeout 60 "$AL" wat "$f" > /dev/null 2>&1 97> "$W/r.$key.wat"
  }
  export -f one
  xargs -P "$JOBS" -I{} bash -c 'one "$@"' _ {} < "$W/corpus.list"
  for r in "$W"/r.*; do [ -s "$r" ] && classify "$r"; done > "$W/corpus.cls"
  for r in "$W"/r.*.x86; do [ -s "$r" ] && records "$(basename "$r" .x86)" "$r"; done > "$W/corpus.rec"
  echo "$(wc -l < "$W/corpus.list" | tr -d ' ') sources" > "$W/corpus.meta"
}

run_self() {
  timeout 1800 "$AL" package.al > /dev/null 2> "$W/self.err" 97> "$W/self.rows"
  echo "rc=$?" > "$W/self.meta"
  classify "$W/self.rows" > "$W/self.cls"
  records self "$W/self.rows" > "$W/self.rec"
}

report() { # set
  local set="$1" f="$W/$1.cls"
  echo "sign census — $set ($(cat "$W/$set.meta")): emitter decisions against sema's recorded types"
  awk -F'\t' '
    { who = $1; c = $2; sub(/\(.*/, "", c); n[who]++; k[who, c]++; seen[c] = 1 }
    END {
      printf "  %-8s %8s %8s %9s %9s %12s %12s %15s\n", "backend", "rows", "agree", "DISAGREE", "sema-lit", "sema-unknown", "sema-absent", "sema-ambiguous"
      split("x86_64 aarch64 riscv64 wasm", B, " ")
      for (i = 1; i <= 4; i++) {
        b = B[i]; if (!(b in n)) continue
        printf "  %-8s %8d %8d %9d %9d %12d %12d %15d\n", b, n[b], k[b, "agree"], k[b, "DISAGREE"], k[b, "sema-lit"], k[b, "sema-unknown"], k[b, "sema-absent"], k[b, "sema-ambiguous"]
      }
      ## Machine-readable: the DISAGREE count per backend, for the gate ratchet. A backend that made
      ## NO decision at all prints -1, never a skipped line: an absent backend is not a zero, and a
      ## zero here would read as "this emitter now agrees with sema everywhere" when it simply did not
      ## answer. The gate turns -1 into a failure.
      printf "sign census counts %s:", SET
      for (i = 1; i <= 4; i++) { b = B[i]; printf " %s=%d", b, (b in n) ? k[b, "DISAGREE"] : -1 }
      printf "\n"
    }' SET="$set" "$f"
  # The x86 records report: residue decisions (rows) and distinct source lines (file + line text),
  # under each context; "known with the iteration" is the residue the iteration key (e4) answers.
  awk -F'\t' '
    { n++; k = $1 "|" $5
      if ($2 == "res") { rn++; ln[k] = 1 }
      if ($3 == "res") { ri++; li[k] = 1 }
      if ($4 == "res") { rc++; lc[k] = 1 }
      if ($3 == "res" && $4 == "ok") { mk[k] = 1 } }
    function cnt(a,   x, c) { c = 0; for (x in a) c++; return c }
    END {
      printf "  x86_64 records at %d decisions — residue (an operand U or A): no context %d rows / %d lines; instance %d / %d; instance+iteration %d / %d\n", n, rn, cnt(ln), ri, cnt(li), rc, cnt(lc)
      printf "  lines the iteration key makes known (residue with the instance alone, none with the iteration): %d\n", cnt(mk)
    }' "$W/$set.rec"
  if [ "$LIST" != 0 ]; then
    awk -F'\t' '$2 == "res" || $3 == "res" || $4 == "res" { print $1 "\tnone=" $2 " inst=" $3 " inst+iter=" $4 "\t" $5 }' "$W/$set.rec" | sort -u | head -n "$LIST" > "$W/rlist" || true
    if [ -s "$W/rlist" ]; then
      echo "  x86_64 residue under any context, with each context's answer (distinct, up to $LIST):"
      sed 's/^/    /' "$W/rlist"
    fi
    for b in x86_64 aarch64 riscv64 wasm; do
      grep -P "^$b\tDISAGREE" "$f" | sort -u | head -n "$LIST" > "$W/list" || true
      if [ -s "$W/list" ]; then
        echo "  $b disagreements (distinct, up to $LIST):"
        sed "s/^$b\t/    /" "$W/list"
      fi
    done
  fi
}

# The census self-test (docs/ir-slice-1.md §8.5): planted programs, expected `#signrec` columns.
self_test() {
  local fails=0 checks=0
  cat > "$W/st_inst.al" <<'AL'
lt := fn(T : type, a : T, b : T) -> bool { return a < b }
main := fn() -> u64 {
  x : i64 = 0 - 1
  y : u64 = 1
  if lt(i64, x, 1) and lt(u64, y, 2) { return 42 }
  0
}
AL
  cat > "$W/st_member.al" <<'AL'
P := struct { a : u64, b : i64 }
lessf := fn(T : type, x : T, y : T) -> u64 {
  mut n : u64 = 0
  comptime for f in typeinfo(T).fields {
    if x.(f) < y.(f) { n = n + 1 }
  }
  n
}
main := fn() -> u64 {
  p := P(a = 1, b = 0 - 5)
  q := P(a = 2, b = 3)
  lessf(P, p, q) + 40
}
AL
  cat > "$W/st_pack.al" <<'AL'
maxof := fn(first : u64, rest : ...) -> u64 {
  mut m := first
  comptime for v in rest {
    if v > m { m = v }
  }
  return m
}
main := fn() -> u64 {
  a : u64 = 42
  b : u64 = 7
  return maxof(u64(3), a, b)
}
AL
  # check <program> <description> <regex over the #signrec rows>
  check() {
    checks=$((checks + 1))
    if grep -qE "$3" "$W/st_$1.rows"; then echo "ok   $1: $2"
    else echo "FAIL $1: $2 (no row matches /$3/)"; sed 's/^/     /' "$W/st_$1.rows"; fails=$((fails + 1)); fi
  }
  for p in inst member pack; do
    "$AL" "$W/st_$p.al" > /dev/null 2> "$W/st_$p.err" 97> "$W/st_$p.rows"
    rc=$?
    checks=$((checks + 1))
    if [ "$rc" = 0 ] && grep -q '^#signrec ' "$W/st_$p.rows"; then echo "ok   $p: compiles (rc 0) and writes #signrec rows"
    else echo "FAIL $p: rc=$rc, $(grep -c '^#signrec ' "$W/st_$p.rows") #signrec rows"; sed 's/^/     /' "$W/st_$p.err" | head -5; fails=$((fails + 1)); fi
  done
  check inst "i64 instance: unknown with no context, signed in the instance" '^#signrec 24 [0-9]+ [0-9]+ U,U Is,Is Is,Is '
  check inst "u64 instance: unknown with no context, unsigned in the instance" '^#signrec 24 [0-9]+ [0-9]+ U,U Iu,Iu Iu,Iu '
  check member "field a: unknown in the instance alone, unsigned in its iteration" '^#signrec 24 [0-9]+ [0-9]+ U,U U,U Iu,Iu '
  check member "field b: unknown in the instance alone, signed in its iteration" '^#signrec 24 [0-9]+ [0-9]+ U,U U,U Is,Is '
  check pack "pack element: no record outside its iteration, unsigned in it" '^#signrec 25 [0-9]+ [0-9]+ U,Iu U,Iu Iu,Iu '
  # The ratchet over the planted counts: held, grown-closed, FAIL on growth, and never a pass when a
  # backend is unheld or the census answered nothing there (-1).
  printf 'x86_64=4 aarch64=165 riscv64=156 wasm=158\n' > "$W/corpus.counts"
  printf 'x86_64=4\naarch64=165\nriscv64=156\nwasm=158\n' > "$W/sb_ok"
  printf 'x86_64=4\naarch64=165\nriscv64=156\n' > "$W/sb_unheld"
  printf 'x86_64=9\naarch64=165\nriscv64=156\nwasm=158\n' > "$W/sb_high"
  printf 'x86_64=x\naarch64=165\nriscv64=156\nwasm=158\n' > "$W/sb_bad"
  sign_ratchet "$W/sb_ok" >/dev/null 2>&1; rc=$?
  checks=$((checks + 1)); [ "$rc" = 0 ] && echo "ok   sign ratchet self-test: held at the line" || { echo "FAIL sign ratchet held (rc=$rc)"; fails=$((fails + 1)); }
  printf 'x86_64=3 aarch64=100 riscv64=156 wasm=158\n' > "$W/corpus.counts"
  sign_ratchet "$W/sb_ok" >/dev/null 2>&1; rc=$?
  checks=$((checks + 1)); [ "$rc" = 0 ] && echo "ok   sign ratchet self-test: closing disagreements is not a failure" || { echo "FAIL sign ratchet closed (rc=$rc)"; fails=$((fails + 1)); }
  printf 'x86_64=5 aarch64=165 riscv64=156 wasm=158\n' > "$W/corpus.counts"
  out="$(sign_ratchet "$W/sb_ok" 2>&1)"; rc=$?
  checks=$((checks + 1))
  if [ "$rc" = 1 ] && printf '%s\n' "$out" | grep -q 'x86_64 disagrees'; then echo "ok   sign ratchet self-test: FAIL when a backend grows its disagreements, and names it"
  else echo "FAIL sign ratchet grew (rc=$rc)"; fails=$((fails + 1)); fi
  printf 'x86_64=4 aarch64=165 riscv64=156 wasm=-1\n' > "$W/corpus.counts"
  sign_ratchet "$W/sb_ok" >/dev/null 2>&1; rc=$?
  checks=$((checks + 1)); [ "$rc" = 2 ] && echo "ok   sign ratchet self-test: a blind backend (-1) is not a pass" || { echo "FAIL sign ratchet blind (rc=$rc)"; fails=$((fails + 1)); }
  printf 'x86_64=4 aarch64=165 riscv64=156 wasm=158\n' > "$W/corpus.counts"
  sign_ratchet "$W/sb_unheld" >/dev/null 2>&1; rc=$?
  checks=$((checks + 1)); [ "$rc" = 2 ] && echo "ok   sign ratchet self-test: a baseline naming no wasm leaves it unheld" || { echo "FAIL sign ratchet unheld (rc=$rc)"; fails=$((fails + 1)); }
  sign_ratchet "$W/sb_bad" >/dev/null 2>&1; rc=$?
  checks=$((checks + 1)); [ "$rc" = 2 ] && echo "ok   sign ratchet self-test: a malformed baseline is not a pass" || { echo "FAIL sign ratchet malformed (rc=$rc)"; fails=$((fails + 1)); }
  sign_ratchet "$W/sb_high" >/dev/null 2>&1; rc=$?
  checks=$((checks + 1)); [ "$rc" = 0 ] && echo "ok   sign ratchet self-test: a baseline above the measurement holds" || { echo "FAIL sign ratchet above (rc=$rc)"; fails=$((fails + 1)); }
  echo "sign_census self-test: $checks checks, $fails failed"
  [ "$fails" = 0 ]
}
# The ratchet over the corpus table. Each backend's DISAGREE count may not GROW: every disagreement is
# one `/ % < > <= >=` where the emitter chose a signedness from the expression's SHAPE that differs from
# the type sema recorded — a #764/#765/#766-class wrong value, found by the census instead of by a
# generator's luck. A backend at -1 answered no decisions at all: the census went blind, which is not a
# zero and never a pass. 0 held, 1 GREW, 2 the baseline is unusable.
sign_ratchet() { # baseline-file  reads "$W/corpus.counts" (backend=count pairs)
  local f="$1"
  [ -s "$f" ] || { echo "sign ratchet: NO baseline at $f — write it with:" \
    ; echo "  scripts/sign_census.sh --gate --ratchet-write" >&2; return 2; }
  local be want have rc=0 seen=""
  while read -r line; do
    [ -n "$line" ] || continue
    case "$line" in *=*) ;; *) echo "sign ratchet: malformed baseline line '$line'" >&2; return 2 ;; esac
    be="${line%%=*}"; want="${line#*=}"
    case "$want" in ''|*[!0-9]*) echo "sign ratchet: malformed baseline line '$line'" >&2; return 2 ;; esac
    case "$be" in x86_64|aarch64|riscv64|wasm) ;; *) echo "sign ratchet: unknown backend '$be'" >&2; return 2 ;; esac
    seen="$seen $be"
    have=$(tr ' ' '\n' < "$W/corpus.counts" | grep "^$be=" | head -1 | cut -d= -f2)
    case "$have" in ''|*-*) echo "sign ratchet: no measurement for $be (blank or -1 — the census did not answer there)" >&2; return 2 ;; esac
    if [ "$have" -gt "$want" ]; then
      echo "sign ratchet: FAIL — $be disagrees with sema's recorded signedness MORE than the baseline: $want -> $have"
      echo "  Each new disagreement is one signedness chosen from shape instead of from the type (§3.8)."
      rc=1
    elif [ "$have" -lt "$want" ]; then
      echo "sign ratchet: $be CLOSED some disagreements $want -> $have; lower the baseline."
    fi
  done < "$f"
  for be in x86_64 aarch64 riscv64 wasm; do
    case " $seen " in *" $be "*) ;; *) echo "sign ratchet: baseline names no $be — that backend is unheld" >&2; return 2 ;; esac
  done
  return $rc
}

if [ "$SELFTEST" = 1 ]; then self_test; exit $?; fi

[ "$ONLY" = self ] || run_corpus
[ "$ONLY" = corpus ] || run_self
if [ "$ONLY" = self ]; then
  [ "$ONLY" = corpus ] || report self
  exit 0
fi
report corpus | tee "$W/corpus.report"
grep '^sign census counts corpus:' "$W/corpus.report" | tail -1 | sed 's/^sign census counts corpus://' > "$W/corpus.counts"
if [ "$RATCHET_WRITE" = 1 ]; then
  tr ' ' '\n' < "$W/corpus.counts" | grep -v '^$' > "$BASELINE" || exit 2
  echo "sign ratchet: WROTE $BASELINE ($(tr '\n' ' ' < "$BASELINE"))"
  exit 0
fi
[ "$ONLY" = corpus ] || report self
if [ "$GATE" = 1 ]; then
  sign_ratchet "$BASELINE"; rc=$?
  case "$rc" in
    0) echo "sign census gate: no backend grew its disagreement with sema's recorded signedness" ;;
    1) echo "*** sign census gate: FAIL — a backend chose signedness from shape where sema recorded otherwise (§3.8) ***" ;;
    *) echo "*** sign census gate: FAIL — the ratchet could not judge (above); an unheld backend is not a pass ***" ;;
  esac
  exit $rc
fi
exit 0
