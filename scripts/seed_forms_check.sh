#!/usr/bin/env bash
# scripts/seed_forms_check.sh — the SEED-FORMS REGISTRY check (strict_forms.md §8, issue #691; owner
# decision on #785).
#
# WHAT IT ENFORCES
# ----------------
# `seed/alatyr` builds Stage1. A form the frozen seed miscompiles therefore breaks the compiler even
# where the tree's own compiler handles it, so `src/` and `lib/` avoid such forms and leave a
# workaround comment. Until this registry existed, those limitations lived only in the comments. So
# nobody could tell whether a comment was still true, and nothing noticed when a promotion made one
# obsolete. `scripts/seed_forms.tsv` lists each form with a planted program under `scripts/seed_forms/`
# and the program's correct exit value, and this check runs every program with both compilers:
#
#   state `seed`  tree == due   else FAIL: the form REGRESSED in the tree
#                 seed != due   else FAIL: the seed now handles it. Retire the row and remove the
#                               workaround comments at its sites. That is how the registry retires
#                               itself after a promotion: the promotion makes this check go red.
#   state `tree`  tree != due   else FAIL: the tree now handles it, so the row moves to `seed`. The
#                               seed's result is printed and not judged, because the tree defect is
#                               what the row tracks.
#
# The registry must also match the directory, both ways: a program with no row, or a row with no
# program, is refused, as is a malformed row. An EMPTY registry is legitimate only when it says so:
# a `# live-rows: N` line declares how many rows the file holds, and the parsed count must equal it.
# Without the declaration an empty registry is refused, and a declaration the parse disagrees with is
# refused too, so a parser that silently skips rows cannot read as "nothing to check". The registry
# empties when a promotion retires its last row (0.2.7 retired #790's and #791's).
#
# WHY THE PROGRAMS ARE NOT IN test/
# ---------------------------------
# `scripts/corpus_manifest.sh` enumerates `git ls-files 'test/*.al'`. That is a git pathspec, and
# its `*` crosses `/`, so even `test/seed_forms/x.al` would be a corpus fixture with four manifest
# rows. These programs are about the SEED, which the corpus never runs, and each row retires on a
# promotion, which would move the manifest every time. `scripts/seed_forms/` is outside every `.al`
# pathspec the gate uses (`test/*.al`, `src/*.al`, `lib/*.al`).
#
# Usage (inside `nix develop`):  bash scripts/seed_forms_check.sh              # after a build
#                                bash scripts/seed_forms_check.sh --self-test  # no compiler
# The tree compiler is `$SEED_FORMS_TREE`, else `target/debug/alatyr` (full.sh's Stage2). The seed is
# `$SEED_FORMS_SEED`, else `seed/alatyr`. `$SEED_FORMS_REGISTRY` / `$SEED_FORMS_DIR` override the
# registry and the program directory (the self-test uses them). `$SEED_FORMS_TIMEOUT`, in seconds,
# defaults to 300 per run.
# Exit 0 = every row holds.  1 = a row failed (named).  2 = the check could not be performed.
set -u
export LC_ALL=C
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

## The decider, kept pure so the self-test can drive it without a compiler. Prints one verdict word.
sf_decide() { # state due tree_rc seed_rc
  local state="$1" due="$2" trc="$3" src="$4"
  case "$state" in
    seed)
      if [ "$trc" != "$due" ]; then echo TREE-REGRESSED
      elif [ "$src" = "$due" ]; then echo SEED-NOW-HANDLES
      else echo OK; fi ;;
    tree)
      if [ "$trc" = "$due" ]; then echo TREE-NOW-HANDLES
      else echo OK; fi ;;
    *) echo BAD-STATE ;;
  esac
}

sf_run() { # compiler program errfile -> prints rc
  local cc="$1" prog="$2" err="$3" rc
  if command -v timeout >/dev/null 2>&1; then
    ( ulimit -c 0; timeout "${SEED_FORMS_TIMEOUT:-300}" "$cc" run "$prog" >/dev/null 2>"$err" ); rc=$?
  else
    ( ulimit -c 0; "$cc" run "$prog" >/dev/null 2>"$err" ); rc=$?
  fi
  echo "$rc"
}

sf_check() {
  local reg="${SEED_FORMS_REGISTRY:-$ROOT/scripts/seed_forms.tsv}"
  local dir="${SEED_FORMS_DIR:-$ROOT/scripts/seed_forms}"
  local tree="${SEED_FORMS_TREE:-$ROOT/target/debug/alatyr}"
  local seed="${SEED_FORMS_SEED:-$ROOT/seed/alatyr}"
  local w bad=0 rows=0 nseed=0 ntree=0 declared
  [ -f "$reg" ] || { echo "seed forms: cannot read the registry $reg" >&2; return 2; }
  declared="$(sed -n 's/^# live-rows: *\([0-9][0-9]*\) *$/\1/p' "$reg" | head -1)"
  [ -d "$dir" ] || { echo "seed forms: no program directory $dir" >&2; return 2; }
  [ -x "$tree" ] || { echo "seed forms: no tree compiler at $tree (build first)" >&2; return 2; }
  [ -x "$seed" ] || { echo "seed forms: no seed at $seed" >&2; return 2; }
  w="$(mktemp -d)" || return 2
  : > "$w/names"
  local name state due issue sites extra prog trc src v
  while IFS=$'\t' read -r name state due issue sites extra || [ -n "$name" ]; do
    case "$name" in ''|'#'*) continue ;; esac
    rows=$((rows + 1))
    if [ -n "${extra:-}" ] || [ -z "${sites:-}" ]; then
      echo "seed forms: FAIL $name: malformed row (want five TAB-separated fields: name state due issue sites)"; bad=1; continue
    fi
    if ! [[ "$name" =~ ^[a-z0-9_]+$ ]]; then echo "seed forms: FAIL '$name': a name is [a-z0-9_]+"; bad=1; continue; fi
    if grep -qxF "$name" "$w/names"; then echo "seed forms: FAIL $name: listed twice"; bad=1; continue; fi
    echo "$name" >> "$w/names"
    if [ "$state" != seed ] && [ "$state" != tree ]; then echo "seed forms: FAIL $name: state '$state' is neither 'seed' nor 'tree'"; bad=1; continue; fi
    if ! [[ "$due" =~ ^[0-9]+$ ]] || [ "$due" -ge 126 ]; then echo "seed forms: FAIL $name: due '$due' is not an exit value below 126"; bad=1; continue; fi
    if ! [[ "$issue" =~ ^#[0-9]+$ ]]; then echo "seed forms: FAIL $name: issue '$issue' is not #N"; bad=1; continue; fi
    prog="$dir/$name.al"
    if [ ! -f "$prog" ]; then echo "seed forms: FAIL $name: the row has no program $prog"; bad=1; continue; fi
    trc="$(sf_run "$tree" "$prog" "$w/$name.tree.err")"
    src="$(sf_run "$seed" "$prog" "$w/$name.seed.err")"
    v="$(sf_decide "$state" "$due" "$trc" "$src")"
    echo "seed forms: $name state=$state due=$due tree=$trc seed=$src $issue $v"
    case "$state" in seed) nseed=$((nseed + 1)) ;; tree) ntree=$((ntree + 1)) ;; esac
    case "$v" in
      OK) ;;
      TREE-REGRESSED)
        echo "seed forms: FAIL $name: the tree compiler answers $trc where $due is due — the form REGRESSED in the tree ($issue)"
        sed 's/^/    tree stderr: /' "$w/$name.tree.err" | head -3
        bad=1 ;;
      SEED-NOW-HANDLES)
        echo "seed forms: FAIL $name: the seed now handles $name (answers $due). Retire this entry and remove its workaround comments at: $sites"
        bad=1 ;;
      TREE-NOW-HANDLES)
        echo "seed forms: FAIL $name: the tree now handles $name ($issue answers $due). Change its state to 'seed', so the registry tracks the seed until a promotion; its workaround sites are: $sites"
        bad=1 ;;
      *) echo "seed forms: FAIL $name: no verdict ($v)"; bad=1 ;;
    esac
  done < "$reg"
  ## Every program has a row: an orphan is a limitation someone planted and nobody checks.
  local f b
  for f in "$dir"/*.al; do
    [ -e "$f" ] || continue
    b="$(basename "$f" .al)"
    grep -qxF "$b" "$w/names" || { echo "seed forms: FAIL $b: program $f has no row in the registry"; bad=1; }
  done
  rm -rf "$w"
  if [ -n "$declared" ]; then
    if [ "$rows" != "$declared" ]; then echo "seed forms: FAIL: the registry declares live-rows: $declared but $rows rows were parsed"; bad=1; fi
  elif [ "$rows" = 0 ]; then
    echo "seed forms: FAIL: the registry lists no form — what was checked is unknown (an emptied registry says '# live-rows: 0')"; bad=1
  fi
  local sh
  sh="$( (sha256sum "$seed" 2>/dev/null || shasum -a 256 "$seed" 2>/dev/null) | cut -c1-12)"
  echo "seed forms: rows=$rows seed=$nseed tree=$ntree seed_sha256=${sh:-unknown}"
  if [ "$bad" != 0 ]; then echo "*** seed forms: FAILURES ***"; return 1; fi
  echo "*** seed forms: PASS ***"
  return 0
}

## The #600 gate-of-the-gate. It needs no compiler. A FAKE compiler reads `## fake-<role>-rc: N` from
## the program and exits N, so each planted tree hands the real decider, the registry parser and the
## orphan walk a known pair of results. The controls must stay green and the plants must be refused
## by name. So an always-pass decider loses the plants, an always-fail decider loses the controls, and
## a parser that skips rows fails the malformed and empty cases.
sf_self_test() {
  local st bad=0 cases=0
  st="$(mktemp -d)" || return 2
  cat > "$st/fake" <<'EOF'
#!/usr/bin/env bash
role="$(basename "$0")"
rc="$(sed -n "s/^## fake-$role-rc: \([0-9]*\)$/\1/p" "$2" | head -1)"
exit "${rc:-99}"
EOF
  chmod +x "$st/fake"
  ## case <label> <want-exit> <needle>... ; the registry body is on stdin, programs are made by `prog`.
  sf_case() {
    local label="$1" want="$2"; shift 2
    local d="$st/$label" out rc n
    mkdir -p "$d/progs" "$d/bin"
    cp "$st/fake" "$d/bin/tree"; cp "$st/fake" "$d/bin/seed"
    cat > "$d/reg"
    [ -f "$st/$label.progs" ] && ( cd "$d/progs" && bash "$st/$label.progs" )
    out="$(SEED_FORMS_REGISTRY="$d/reg" SEED_FORMS_DIR="$d/progs" SEED_FORMS_TREE="$d/bin/tree" \
      SEED_FORMS_SEED="$d/bin/seed" sf_check 2>&1)"; rc=$?
    cases=$((cases + 1))
    if [ "$rc" != "$want" ]; then
      echo "FAIL seed forms self-test $label: exit $rc, want $want"; printf '%s\n' "$out" | sed 's/^/      /' | head -8; bad=1; return
    fi
    for n in "$@"; do
      case "$out" in *"$n"*) ;; *) echo "FAIL seed forms self-test $label: output lacks '$n'"; bad=1; return ;; esac
    done
    echo "ok   seed forms self-test $label"
  }
  mk() { # label name tree_rc seed_rc
    printf 'printf "## fake-tree-rc: %s\\n## fake-seed-rc: %s\\nmain := fn() -> u64 { 42 }\\n" > %s.al\n' "$3" "$4" "$2" >> "$st/$1.progs"
  }
  T=$'\t'
  ## CONTROLS — must stay green.
  mk ctl-seed a 42 0
  sf_case ctl-seed 0 "a state=seed due=42 tree=42 seed=0 #1 OK" "rows=1 seed=1 tree=0" "*** seed forms: PASS" < <(printf '# c\n\na%sseed%s42%s#1%sx.al:f\n' "$T" "$T" "$T" "$T")
  mk ctl-tree b 139 139
  sf_case ctl-tree 0 "b state=tree due=42 tree=139 seed=139 #2 OK" "rows=1 seed=0 tree=1" < <(printf 'b%stree%s42%s#2%sy.al:g\n' "$T" "$T" "$T" "$T")
  mk ctl-tree-seedok c 1 42
  sf_case ctl-tree-seedok 0 "c state=tree due=42 tree=1 seed=42 #3 OK" < <(printf 'c%stree%s42%s#3%sz.al:h\n' "$T" "$T" "$T" "$T")
  ## PLANTS — each must be refused, by name.
  mk tree-regressed d 0 0
  sf_case tree-regressed 1 "FAIL d:" "REGRESSED in the tree" "*** seed forms: FAILURES" < <(printf 'd%sseed%s42%s#4%ss.al:k\n' "$T" "$T" "$T" "$T")
  mk seed-now-handles e 42 42
  sf_case seed-now-handles 1 "the seed now handles e" "Retire this entry" "src/ast.al:fn_x; lib/y.al:fn_z" < <(printf 'e%sseed%s42%s#5%ssrc/ast.al:fn_x; lib/y.al:fn_z\n' "$T" "$T" "$T" "$T")
  mk tree-now-handles f 42 139
  sf_case tree-now-handles 1 "the tree now handles f" "Change its state to 'seed'" < <(printf 'f%stree%s42%s#6%ss.al:k\n' "$T" "$T" "$T" "$T")
  mk orphan g 42 0; mk orphan h 42 0
  sf_case orphan 1 "FAIL h: program" "has no row" < <(printf 'g%sseed%s42%s#7%ss.al:k\n' "$T" "$T" "$T" "$T")
  sf_case no-program 1 "FAIL i: the row has no program" < <(printf 'i%sseed%s42%s#8%ss.al:k\n' "$T" "$T" "$T" "$T")
  sf_case empty 1 "the registry lists no form" < <(printf '# only comments\n\n')
  ## CONTROL: an emptied registry that declares it passes, and says how many rows it checked.
  sf_case declared-empty 0 "rows=0" "*** seed forms: PASS" < <(printf '# live-rows: 0\n# only comments\n')
  ## A declaration the parse disagrees with is refused: a row the parser skipped cannot hide.
  mk declared-mismatch n 42 0
  sf_case declared-mismatch 1 "declares live-rows: 0 but 1 rows" < <(printf '# live-rows: 0\nn%sseed%s42%s#9%ss.al:k\n' "$T" "$T" "$T" "$T")
  mk bad-due j 42 0
  sf_case bad-due 1 "FAIL j: due '300'" < <(printf 'j%sseed%s300%s#9%ss.al:k\n' "$T" "$T" "$T" "$T")
  mk bad-state k 42 0
  sf_case bad-state 1 "FAIL k: state 'fixed'" < <(printf 'k%sfixed%s42%s#9%ss.al:k\n' "$T" "$T" "$T" "$T")
  mk short-row l 42 0
  sf_case short-row 1 "FAIL l: malformed row" < <(printf 'l%sseed%s42%s#9\n' "$T" "$T" "$T")
  mk dup m 42 0
  sf_case dup 1 "FAIL m: listed twice" < <(printf 'm%sseed%s42%s#9%ss.al:k\nm%sseed%s42%s#9%ss.al:k\n' "$T" "$T" "$T" "$T" "$T" "$T" "$T" "$T")
  rm -rf "$st"
  local want=15
  echo "seed forms self-test: cases=$cases failures=$bad"
  if [ "$cases" != "$want" ]; then echo "FAIL seed forms self-test: ran $cases cases, want $want"; return 1; fi
  [ "$bad" = 0 ] || return 1
  return 0
}

case "${1:-}" in
  --self-test) sf_self_test; exit $? ;;
  '') cd "$ROOT" || exit 2; sf_check; exit $? ;;
  *) echo "usage: bash scripts/seed_forms_check.sh [--self-test]" >&2; exit 2 ;;
esac
