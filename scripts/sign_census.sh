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
#
# The compiler is `$ALATYR` if set, else this checkout's `target/debug/alatyr`.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 2
AL="${ALATYR:-$ROOT/target/debug/alatyr}"
JOBS=8
ONLY=both
LIST=40
while [ $# -gt 0 ]; do
  case "$1" in
    --jobs) JOBS="$2"; shift 2 ;;
    --only) ONLY="$2"; shift 2 ;;
    --list) LIST="$2"; shift 2 ;;
    *) echo "usage: $0 [--jobs N] [--only corpus|self] [--list N]" >&2; exit 2 ;;
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
  echo "$(wc -l < "$W/corpus.list" | tr -d ' ') sources" > "$W/corpus.meta"
}

run_self() {
  timeout 1800 "$AL" package.al > /dev/null 2> "$W/self.err" 97> "$W/self.rows"
  echo "rc=$?" > "$W/self.meta"
  classify "$W/self.rows" > "$W/self.cls"
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
    }' "$f"
  if [ "$LIST" != 0 ]; then
    for b in x86_64 aarch64 riscv64 wasm; do
      grep -P "^$b\tDISAGREE" "$f" | sort -u | head -n "$LIST" > "$W/list" || true
      if [ -s "$W/list" ]; then
        echo "  $b disagreements (distinct, up to $LIST):"
        sed "s/^$b\t/    /" "$W/list"
      fi
    done
  fi
}

[ "$ONLY" = self ] || run_corpus
[ "$ONLY" = corpus ] || run_self
[ "$ONLY" = self ] || report corpus
[ "$ONLY" = corpus ] || report self
exit 0
