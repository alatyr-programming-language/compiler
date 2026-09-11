#!/usr/bin/env bash
# scripts/wildcard_arm_check.sh — the gate's WILDCARD-ARM check: a change may not ADD an
# unacknowledged `_ =>` match arm over an ENUMERABLE scrutinee (issue #658).
#
# WHY THIS EXISTS, AND WHY IT IS AN ADDITION RULE RATHER THAN A LIMIT
# ------------------------------------------------------------------
# A `_ =>` arm over a project `enum` absorbs every variant nobody thought about, including the ones
# added after the arm was written. That is not a style opinion; it is the measured defect class this
# repository keeps producing. #544's census parsed 727 such arms and measured what happens when one
# is deleted: in 249 of the 727 the deletion is SILENT — `check` exits 0, `build` exits 0, and the
# `match` with no arm taken returns −1 at run time (`run rc=255`), with no diagnostic anywhere. So
# the arms already in the tree cannot be swept; each one has to be enumerated by hand, by the #544
# stage-1 procedure in `.agents/skills/alatyr-lane/wildcard_enumeration.md`.
#
# The asymmetry that gives this file its shape was measured too. Between `6759a95` and `6fe1e1d` the
# tree-wide total went 727 -> 731 in a single day: lane #651 added one arm each to `src/aarch64.al`,
# `src/riscv64.al`, `src/wat.al` and `src/lower_layout.al` and nothing was removed. Stage 1 then
# landed two whole files — `src/lower_ctx.al` 24 -> 2 (#661) and `src/aarch64.al` 69 -> 33 (#678),
# about 58 arms — and the tree-wide count did not move. Removal and addition were running at the
# same rate, so the headline metric of the stage repairing this was flat while the stage was working
# at full speed. Refusing unacknowledged ADDITIONS while letting removals through converts that
# stalemate into a monotone decrease at whatever rate stage 1 manages, and it costs the author of a
# new arm nothing: they are present, they know which forms the arm absorbs, and they can either
# enumerate them or write down why the wildcard is required.
#
# WHY `_` OVER `Expr` IS NOT THE SAME THING AS `_` OVER `u8`
# ----------------------------------------------------------
# Over an integer or a byte the domain is not enumerable by hand and `_` is the only way to spell
# "everything else"; the census found exactly FOUR such arms in the whole tree, which is why this
# rule almost never fires on a correct use. Over `ast::Expr` the domain is a list in `src/ast.al`
# that a later commit will extend, and the difference is what the compiler does when it is extended:
# a spelled-out group arm makes the new variant a `check: type mismatch` naming the file and line,
# and a `_` makes it a silently absorbed case. That is the whole of the rule, and it is decided from
# the SCRUTINEE'S RESOLVED TYPE, never from the arm's own text.
#
# WHY THERE IS NO FOURTH ORACLE
# -----------------------------
# This repository keeps exactly three oracle files, each with a one-open-PR rule and a `-merge`
# attribute. A committed baseline number would be a fourth in spirit — something to regenerate,
# something to drift, something two lanes can conflict over. #649's `scripts/corpus_enum_check.sh`
# established the better shape: it holds no oracle at all and compares two things the repository
# already contains. So does this file. It counts the arms in the MERGE BASE and in the head and
# refuses an increase; there is no committed number, nothing to regenerate, and nothing to merge.
# It also answers better than a baseline would: a baseline says "you are above the line", which
# invites arguing about the line, while a merge-base delta says "you added one, here it is, on this
# line", which is a fact about the change under review.
#
# HOW THE ARMS ARE COUNTED, AND WHY NOT WITH grep
# -----------------------------------------------
# `scripts/wildcard_arm_scan.awk` tokenizes the source with `src/lexrt.al`'s lexical rules and walks
# each `match`'s arm list. The census measured 727 real arms where `grep -c '_ =>'` answered 497,
# and the error is not a constant: `src/parser.al` has 27 grep hits of which THREE are band comments
# quoting the token in prose (lines 1704, 3102, 3548 at the time of writing), while twenty of
# `src/lower_ctx.al`'s arms were invisible to `grep -cE '^\s+_ =>'` because they sit inline in
# one-line accessors. A grep-based gate fires on a comment and misses a real arm, which is exactly
# how a check earns a reputation for being wrong and gets routed around.
#
# WHAT IS EXEMPT, AND IT IS WRITTEN DOWN RATHER THAN GUESSED
# ----------------------------------------------------------
#   literal   every sibling pattern in the same `match` is an integer/char/string literal or a
#             range: a non-enumerable scrutinee, where `_` is legitimate. FOUR arms tree-wide
#             (`src/comptime.al` once, `src/lower.al` three times — the register-name tables).
#   comptime  a `comptime match typeinfo(T)` kind dispatch, or the generic `T.(v)` comptime-variant
#             pattern `lib/base/derive.al` uses. The kind set is closed, but it is not a project
#             `enum` declaration this scanner can name, so it is exempt AND reported by count, not
#             silently dropped.
# A group arm that spells out its variants is not a wildcard at all and never reaches this check;
# that is the form `.agents/skills/alatyr-lane/wildcard_enumeration.md` §3 defines, and #544
# deliberately granted no exemption for the single-case accessor shape.
#
# HOW TO ACKNOWLEDGE ONE
# ----------------------
# Put `wildcard-ok: <reason>` in a comment on the arm's own line, or on the line immediately above
# it. A non-empty reason is required. The marker lives WHERE THE ARM LIVES, not in a commit message
# or a PR body, for the reason #649 records: a rule kept anywhere but the enforcement point is a
# rule people route around, and a reviewer reading the arm three months later reads the reason with
# it.
#
#     ## wildcard-ok: the scrutinee is a lexer token KIND (a `usize`), not a project enum.
#     _ => { r = false }
#
# `scripts/dev.sh` deliberately does NOT run this, for the reason `scripts/corpus_enum_check.sh`
# gives for itself: the fast loop is run fifty times a day and a check that nags through a
# half-finished refactor only teaches people to skip the fast loop. It is cheap enough to run on its
# own whenever you want the answer — about 8 s over `src/` + `lib/`, no compiler — and
# `scripts/full.sh` runs it before it builds anything, so the author hears about a new arm at the
# cheapest moment the authoritative gate has.
#
# Usage (inside `nix develop`):  bash scripts/wildcard_arm_check.sh [<base-rev>]
#                                bash scripts/wildcard_arm_check.sh --list [<root>]
#                                bash scripts/wildcard_arm_check.sh --self-test
# Base resolution, in order: `$1`, `$ALATYR_WILDCARD_BASE`, `git merge-base origin/main HEAD`,
# `git merge-base main HEAD`. On `main` itself the merge base IS the head, so the delta is zero and
# this check is green by construction.
# Exit 0 = no unacknowledged addition.  1 = an addition (the arms are named).  2 = the check could
#       not be performed (no resolvable base, not a git work tree, or an EMPTY corpus — a check that
#       counted nothing must not read as a pass).
set -u
## The per-file counts are joined with `sort` + `join`, and those two must agree on collation or the
## join silently drops rows. Pin it for the whole script; everything this file parses is ASCII.
export LC_ALL=C
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCAN="$ROOT/scripts/wildcard_arm_scan.awk"

## The pathspecs, spelled exactly as scripts/idiom_gate.sh and scripts/fmt_corpus.sh's second walk
## spell them. git's `*` matches `/`, so `src/*.al` also selects `src/lower/**`.
WA_PATHSPECS=('src/*.al' 'lib/*.al')
WA_ROOTS=(src lib)

## Scan one directory. A git work tree is enumerated from the INDEX (the same enumeration the two
## source-reading oracle stages use, and `scripts/corpus_enum_check.sh` has already proved the index
## and the worktree name the same `.al` set by the time this runs); a plain directory — the base
## tree this script extracts, and the self-test's planted trees — is enumerated with `find`, which
## over a `git archive` extraction is the same set by construction.
wa_scan() { # dir -> rows on stdout
  local d="$1" list
  list="$(mktemp)" || return 2
  if git -C "$d" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    ( cd "$d" && git ls-files -- "${WA_PATHSPECS[@]}" ) | sort > "$list"
  else
    ( cd "$d" && find "${WA_ROOTS[@]}" \( -type f -o -type l \) -name '*.al' -print 2>/dev/null ) |
      sed 's|^\./||' | sort > "$list"
  fi
  if [ ! -s "$list" ]; then rm -f "$list"; return 3; fi
  ## ONE awk invocation, never `xargs`. The `enum` declarations and their variant names are collected
  ## in the same pass as the arms and resolved at END, so a list split across two invocations would
  ## resolve the second batch against an empty table and silently reclassify every arm in it as
  ## exempt. `mapfile` also carries a path holding whitespace, which word splitting would not.
  local files=() rc
  mapfile -t files < "$list"
  ( cd "$d" && awk -f "$SCAN" -- "${files[@]}" )
  rc=$?
  rm -f "$list"
  return "$rc"
}

## The COUNTED set: an arm over an enumerable scrutinee that carries no acknowledgement. `none` — a
## `match` with no sibling arm to resolve against — counts too, and fails closed on purpose: an
## unresolvable scrutinee is not evidence that the scrutinee is a byte.
wa_counted() { awk -F'\t' '($4 == "enum" || $4 == "none") && $5 == 0' ; }

## THE DECIDER. Two directories in, a verdict out. The self-test drives THIS function against
## planted trees, because a stage whose failure verdict is only ever reached by the real tree is a
## verdict nobody has ever seen fail (issue #600).
wa_decide() { # base-dir head-dir base-label [head-git-rev-for-line-locating]
  local bd="$1" hd="$2" label="$3" difbase="${4:-}"
  local w brc hrc bn hn nf acked lit ct none bad=0

  w="$(mktemp -d)" || return 2
  wa_scan "$bd" > "$w/base.rows"; brc=$?
  wa_scan "$hd" > "$w/head.rows"; hrc=$?
  if [ "$brc" = 3 ] || [ "$hrc" = 3 ]; then
    echo "wildcard arms: FAIL — one of the two trees holds ZERO tracked .al files under ${WA_PATHSPECS[*]};" >&2
    echo "  there is nothing to compare and this check proved nothing. Refusing to report a result." >&2
    rm -rf "$w"; return 2
  fi
  if [ "$brc" != 0 ] || [ "$hrc" != 0 ]; then
    echo "wildcard arms: FAIL — the scanner exited non-zero (base rc=$brc head rc=$hrc)." >&2
    rm -rf "$w"; return 2
  fi

  wa_counted < "$w/base.rows" > "$w/base.counted"
  wa_counted < "$w/head.rows" > "$w/head.counted"
  bn="$(wc -l < "$w/base.counted")"; hn="$(wc -l < "$w/head.counted")"
  nf="$(cut -f1 "$w/head.rows" | sort -u | wc -l)"
  acked="$(awk -F'\t' '$5 == 1' "$w/head.rows" | wc -l)"
  lit="$(awk -F'\t' '$4 == "literal"'  "$w/head.rows" | wc -l)"
  ct="$(awk -F'\t'  '$4 == "comptime"' "$w/head.rows" | wc -l)"
  none="$(awk -F'\t' '$4 == "none"'    "$w/head.rows" | wc -l)"

  if [ "$hn" -gt "$bn" ]; then
    bad=1
    echo "wildcard arms: FAIL — $((hn - bn)) unacknowledged \`_ =>\` arm(s) over an ENUMERABLE scrutinee" >&2
    echo "  were ADDED relative to $label ($bn -> $hn)." >&2
    ## Name the arms. Per-file first, because that is where the delta is attributable, and then the
    ## exact lines — marked `+` when the diff against the base actually touched them, so the author
    ## reads the added arm rather than the file's whole inventory.
    cut -f1 "$w/base.counted" | sort | uniq -c | awk '{print $2"\t"$1}' | sort > "$w/base.per"
    cut -f1 "$w/head.counted" | sort | uniq -c | awk '{print $2"\t"$1}' | sort > "$w/head.per"
    join -t"$(printf '\t')" -a2 -e0 -o 0,1.2,2.2 "$w/base.per" "$w/head.per" |
      awk -F'\t' '$3 > $2 {printf "    %s: %d -> %d\n", $1, $2, $3}' >&2
    if [ -n "$difbase" ]; then
      : > "$w/added"
      while IFS=$'\t' read -r f bc hc; do
        [ "$hc" -gt "$bc" ] || continue
        git -C "$hd" diff --unified=0 "$difbase" -- "$f" 2>/dev/null |
          awk '/^@@/ { split($3, a, ","); s = a[1] + 0; if (s < 0) s = -s; n = (a[2] == "" ? 1 : a[2] + 0)
                       if (n > 0) print s"\t"(s + n - 1) }' > "$w/hunks"
        awk -F'\t' -v f="$f" '$1 == f {print $2}' "$w/head.counted" | sort -n | while read -r ln; do
          if awk -F'\t' -v l="$ln" '$1 <= l && l <= $2 {found = 1} END {exit !found}' "$w/hunks" 2>/dev/null; then
            echo "    + $f:$ln" >> "$w/added"
          fi
        done
      done < <(join -t"$(printf '\t')" -a2 -e0 -o 0,1.2,2.2 "$w/base.per" "$w/head.per")
      if [ -s "$w/added" ]; then
        echo "  on lines this change touched:" >&2
        head -40 "$w/added" >&2
      fi
    fi
    echo "  A \`_\` over a project enum absorbs every variant added after it, and the compiler cannot" >&2
    echo "  tell you: #544's census measured that a match with no arm taken returns -1 with rc 0 from" >&2
    echo "  both \`check\` and \`build\`, so the cost is paid later, silently, by somebody else." >&2
    echo "  Fix, in order of preference: spell the absorbed variants as one OR-pattern group arm" >&2
    echo "  (.agents/skills/alatyr-lane/wildcard_enumeration.md §3), or — if the wildcard is really" >&2
    echo "  required — acknowledge it WHERE IT LIVES, on its own line or the line above it:" >&2
    echo "      ## wildcard-ok: <why this scrutinee cannot be enumerated here>" >&2
  fi

  ## Proof of work on the same line as the verdict: a green line with no counts cannot be told apart
  ## from a check that scanned nothing, and that is the failure mode every stage of this gate is
  ## built to refuse.
  echo "wildcard arms: base=$label files=$nf base_arms=$bn head_arms=$hn delta=$((hn - bn)) acked=$acked exempt_literal=$lit exempt_comptime=$ct unresolved=$none pathspecs=${WA_PATHSPECS[*]}"
  if [ "$bad" = 0 ]; then
    echo "*** wildcard arms: no unacknowledged \`_ =>\` arm over an enumerable scrutinee was added ***"
  else
    echo "*** wildcard arms: this change ADDS unacknowledged \`_ =>\` arms over enumerable scrutinees ***"
  fi
  rm -rf "$w"
  return "$bad"
}

wa_resolve_base() {
  if [ -n "${WA_BASE_ARG:-}" ]; then git -C "$ROOT" rev-parse --verify -q "${WA_BASE_ARG}^{commit}" && return 0; return 1; fi
  if [ -n "${ALATYR_WILDCARD_BASE:-}" ]; then git -C "$ROOT" rev-parse --verify -q "${ALATYR_WILDCARD_BASE}^{commit}" && return 0; return 1; fi
  git -C "$ROOT" merge-base origin/main HEAD 2>/dev/null && return 0
  git -C "$ROOT" merge-base main HEAD 2>/dev/null && return 0
  return 1
}

# ======================================================================================================
# THE GATE-OF-THE-GATE (issue #600). Twelve planted trees, 6 + 1 + 5: SIX added arms the decider must
# refuse BY NAME — one of them in a real git tree, so the `+ path:line` locator is reached too — ONE
# tree it must refuse to report on at all, and FIVE controls that must stay green. The controls are not padding — without them a
# decider that simply always failed would score full marks here — and they are chosen to pin down the
# two things this check is most likely to get wrong: the exemption (an integer scrutinee, a comptime
# kind dispatch) and the tokenizer (an arm quoted in PROSE, and an arm hidden inline in a one-line
# accessor, which are the two directions in which a grep-based count is measurably wrong).
# ======================================================================================================
_wa_base_tree() { # dir
  local d="$1"
  mkdir -p "$d/src" "$d/lib"
  cat > "$d/src/ast.al" <<'AL'
pub Expr := enum { Num(i64), Var(usize), Call(usize) }
pub Stmt := enum { Let(usize), Ret(usize) }
AL
  cat > "$d/src/use.al" <<'AL'
(Expr, Stmt) := ast
pub f := fn(v : ptr(Expr)) -> bool {
  mut r := false
  match deref(v) {
    Expr::Num(a) => { r = true }
    Expr::Var | Expr::Call => {}
  }
  r
}
pub g := fn(i : usize) -> bool {
  mut r := false
  match i {
    0 => { r = true }
    _ => {}
  }
  r
}
pub h := fn(v : ptr(Expr)) -> bool {
  mut r := false
  match deref(v) {
    Expr::Call(a) => { r = true }
    _ => {}
  }
  r
}
AL
  printf 'pub one := fn() -> u64 { 1 }\n' > "$d/lib/rt.al"
}

_wa_case() { # label base-dir head-dir want-rc [DIFFBASE=<rev>] needle...
  local label="$1" bd="$2" hd="$3" want="$4"; shift 4
  local out rc n dif=""
  case "${1:-}" in DIFFBASE=*) dif="${1#DIFFBASE=}"; shift ;; esac
  out="$(wa_decide "$bd" "$hd" "SELFTEST" "$dif" 2>&1)"; rc=$?
  if [ "$rc" != "$want" ]; then
    echo "FAIL wildcard arms self-test [$label]: rc=$rc, want $want" >&2
    printf '%s\n' "$out" | sed 's/^/      /' >&2
    return 1
  fi
  for n in "$@"; do
    case "$out" in
      *"$n"*) ;;
      *) echo "FAIL wildcard arms self-test [$label]: the verdict never names '$n'" >&2
         printf '%s\n' "$out" | sed 's/^/      /' >&2
         return 1 ;;
    esac
  done
  echo "ok   wildcard arms self-test [$label] (rc=$rc)"
  return 0
}

wa_self_test() {
  local t bd hd bad=0
  t="$(mktemp -d)" || return 2
  bd="$t/base"; _wa_base_tree "$bd"

  ## CONTROL 1 — an unchanged tree. The base already holds ONE counted arm (`h`), so a decider that
  ## simply refused a non-zero count would fail here rather than pass.
  hd="$t/c1"; cp -r "$bd" "$hd"
  _wa_case "control: unchanged tree" "$bd" "$hd" 0 "base_arms=1 head_arms=1 delta=0" || bad=1

  ## CONTROL 2 — a REMOVAL. Stage 1's whole job; it must never be refused.
  hd="$t/c2"; cp -r "$bd" "$hd"
  awk '{ if ($0 == "    _ => {}") print "    Expr::Num | Expr::Var => {}"; else print }' \
    "$bd/src/use.al" > "$hd/src/use.al"
  _wa_case "control: an arm REMOVED" "$bd" "$hd" 0 "delta=-1" || bad=1

  ## PLANT 1 — the shape #651 landed four times: one new `_ =>` over `Expr`.
  hd="$t/p1"; cp -r "$bd" "$hd"
  cat >> "$hd/src/use.al" <<'AL'
pub p := fn(v : ptr(Expr)) -> bool {
  mut r := false
  match deref(v) {
    Expr::Num(a) => { r = true }
    _ => {}
  }
  r
}
AL
  _wa_case "plant: a new _ => over Expr" "$bd" "$hd" 1 "src/use.al: 1 -> 2" "wildcard-ok:" || bad=1

  ## PLANT 2 — the same arm spelled with BARE variant patterns. The scrutinee's type is resolved
  ## through the variant table built from `src/ast.al`, so the bare spelling is not a way out.
  hd="$t/p2"; cp -r "$bd" "$hd"
  cat >> "$hd/src/use.al" <<'AL'
pub q := fn(v : ptr(Expr)) -> bool {
  mut r := false
  match deref(v) {
    Num(a) => { r = true }
    _ => {}
  }
  r
}
AL
  _wa_case "plant: bare variant patterns still resolve" "$bd" "$hd" 1 "src/use.al: 1 -> 2" || bad=1

  ## PLANT 3 — the INLINE one-line accessor. Twenty of `src/lower_ctx.al`'s twenty-four arms had this
  ## shape and `grep -cE '^\s+_ =>'` answered 4 for the file.
  hd="$t/p3"; cp -r "$bd" "$hd"
  printf 'pub s := fn(v : ptr(Expr)) -> bool { mut r := false; match deref(v) { Expr::Num(a) => { r = true } _ => {} }; r }\n' >> "$hd/src/use.al"
  _wa_case "plant: inline one-line accessor arm" "$bd" "$hd" 1 "src/use.al: 1 -> 2" || bad=1

  ## PLANT 4 — a `match` with NO sibling arm to resolve against. Nothing proves the scrutinee is a
  ## byte, so it counts; the acknowledgement marker is the way out.
  hd="$t/p4"; cp -r "$bd" "$hd"
  cat >> "$hd/src/use.al" <<'AL'
pub u := fn(v : ptr(Expr)) -> bool {
  mut r := false
  match deref(v) {
    _ => { r = true }
  }
  r
}
AL
  _wa_case "plant: unresolvable scrutinee fails closed" "$bd" "$hd" 1 "unresolved=1" || bad=1

  ## PLANT 5 — an acknowledgement with an EMPTY reason acknowledges nothing.
  hd="$t/p5"; cp -r "$bd" "$hd"
  cat >> "$hd/src/use.al" <<'AL'
pub w := fn(v : ptr(Expr)) -> bool {
  mut r := false
  match deref(v) {
    Expr::Num(a) => { r = true }
    ## wildcard-ok:
    _ => {}
  }
  r
}
AL
  _wa_case "plant: wildcard-ok with no reason" "$bd" "$hd" 1 "src/use.al: 1 -> 2" || bad=1

  ## CONTROL 3 — the SAME arm, acknowledged where it lives. This is the escape hatch, and it must work.
  hd="$t/c3"; cp -r "$bd" "$hd"
  cat >> "$hd/src/use.al" <<'AL'
pub w := fn(v : ptr(Expr)) -> bool {
  mut r := false
  match deref(v) {
    Expr::Num(a) => { r = true }
    ## wildcard-ok: this accessor is called from the comptime prelude before `Expr` is complete.
    _ => {}
  }
  r
}
AL
  _wa_case "control: acknowledged arm" "$bd" "$hd" 0 "delta=0" "acked=1" || bad=1

  ## CONTROL 4 — the EXEMPTIONS. An integer scrutinee and a comptime `typeinfo` kind dispatch are
  ## both legitimate uses of `_`; the census found only four of the first in the whole tree.
  hd="$t/c4"; cp -r "$bd" "$hd"
  cat >> "$hd/src/use.al" <<'AL'
pub reg := fn(i : usize) -> bool {
  mut r := false
  match i {
    0 => { r = true }
    1 => { r = true }
    _ => {}
  }
  r
}
pub disp := fn(T : type, v : T) -> bool {
  mut r := false
  comptime match typeinfo(T) {
    Struct(_) => { r = true }
    _ => {}
  }
  r
}
AL
  _wa_case "control: integer + comptime exemptions" "$bd" "$hd" 0 "delta=0" "exempt_literal=2" "exempt_comptime=1" || bad=1

  ## CONTROL 5 — PROSE and a STRING literal. `src/parser.al` has three band comments quoting `_ =>`
  ## in prose; a grep-based count fires on all three. This control is the reason the scanner is a
  ## tokenizer.
  hd="$t/c5"; cp -r "$bd" "$hd"
  cat >> "$hd/src/use.al" <<'AL'
## A band note: the arms below replace a `_ => {}` that used to absorb `Expr::Call`,
## which parsed as `match e { 0 => 1 ; _ => 2 }` in the expression form.
pub note := fn() -> str { "_ => {}" }
AL
  _wa_case "control: _ => in prose and in a string" "$bd" "$hd" 0 "delta=0" || bad=1

  ## PLANT 6 — the LINE LOCATOR, which is the half of the refusal an author actually acts on, and it
  ## is the one part that needs a real git tree: the `+ path:line` list comes from a diff against the
  ## base rev, so without this case the locator would never have been reached by any test.
  hd="$t/p6"; cp -r "$bd" "$hd"
  git -C "$hd" init -q 2>/dev/null || { echo "FAIL wildcard arms self-test [plant: line locator]: git init failed" >&2; bad=1; }
  git -C "$hd" config user.email wa@example.invalid
  git -C "$hd" config user.name  "wildcard arm self-test"
  git -C "$hd" add -A >/dev/null 2>&1
  git -C "$hd" commit -qm base >/dev/null 2>&1
  cat >> "$hd/src/use.al" <<'AL'
pub z := fn(v : ptr(Expr)) -> bool {
  mut r := false
  match deref(v) {
    Expr::Num(a) => { r = true }
    _ => {}
  }
  r
}
AL
  _wa_case "plant: the refusal names the added LINE" "$bd" "$hd" 1 DIFFBASE=HEAD \
    "on lines this change touched" "+ src/use.al:30" || bad=1

  ## REFUSAL — an EMPTY corpus must not read as a pass.
  hd="$t/e1"; mkdir -p "$hd/src" "$hd/lib"
  _wa_case "refusal: empty corpus is not a pass" "$bd" "$hd" 2 "proved nothing" || bad=1

  rm -rf "$t"
  if [ "$bad" = 0 ]; then
    echo "wildcard arms: gate-of-the-gate PASSED (6 planted additions refused, 1 no-corpus refusal, 5 controls)"
  else
    echo "wildcard arms: gate-of-the-gate FAILED" >&2
  fi
  return "$bad"
}

# ------------------------------------------------------------------------------------------------
case "${1:-}" in
  --self-test) wa_self_test; exit $? ;;
  --list) shift; wa_scan "${1:-$ROOT}"; exit $? ;;
esac

WA_BASE_ARG="${1:-}"
git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "wildcard arms: FAIL — '$ROOT' is not a git work tree, so there is no merge base to compare" >&2
  echo "  against and this check cannot be performed. Refusing to report a result." >&2
  exit 2
}
BASE="$(wa_resolve_base)" || {
  echo "wildcard arms: FAIL — no base commit could be resolved. This check is a DELTA against the" >&2
  echo "  merge base and holds no committed baseline of its own, so without a base there is nothing" >&2
  echo "  to compare. Tried, in order: the command-line argument, \$ALATYR_WILDCARD_BASE," >&2
  echo "  'git merge-base origin/main HEAD', 'git merge-base main HEAD'." >&2
  exit 2
}
BD="$(mktemp -d)" || exit 2
trap 'rm -rf "$BD"' EXIT
if ! git -C "$ROOT" archive "$BASE" -- "${WA_ROOTS[@]}" 2>/dev/null | tar -x -C "$BD" 2>/dev/null; then
  echo "wildcard arms: FAIL — could not extract ${WA_ROOTS[*]} from base $BASE." >&2
  exit 2
fi
wa_decide "$BD" "$ROOT" "$(git -C "$ROOT" rev-parse --short "$BASE")" "$BASE"
exit $?
