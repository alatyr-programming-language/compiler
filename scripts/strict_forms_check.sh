#!/usr/bin/env bash
# scripts/strict_forms_check.sh — the gate's STRICT-FORMS check: a change may not ADD an
# unacknowledged occurrence of a form the catalogue in AGENTS.md "Strict forms" retires (issue #691).
#
# WHAT IT ENFORCES
# ----------------
# `.agents/skills/alatyr-lane/strict_forms.md` is the catalogue: each form, the defect class it has
# produced in this repository (with the issue numbers), the form to write instead, and whether a
# check holds it. This script is the check for the forms that CAN be counted. Five rules, in two
# halves, because two of them need a type and the other three need only tokens:
#
#   LEXICAL (no compiler, ~3 s, runs before the build — `scripts/strict_forms_scan.awk`)
#     unchecked      an `unchecked` escape with no `## unchecked-ok: <reason>`
#     kind-literal   a kind/tag compared with or computed from an integer literal, no
#                    `## kind-literal-ok: <reason>`
#     try-inline     the value of a `?` used inside a larger expression, no `## try-inline-ok: <reason>`
#   TYPED (`--typed`, after the build — the #529 census channel on file descriptor 98)
#     ptrint         an IMPLICIT `usize` <-> `ptr(T)` crossing the checker accepted (Types §4.3 makes a
#                    reinterpret explicit). No marker: the way out is to write it explicitly.
#     null           a pointer NULL SENTINEL: the explicit forms the lexical scanner counts
#                    (`bitcast(ptr(T), 0)`, `bitcast(usize, p) == 0`) with no `## null-ok: <reason>`,
#                    PLUS the implicit comparisons among the ptrint rows (`p == 0`, class OP-CMP).
#
# Why `null` is decided on the SUM and not on the explicit half alone: #529 step 3 is converting the
# implicit comparisons into explicit ones, one module per slice (`19a1b93`, `68e31a1`, `fc5ba99`,
# `b8cf45d`). A slice like that moves a row from the implicit column to the explicit one and adds no
# null sentinel to the tree; deciding on the explicit column alone would refuse exactly the work that
# is removing the implicit ones. The sum is flat across such a slice and grows by one for every null
# test or null fabrication that is really new.
#
# WHY IT IS AN ADDITION RULE, AND WHY THERE IS NO ORACLE
# ------------------------------------------------------
# The reasons are `scripts/wildcard_arm_check.sh`'s, measured there and not repeated: preventing a
# new occurrence costs its author nothing (they are present and know why it is there), removing the
# thousands already in the tree is a campaign of its own, and a committed baseline number would be a
# fourth oracle. So the check counts the MERGE BASE and the head and refuses an increase per rule;
# there is no committed number and nothing to regenerate. Counts are per rule and tree-wide: removing
# an `unchecked` does not license a new kind literal, and moving code between files is not an
# addition. The price of tree-wide counting is that one addition paid for by one removal elsewhere in
# the same change passes; the verdict line prints both totals, so a reviewer sees it.
#
# HOW TO ACKNOWLEDGE ONE
# ----------------------
# A comment `## <rule>-ok: <reason>` on the form's own line or on the line immediately above it, with a
# non-empty reason. The marker lives where the form lives, for #649's reason: a rule kept anywhere else
# is one people route around, and the reader of the form three months later reads the reason with it.
#
#     ## unchecked-ok: the syscall ABI returns -errno in the result word; decoded on the next line.
#     r := unchecked sys_write(fd, p, n)
#
# Usage (inside `nix develop`):  bash scripts/strict_forms_check.sh [<base-rev>]           # lexical
#                                bash scripts/strict_forms_check.sh --typed [<base-rev>]   # after a build
#                                bash scripts/strict_forms_check.sh --list [<root>]
#                                bash scripts/strict_forms_check.sh --self-test            # no compiler
#                                bash scripts/strict_forms_check.sh --typed-self-test [<compiler>]
# Base resolution, in order: `$1`, `$ALATYR_STRICT_BASE`, `git merge-base origin/main HEAD`,
# `git merge-base main HEAD`. `--typed` uses `$ALATYR` or `target/debug/alatyr` (full.sh's Stage2).
# Exit 0 = no unacknowledged addition.  1 = an addition (named).  2 = the check could not be performed.
set -u
export LC_ALL=C
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCAN="$ROOT/scripts/strict_forms_scan.awk"
SF_PATHSPECS=('src/*.al' 'lib/*.al')
SF_ROOTS=(src lib)
SF_LEX_RULES="unchecked kind-literal try-inline"

sf_scan() { # dir -> rows on stdout (the same enumeration as scripts/wildcard_arm_check.sh)
  local d="$1" list files=() rc
  list="$(mktemp)" || return 2
  if git -C "$d" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    ( cd "$d" && git ls-files -- "${SF_PATHSPECS[@]}" ) | sort > "$list"
  else
    ( cd "$d" && find "${SF_ROOTS[@]}" \( -type f -o -type l \) -name '*.al' -print 2>/dev/null ) |
      sed 's|^\./||' | sort > "$list"
  fi
  if [ ! -s "$list" ]; then rm -f "$list"; return 3; fi
  mapfile -t files < "$list"
  ( cd "$d" && awk -f "$SCAN" -- "${files[@]}" )
  rc=$?
  rm -f "$list"
  return "$rc"
}

## The COUNTED set of one rule: its rows with no acknowledgement.
sf_counted() { awk -F'\t' -v r="$1" '$3 == r && $4 == 0'; }

## Name the added rows of one rule: per-file increases, then the exact lines the diff touched.
sf_name_additions() { # rule base.counted head.counted head-dir difbase workdir
  local rule="$1" bc="$2" hc="$3" hd="$4" difbase="$5" w="$6" f b h
  cut -f1 "$bc" | sort | uniq -c | awk '{print $2"\t"$1}' | sort > "$w/b.per"
  cut -f1 "$hc" | sort | uniq -c | awk '{print $2"\t"$1}' | sort > "$w/h.per"
  join -t"$(printf '\t')" -a2 -e0 -o 0,1.2,2.2 "$w/b.per" "$w/h.per" > "$w/j.per"
  awk -F'\t' '$3 > $2 {printf "    %s: %d -> %d\n", $1, $2, $3}' "$w/j.per" >&2
  [ -n "$difbase" ] || return 0
  : > "$w/added"
  while IFS=$'\t' read -r f b h; do
    [ "$h" -gt "$b" ] || continue
    git -C "$hd" diff --unified=0 "$difbase" -- "$f" 2>/dev/null |
      awk '/^@@/ { split($3, a, ","); s = a[1] + 0; if (s < 0) s = -s; n = (a[2] == "" ? 1 : a[2] + 0)
                   if (n > 0) print s"\t"(s + n - 1) }' > "$w/hunks"
    awk -F'\t' -v f="$f" '$1 == f {print $2"\t"$5}' "$hc" | sort -n | while IFS=$'\t' read -r ln form; do
      if awk -F'\t' -v l="$ln" '$1 <= l && l <= $2 {found = 1} END {exit !found}' "$w/hunks"; then
        echo "    + $f:$ln  [$rule] $form" >> "$w/added"
      fi
    done
  done < "$w/j.per"
  if [ -s "$w/added" ]; then
    echo "  on lines this change touched:" >&2
    head -40 "$w/added" >&2
  fi
}

sf_advice() { # rule
  case "$1" in
    unchecked)
      echo "  An \`unchecked\` suspends the checks Memory §4.5 grants it; without a reason next to it the next" >&2
      echo "  reader cannot tell a deliberate reinterpret from a silenced mismatch (strict_forms.md §unchecked)." >&2
      echo "  Fix: drop it if the operand already has the right type, or say why it is needed, there:" >&2
      echo "      ## unchecked-ok: <what is reinterpreted and why the types cannot say it>" >&2 ;;
    kind-literal)
      echo "  A kind compared with a literal is a decision the compiler cannot check: #583 measured 134 such" >&2
      echo "  sites behind one \`u8\` and three defects (#519, #529, #562). Fix: compare with a named variant" >&2
      echo "  of an enum (or a named constant while the kind is still an integer), or say why, there:" >&2
      echo "      ## kind-literal-ok: <why this kind has no named form yet>" >&2 ;;
    try-inline)
      echo "  The value of a \`?\` used inside a larger expression is the #752 shape: a multi-word payload read" >&2
      echo "  inline delivered word 0 and stack garbage, and the frozen seed 0.2.4 predates the fix (1b5cd53)." >&2
      echo "  Fix: bind it first — \`x := f()?\` — and use \`x\`; or say why, there:" >&2
      echo "      ## try-inline-ok: <why the payload is one word and must be read inline>" >&2 ;;
    null)
      echo "  A null pointer is an absence spelled as the integer 0 — the sentinel the type cannot see." >&2
      echo "  Fix: \`Option(ptr(T))\` (niche-folded, one word; #768/#770/#775 track its remaining gaps), or" >&2
      echo "  — for a list link the AST already spells as null — say why, there:" >&2
      echo "      ## null-ok: <which existing null-terminated structure this walks or builds>" >&2 ;;
    ptrint)
      echo "  An implicit \`usize\` <-> \`ptr(T)\` crossing is the #529 seam: Types §4.3 makes a reinterpret explicit" >&2
      echo "  and Memory §4.5 makes a fabricated pointer ill-formed outside a grant. There is no marker for" >&2
      echo "  this one — write the crossing explicitly (\`unchecked bitcast(usize, p)\`, with its reason)." >&2 ;;
  esac
}

## THE LEXICAL DECIDER. Two directories in, a verdict out; the self-test drives this function.
sf_decide() { # base-dir head-dir base-label [difbase]
  local bd="$1" hd="$2" label="$3" difbase="${4:-}"
  local w brc hrc bad=0 r bn hn ak nf summary="" nb nh
  w="$(mktemp -d)" || return 2
  sf_scan "$bd" > "$w/base.rows"; brc=$?
  sf_scan "$hd" > "$w/head.rows"; hrc=$?
  if [ "$brc" = 3 ] || [ "$hrc" = 3 ]; then
    echo "strict forms: FAIL — one of the two trees holds ZERO tracked .al files under ${SF_PATHSPECS[*]};" >&2
    echo "  there is nothing to compare and this check proved nothing. Refusing to report a result." >&2
    rm -rf "$w"; return 2
  fi
  if [ "$brc" != 0 ] || [ "$hrc" != 0 ]; then
    echo "strict forms: FAIL — the scanner exited non-zero (base rc=$brc head rc=$hrc)." >&2
    rm -rf "$w"; return 2
  fi
  nf="$(cd "$hd" && if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then git ls-files -- "${SF_PATHSPECS[@]}"; else find "${SF_ROOTS[@]}" -name '*.al'; fi | wc -l | tr -d ' ')"
  for r in $SF_LEX_RULES; do
    sf_counted "$r" < "$w/base.rows" > "$w/base.$r"
    sf_counted "$r" < "$w/head.rows" > "$w/head.$r"
    bn="$(wc -l < "$w/base.$r" | tr -d ' ')"; hn="$(wc -l < "$w/head.$r" | tr -d ' ')"
    ak="$(awk -F'\t' -v r="$r" '$3 == r && $4 == 1' "$w/head.rows" | wc -l | tr -d ' ')"
    summary="$summary $r=$bn->$hn(acked=$ak)"
    if [ "$hn" -gt "$bn" ]; then
      bad=1
      echo "strict forms: FAIL — $((hn - bn)) unacknowledged [$r] form(s) were ADDED relative to $label ($bn -> $hn)." >&2
      sf_name_additions "$r" "$w/base.$r" "$w/head.$r" "$hd" "$difbase" "$w"
      sf_advice "$r"
    fi
  done
  ## The explicit null forms are COUNTED here and DECIDED by `--typed`, which adds the implicit
  ## comparisons only the compiler can see (the header says why the sum is the decided number).
  nb="$(sf_counted null < "$w/base.rows" | wc -l | tr -d ' ')"; nh="$(sf_counted null < "$w/head.rows" | wc -l | tr -d ' ')"
  echo "strict forms: base=$label files=$nf$summary null-explicit=$nb->$nh(decided-by=--typed)"
  if [ "$bad" = 0 ]; then
    echo "*** strict forms: no unacknowledged strict-form addition (lexical rules: $SF_LEX_RULES) ***"
  else
    echo "*** strict forms: this change ADDS unacknowledged strict forms (see above) ***"
  fi
  rm -rf "$w"
  return "$bad"
}

# ======================================================================================================
# THE TYPED HALF. The compiler is the only thing that knows `p` in `p == 0` is a pointer, and it
# already says so: `src/sema.al`'s #529 instrument writes one row per implicit usize<->ptr crossing to
# file descriptor 98 (`scripts/ptrint_census.sh`). The head compiler checks BOTH trees, so a row count
# never differs because the instrument did. The base tree is checked from its own extraction with the
# compiler copied into ITS `target/debug/` — the library lookup is relative to the executable
# (AGENTS.md), so that is what makes the base count read the base `lib/` rather than the head's.
# ======================================================================================================
sf_typed_measure() { # dir compiler target out -> rc of `check`; rows in <out>
  local d="$1" cc="$2" tgt="$3" out="$4" rc
  ( cd "$d" && ulimit -c 0 && "$cc" check "$tgt" 98>"$out" >/dev/null 2>"$out.err" ); rc=$?
  return "$rc"
}
sf_implicit_rows() { awk '$1 == "#529" && $2 != "SUMMARY"' "$1"; }
## A row's identity for naming additions: class, module, declaration and source text — never the byte
## offset, which moves with every edit above it.
sf_implicit_keys() { sf_implicit_rows "$1" | awk '{ s = $0; sub(/^[^|]*\|/, "", s); print $2" "$6" "$7" |"s }' | sort; }

## THE TYPED DECIDER. Counts in, a verdict out, so the self-test can drive it without a compiler.
## ib/ih are the implicit (#529) row counts, or "SKIPPED"; ob/oh the OP-CMP subset; eb/eh the
## unacknowledged explicit null forms.
sf_typed_decide() { # label ib ih ob oh eb eh [base-rows head-rows]
  local label="$1" ib="$2" ih="$3" ob="$4" oh="$5" eb="$6" eh="$7" brow="${8:-}" hrow="${9:-}" bad=0 nb nh
  if [ "$ib" = SKIPPED ]; then
    nb="$eb"; nh="$eh"
  else
    nb=$((eb + ob)); nh=$((eh + oh))
    if [ "$ih" -gt "$ib" ]; then
      bad=1
      echo "strict forms: FAIL — $((ih - ib)) IMPLICIT usize<->ptr crossing(s) [ptrint] were ADDED relative to $label ($ib -> $ih)." >&2
      if [ -n "$brow" ] && [ -n "$hrow" ]; then
        echo "  new rows (class module declaration | source):" >&2
        comm -13 <(sf_implicit_keys "$brow") <(sf_implicit_keys "$hrow") | head -20 | sed 's/^/    + /' >&2
      fi
      sf_advice ptrint
    fi
  fi
  if [ "$nh" -gt "$nb" ]; then
    bad=1
    echo "strict forms: FAIL — $((nh - nb)) NULL-SENTINEL form(s) [null] were ADDED relative to $label ($nb -> $nh:" >&2
    echo "  explicit $eb -> $eh, implicit comparisons $ob -> $oh)." >&2
    echo "  (the explicit ones are named by: bash scripts/strict_forms_check.sh --list | awk -F'\\t' '\$3==\"null\" && \$4==0')" >&2
    sf_advice null
  fi
  echo "strict forms typed: base=$label ptrint=$ib->$ih null=$nb->$nh(explicit=$eb->$eh implicit-cmp=$ob->$oh)"
  if [ "$bad" = 0 ]; then
    echo "*** strict forms typed: no implicit crossing and no null sentinel was added ***"
  else
    echo "*** strict forms typed: this change ADDS implicit crossings or null sentinels (see above) ***"
  fi
  return "$bad"
}

sf_typed() { # base-rev
  local base="$1" cc="${ALATYR:-$ROOT/target/debug/alatyr}" w bd brc hrc ib ih ob oh eb eh label
  [ -x "$cc" ] || { echo "strict forms typed: FAIL — no compiler at $cc (run after the build)." >&2; return 2; }
  label="$(git -C "$ROOT" rev-parse --short "$base")"
  w="$(mktemp -d)" || return 2
  bd="$w/base"; mkdir -p "$bd/target/debug"
  if ! git -C "$ROOT" archive "$base" -- package.al "${SF_ROOTS[@]}" | tar -x -C "$bd"; then
    echo "strict forms typed: FAIL — could not extract the base tree from $base." >&2; rm -rf "$w"; return 2
  fi
  cp "$cc" "$bd/target/debug/alatyr"
  sf_typed_measure "$ROOT" "$cc" package.al "$w/head.98"; hrc=$?
  if [ "$hrc" != 0 ] || ! grep -q '^#529 SUMMARY ' "$w/head.98"; then
    echo "strict forms typed: FAIL — the head compiler did not check its own tree cleanly (rc=$hrc, SUMMARY" >&2
    echo "  line $(grep -c '^#529 SUMMARY ' "$w/head.98") time(s)); the implicit count is unknown. First diagnostics:" >&2
    head -5 "$w/head.98.err" | sed 's/^/    /' >&2
    rm -rf "$w"; return 2
  fi
  sf_typed_measure "$bd" "$bd/target/debug/alatyr" package.al "$w/base.98"; brc=$?
  ih="$(sf_implicit_rows "$w/head.98" | wc -l | tr -d ' ')"
  oh="$(sf_implicit_rows "$w/head.98" | awk '$2 == "OP-CMP"' | wc -l | tr -d ' ')"
  if [ "$brc" != 0 ] || ! grep -q '^#529 SUMMARY ' "$w/base.98"; then
    ## A change that tightens the checker can make the head compiler refuse the BASE tree (#760 did:
    ## its Deref arm refused twelve walkers the same PR then fixed). The implicit half is then
    ## unmeasurable, and that is SAID in the verdict line, exactly as scripts/full.sh says a skipped
    ## sweep — never read as a zero. The explicit half still decides `null`.
    echo "strict forms typed: NOTE — the head compiler refuses the BASE tree (rc=$brc), so the implicit half" >&2
    echo "  is SKIPPED and \`null\` is decided on its explicit forms alone. First diagnostics:" >&2
    head -3 "$w/base.98.err" | sed 's/^/    /' >&2
    ib=SKIPPED; ob=SKIPPED
  else
    ib="$(sf_implicit_rows "$w/base.98" | wc -l | tr -d ' ')"
    ob="$(sf_implicit_rows "$w/base.98" | awk '$2 == "OP-CMP"' | wc -l | tr -d ' ')"
  fi
  eb="$(sf_scan "$bd" | sf_counted null | wc -l | tr -d ' ')"
  eh="$(sf_scan "$ROOT" | sf_counted null | wc -l | tr -d ' ')"
  sf_typed_decide "$label" "$ib" "$ih" "$ob" "$oh" "$eb" "$eh" "$w/base.98" "$w/head.98"
  local rc=$?
  rm -rf "$w"
  return "$rc"
}

sf_resolve_base() {
  if [ -n "${SF_BASE_ARG:-}" ]; then git -C "$ROOT" rev-parse --verify -q "${SF_BASE_ARG}^{commit}" && return 0; return 1; fi
  if [ -n "${ALATYR_STRICT_BASE:-}" ]; then git -C "$ROOT" rev-parse --verify -q "${ALATYR_STRICT_BASE}^{commit}" && return 0; return 1; fi
  git -C "$ROOT" merge-base origin/main HEAD 2>/dev/null && return 0
  git -C "$ROOT" merge-base main HEAD 2>/dev/null && return 0
  return 1
}

# ======================================================================================================
# THE GATE-OF-THE-GATE (issue #600). Every rule is refused BY NAME on a planted addition, every escape
# is proved to work, and the controls that must stay green pin down the two things a lexical check is
# most likely to get wrong: a form quoted in PROSE or a STRING (a grep fires on it), and a REMOVAL or a
# MOVE between files (an addition rule must never refuse either).
# ======================================================================================================
_sf_base_tree() { # dir
  local d="$1"
  mkdir -p "$d/src" "$d/lib"
  cat > "$d/src/ast.al" <<'AL'
pub Tok := struct { kind : u8, start : usize }
pub Node := struct { next : ptr(Node), v : u64 }
AL
  cat > "$d/src/use.al" <<'AL'
(Tok, Node) := ast
pub a := fn(t : Tok) -> bool { t.kind == 3 }
pub b := fn(p : ptr(Node)) -> usize { unchecked bitcast(usize, p) }
pub c := fn(p : ptr(Node)) -> bool { unchecked bitcast(usize, p) == 0 }
pub d := fn() -> Result(u64, u64) {
  x := f()?
  Result(u64, u64).Ok(x)
}
AL
  printf 'pub one := fn() -> u64 { 1 }\n' > "$d/lib/rt.al"
}

_sf_case() { # label base-dir head-dir want-rc [DIFFBASE=<rev>] needle...
  local label="$1" bd="$2" hd="$3" want="$4"; shift 4
  local out rc n dif=""
  case "${1:-}" in DIFFBASE=*) dif="${1#DIFFBASE=}"; shift ;; esac
  out="$(sf_decide "$bd" "$hd" "SELFTEST" "$dif" 2>&1)"; rc=$?
  _sf_judge "$label" "$rc" "$want" "$out" "$@"
}
_sf_judge() { # label rc want out needle...
  local label="$1" rc="$2" want="$3" out="$4" n; shift 4
  if [ "$rc" != "$want" ]; then
    echo "FAIL strict forms self-test [$label]: rc=$rc, want $want" >&2
    printf '%s\n' "$out" | sed 's/^/      /' >&2
    return 1
  fi
  for n in "$@"; do
    case "$out" in
      *"$n"*) ;;
      *) echo "FAIL strict forms self-test [$label]: the verdict never names '$n'" >&2
         printf '%s\n' "$out" | sed 's/^/      /' >&2
         return 1 ;;
    esac
  done
  echo "ok   strict forms self-test [$label] (rc=$rc)"
}
_sf_plant() { # base-dir new-dir text-appended-to-src/use.al
  cp -r "$1" "$2"; printf '%s\n' "$3" >> "$2/src/use.al"
}

sf_self_test() {
  local t bd hd bad=0 np=0 nc=0
  t="$(mktemp -d)" || return 2
  bd="$t/base"; _sf_base_tree "$bd"

  ## CONTROL — an unchanged tree. The base holds one of every form, so a decider that refused any
  ## non-zero count fails here.
  hd="$t/c1"; cp -r "$bd" "$hd"
  _sf_case "control: unchanged tree" "$bd" "$hd" 0 "unchecked=1->1" "kind-literal=1->1" "try-inline=0->0" "null-explicit=1->1" || bad=1; nc=$((nc+1))

  ## CONTROL — REMOVALS, and a MOVE of a form into another file. Neither is an addition.
  hd="$t/c2"; cp -r "$bd" "$hd"
  grep -v 'pub b :=' "$bd/src/use.al" | sed 's/t.kind == 3/t.kind == t.kind/' > "$hd/src/use.al"
  printf 'pub b := fn(p : ptr(u8)) -> usize { unchecked bitcast(usize, p) }\n' > "$hd/src/moved.al"
  sed -i.bak 's/t.kind == t.kind/false/' "$hd/src/use.al"; rm -f "$hd/src/use.al.bak"
  _sf_case "control: removal and a move between files" "$bd" "$hd" 0 "unchecked=1->1" "kind-literal=1->0" || bad=1; nc=$((nc+1))

  ## PLANT — one new form per rule, each refused by name.
  hd="$t/p1"; _sf_plant "$bd" "$hd" 'pub e := fn(h : usize) -> ptr(u8) { unchecked bitcast(ptr(u8), h) }'
  _sf_case "plant: a new unchecked" "$bd" "$hd" 1 "[unchecked]" "1 -> 2" "unchecked-ok:" || bad=1; np=$((np+1))
  hd="$t/p2"; _sf_plant "$bd" "$hd" 'pub e := fn(t : Tok) -> bool { t.kind != 17 }'
  _sf_case "plant: a kind compared with a literal" "$bd" "$hd" 1 "[kind-literal]" "kind-literal-ok:" || bad=1; np=$((np+1))
  hd="$t/p3"; _sf_plant "$bd" "$hd" 'tag_with_mut := fn(tag : u8) -> u8 { tag + 128 }'
  _sf_case "plant: a flag packed into a tag (+128)" "$bd" "$hd" 1 "[kind-literal]" || bad=1; np=$((np+1))
  hd="$t/p4"; _sf_plant "$bd" "$hd" 'pub e := fn(t : Tok) -> u64 {
  match t.kind {
    0 => { 1 }
    5 => { 2 }
  }
}'
  _sf_case "plant: match over a kind with literal arms" "$bd" "$hd" 1 "kind-literal=1->3" || bad=1; np=$((np+1))
  hd="$t/p5"; _sf_plant "$bd" "$hd" 'pub e := fn() -> Result(u64, u64) { Result(u64, u64).Ok(g()?.a + 1) }'
  _sf_case "plant: the value of a ? used inline" "$bd" "$hd" 1 "[try-inline]" "try-inline-ok:" || bad=1; np=$((np+1))
  hd="$t/p6"; _sf_plant "$bd" "$hd" 'pub e := fn(t : Tok) -> bool { 3 == t.kind }'
  _sf_case "plant: a literal on the left of a kind" "$bd" "$hd" 1 "[kind-literal]" || bad=1; np=$((np+1))
  ## An `unchecked` inside the one-line body of an accessor is still counted: no line-start anchor.
  hd="$t/p7"; _sf_plant "$bd" "$hd" 'pub e := fn(h : usize) -> bool { mut r := false; if h > 1 { r = unchecked (h - 1 > 0) }; r }'
  _sf_case "plant: unchecked inline in a one-line accessor" "$bd" "$hd" 1 "[unchecked]" || bad=1; np=$((np+1))
  ## An acknowledgement with an EMPTY reason acknowledges nothing.
  hd="$t/p8"; _sf_plant "$bd" "$hd" '## unchecked-ok:
pub e := fn(h : usize) -> ptr(u8) { unchecked bitcast(ptr(u8), h) }'
  _sf_case "plant: unchecked-ok with no reason" "$bd" "$hd" 1 "[unchecked]" || bad=1; np=$((np+1))
  ## A marker for ANOTHER rule does not acknowledge this one.
  hd="$t/p9"; _sf_plant "$bd" "$hd" 'pub e := fn(t : Tok) -> bool { t.kind != 17 } ## unchecked-ok: wrong rule'
  _sf_case "plant: a marker for another rule" "$bd" "$hd" 1 "[kind-literal]" || bad=1; np=$((np+1))
  ## The explicit null forms are COUNTED by the lexical pass (the typed pass decides them).
  hd="$t/p10"; _sf_plant "$bd" "$hd" 'pub e := fn() -> ptr(Node) { unchecked bitcast(ptr(Node), 0) }
pub f2 := fn(p : ptr(Node)) -> bool { 0 != unchecked bitcast(usize, p) }'
  _sf_case "control: null forms are counted, and their unchecked is not" "$bd" "$hd" 0 "null-explicit=1->3" "unchecked=1->1" || bad=1; nc=$((nc+1))

  ## CONTROL — every escape, acknowledged where it lives (same line, and the line above).
  hd="$t/c3"; _sf_plant "$bd" "$hd" '## unchecked-ok: planted escape, the line above.
pub e := fn(h : usize) -> ptr(u8) { unchecked bitcast(ptr(u8), h) }
pub f3 := fn(t : Tok) -> bool { t.kind != 17 } ## kind-literal-ok: planted escape, same line.
## try-inline-ok: planted escape.
pub g3 := fn() -> Result(u64, u64) { Result(u64, u64).Ok(g()?.a) }'
  _sf_case "control: acknowledged forms" "$bd" "$hd" 0 "unchecked=1->1(acked=1)" "kind-literal=1->1(acked=1)" "try-inline=0->0(acked=1)" || bad=1; nc=$((nc+1))

  ## CONTROL — PROSE and STRINGS. A grep fires on every one of these.
  hd="$t/c4"; _sf_plant "$bd" "$hd" '## Band note: `unchecked bitcast(usize, p) == 0` and `t.kind == 3` and `f()?.x` used to be here.
pub note := fn() -> str { "unchecked t.kind == 3 g()?.a" }
pub unk := fn(kind : u8, tag : u8) -> u8 { kind }
x := fn() -> Result(u64, u64) {
  y := f()?
  f()?
  Result(u64, u64).Ok(y)
}'
  _sf_case "control: forms in prose, strings, declarations and statement ?" "$bd" "$hd" 0 "unchecked=1->1" "kind-literal=1->1" "try-inline=0->0" || bad=1; nc=$((nc+1))

  ## PLANT — the LINE LOCATOR, which needs a real git tree for the diff.
  hd="$t/p11"; cp -r "$bd" "$hd"
  git -C "$hd" init -q 2>/dev/null || { echo "FAIL strict forms self-test [line locator]: git init failed" >&2; bad=1; }
  git -C "$hd" config user.email sf@example.invalid
  git -C "$hd" config user.name  "strict forms self-test"
  git -C "$hd" add -A >/dev/null 2>&1
  git -C "$hd" commit -qm base >/dev/null 2>&1
  printf 'pub z := fn(h : usize) -> ptr(u8) { unchecked bitcast(ptr(u8), h) }\n' >> "$hd/src/use.al"
  _sf_case "plant: the refusal names the added LINE" "$bd" "$hd" 1 DIFFBASE=HEAD \
    "on lines this change touched" "+ src/use.al:9  [unchecked]" || bad=1; np=$((np+1))

  ## REFUSAL — an EMPTY corpus must not read as a pass.
  hd="$t/e1"; mkdir -p "$hd/src" "$hd/lib"
  _sf_case "refusal: empty corpus is not a pass" "$bd" "$hd" 2 "proved nothing" || bad=1

  ## THE TYPED DECIDER, driven by counts (the compiler-backed proof is --typed-self-test).
  local out rc
  out="$(sf_typed_decide T 361 361 361 361 904 904 2>&1)"; rc=$?
  _sf_judge "typed control: unchanged" "$rc" 0 "$out" "ptrint=361->361" "null=1265->1265" || bad=1; nc=$((nc+1))
  out="$(sf_typed_decide T 361 360 361 360 904 905 2>&1)"; rc=$?
  _sf_judge "typed control: a #529 slice converts one implicit test to explicit" "$rc" 0 "$out" "null=1265->1265" || bad=1; nc=$((nc+1))
  out="$(sf_typed_decide T 361 362 361 362 904 904 2>&1)"; rc=$?
  _sf_judge "typed plant: a new implicit p == 0" "$rc" 1 "$out" "[ptrint]" "[null]" || bad=1; np=$((np+1))
  out="$(sf_typed_decide T 361 361 361 361 904 905 2>&1)"; rc=$?
  _sf_judge "typed plant: a new explicit null test" "$rc" 1 "$out" "[null]" "null-ok:" || bad=1; np=$((np+1))
  out="$(sf_typed_decide T SKIPPED 361 SKIPPED 361 904 905 2>&1)"; rc=$?
  _sf_judge "typed plant: base unmeasurable still decides the explicit half" "$rc" 1 "$out" "ptrint=SKIPPED->361" "[null]" || bad=1; np=$((np+1))

  rm -rf "$t"
  if [ "$bad" = 0 ]; then
    echo "strict forms: gate-of-the-gate PASSED ($np planted additions refused, 1 no-corpus refusal, $nc controls)"
  else
    echo "strict forms: gate-of-the-gate FAILED" >&2
  fi
  return "$bad"
}

## The compiler-backed half of the proof: the #529 channel must SEE a new implicit comparison and
## must NOT see its explicit twin — otherwise the typed rule is blind, and a blind count and a clean
## tree both read as zero (#679).
sf_typed_self_test() {
  local cc="${1:-${ALATYR:-$ROOT/target/debug/alatyr}}" t rc bad=0 n0 n1 n2
  [ -x "$cc" ] || { echo "strict forms typed self-test: FAIL — no compiler at $cc" >&2; return 2; }
  t="$(mktemp -d)" || return 2
  cat > "$t/base.al" <<'AL'
N := struct { next : ptr(N), v : u64 }
give := fn() -> ptr(N) { unchecked bitcast(ptr(N), 4096) }
pub main := fn() -> i32 {
  p : ptr(N) = give()
  mut r : i32 = 0
  if unchecked bitcast(usize, p) != 0 { r = 1 }
  r
}
AL
  sed 's/if unchecked bitcast(usize, p) != 0 { r = 1 }/if p != 0 { r = 1 }/' "$t/base.al" > "$t/implicit.al"
  sed 's/  r$/  if unchecked bitcast(usize, p) == 0 { r = 2 }\n  r/' "$t/base.al" > "$t/explicit.al"
  for f in base implicit explicit; do
    sf_typed_measure "$t" "$cc" "$f.al" "$t/$f.98"; rc=$?
    if [ "$rc" != 0 ] || ! grep -q '^#529 SUMMARY ' "$t/$f.98"; then
      echo "FAIL strict forms typed self-test: \`check $f.al\` rc=$rc or no SUMMARY line" >&2; bad=1
    fi
  done
  n0="$(sf_implicit_rows "$t/base.98" | awk '$2 == "OP-CMP"' | wc -l | tr -d ' ')"
  n1="$(sf_implicit_rows "$t/implicit.98" | awk '$2 == "OP-CMP"' | wc -l | tr -d ' ')"
  n2="$(sf_implicit_rows "$t/explicit.98" | awk '$2 == "OP-CMP"' | wc -l | tr -d ' ')"
  if [ "$n1" -le "$n0" ]; then echo "FAIL strict forms typed self-test: \`p != 0\` added no OP-CMP row ($n0 -> $n1) — the typed rule is blind" >&2; bad=1; fi
  if [ "$n2" != "$n0" ]; then echo "FAIL strict forms typed self-test: an EXPLICIT null test moved the implicit count ($n0 -> $n2)" >&2; bad=1; fi
  rm -rf "$t"
  echo "strict forms typed self-test: implicit-cmp base=$n0 +implicit=$n1 +explicit=$n2"
  if [ "$bad" = 0 ]; then echo "strict forms typed self-test: PASSED"; else echo "strict forms typed self-test: FAILED" >&2; fi
  return "$bad"
}

# ------------------------------------------------------------------------------------------------
case "${1:-}" in
  --self-test) sf_self_test; exit $? ;;
  --typed-self-test) shift; sf_typed_self_test "${1:-}"; exit $? ;;
  --list) shift; sf_scan "${1:-$ROOT}"; exit $? ;;
esac
TYPED=0
if [ "${1:-}" = "--typed" ]; then TYPED=1; shift; fi
SF_BASE_ARG="${1:-}"
git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "strict forms: FAIL — '$ROOT' is not a git work tree, so there is no merge base to compare" >&2
  echo "  against and this check cannot be performed. Refusing to report a result." >&2
  exit 2
}
BASE="$(sf_resolve_base)" || {
  echo "strict forms: FAIL — no base commit could be resolved. This check is a DELTA against the merge" >&2
  echo "  base and holds no committed baseline, so without a base there is nothing to compare. Tried:" >&2
  echo "  the argument, \$ALATYR_STRICT_BASE, 'git merge-base origin/main HEAD', 'git merge-base main HEAD'." >&2
  exit 2
}
if [ "$TYPED" = 1 ]; then sf_typed "$BASE"; exit $?; fi
BD="$(mktemp -d)" || exit 2
trap 'rm -rf "$BD"' EXIT
if ! git -C "$ROOT" archive "$BASE" -- "${SF_ROOTS[@]}" 2>/dev/null | tar -x -C "$BD" 2>/dev/null; then
  echo "strict forms: FAIL — could not extract ${SF_ROOTS[*]} from base $BASE." >&2
  exit 2
fi
sf_decide "$BD" "$ROOT" "$(git -C "$ROOT" rev-parse --short "$BASE")" "$BASE"
exit $?
