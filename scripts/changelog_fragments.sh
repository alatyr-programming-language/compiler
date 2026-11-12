#!/usr/bin/env bash
# scripts/changelog_fragments.sh — one changelog entry, one new file (#1566, #1390 option 3).
#
# ## Why
#
# Every user-visible PR used to append its bullet at the end of CHANGELOG.md's `## Unreleased`, so any
# two of them conflicted at that one anchor. land.sh's screen then sent each such PR to a solo gate
# (#1312, #1319), and every hand restack settled the same conflict again. A fragment is a file of its
# own, `changelog.d/<issue>-<slug>.md`, so two PRs never touch one path, and scripts/promote.sh releases
# the fragments with the version (CHANGELOG.md, "When the version moves").
#
# ## What it holds
#
#   - a fragment's NAME is `<issue>-<slug>.md`: the issue number the entry cites first, then a slug of
#     lower-case letters, digits and single hyphens. changelog.d/README.md is the one other file;
#   - a fragment's BODY is one or more `- ` bullets in CHANGELOG.md's style, each continuation line
#     indented two spaces or more (a nested list item and its own continuation go deeper, as in the
#     released sections): no blank line, no heading, no conflict marker, a final newline;
#   - an ADDITION rule against the merge base, like the strict forms: a line the tree adds inside
#     CHANGELOG.md's `## Unreleased` is refused. A deletion passes, and so does a promotion, which
#     empties the section. A rewritten Unreleased bullet is an added line too: delete the old one and
#     write the new text as a fragment.
#
# Base resolution, in order: `$1`, `$ALATYR_CHANGELOG_BASE`, `git merge-base origin/main HEAD`,
# `git merge-base main HEAD`. It needs no compiler and costs well under a second.
#
# Usage:  bash scripts/changelog_fragments.sh --check [<base-rev>]
#         bash scripts/changelog_fragments.sh --assemble [<dir>]   # the release text, issue order
#         bash scripts/changelog_fragments.sh --self-test
set -u
export LC_ALL=C
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FRAG_DIR_REL=changelog.d

## frag_name_ok NAME -> 0 when NAME is `<issue>-<slug>.md`
frag_name_ok() {
  printf '%s\n' "$1" | grep -Eqx '[1-9][0-9]*-[a-z0-9]+(-[a-z0-9]+)*\.md'
}

## frag_body_ok FILE -> 0 when FILE is one or more bullets; otherwise prints why and returns 1
frag_body_ok() {
  [ -s "$1" ] || { echo "empty"; return 1; }
  [ "$(tail -c 1 "$1" | od -An -c | tr -d ' ')" = '\n' ] || { echo "no final newline"; return 1; }
  ! grep -q "$(printf '\r')" "$1" || { echo "carries a carriage return (CRLF line ends)"; return 1; }
  awk 'NR == 1 && !/^- [^ ]/ { print "line 1 does not open a `- ` bullet"; bad = 1; exit }
       /^(<<<<<<<|=======|>>>>>>>|\|\|\|\|\|\|\|)/ { print "line " NR " is a conflict marker"; bad = 1; exit }
       /^[[:space:]]*$/ { print "line " NR " is blank"; bad = 1; exit }
       /^#/ { print "line " NR " is a heading"; bad = 1; exit }
       !/^- [^ ]/ && !/^  +[^ ]/ { print "line " NR " is neither a `- ` bullet nor a continuation indented two spaces or more"; bad = 1; exit }
       END { exit bad }' "$1"
}

## unreleased_section FILE -> stdout: the lines strictly inside FILE's `## Unreleased` section
unreleased_section() {
  awk '/^## / { open = ($0 ~ /^## Unreleased[[:space:]]*$/); next } open' "$1"
}

## unreleased_added BASEFILE HEADFILE -> stdout: the non-blank Unreleased lines HEAD has and BASE has not
unreleased_added() {
  local d; d="$(mktemp -d)"
  unreleased_section "$1" | grep -v '^[[:space:]]*$' | sort > "$d/b"
  unreleased_section "$2" | grep -v '^[[:space:]]*$' | sort > "$d/h"
  comm -13 "$d/b" "$d/h"
  rm -rf "$d"
}

## check_tree ROOTDIR BASEFILE LABEL -> the verdict; 0 clean, 1 refused
check_tree() {
  local root="$1" basefile="$2" label="$3" f n=0 bad=0 why added na
  if [ -d "$root/$FRAG_DIR_REL" ]; then
    ## `.[!.]*` too: a hidden file is neither checked nor assembled, yet promote.sh deletes every
    ## tracked file here, so its text would vanish without a word.
    for f in "$root/$FRAG_DIR_REL"/* "$root/$FRAG_DIR_REL"/.[!.]*; do
      [ -e "$f" ] || continue
      case "$(basename "$f")" in README.md) continue ;; esac
      n=$((n + 1))
      if [ -d "$f" ] || ! frag_name_ok "$(basename "$f")"; then
        echo "changelog fragments: FAIL $FRAG_DIR_REL/$(basename "$f"): the name is not <issue>-<slug>.md"
        bad=1; continue
      fi
      why="$(frag_body_ok "$f")" || { echo "changelog fragments: FAIL $FRAG_DIR_REL/$(basename "$f"): $why"; bad=1; }
    done
  fi
  ## The rule reads one section, so a tree that renamed, doubled or dropped it would answer "nothing
  ## added" while adding: fail closed. A promotion keeps exactly one heading.
  if [ ! -f "$root/CHANGELOG.md" ]; then
    echo "changelog fragments: FAIL CHANGELOG.md does not exist"; bad=1
  elif [ "$(grep -c '^## Unreleased[[:space:]]*$' "$root/CHANGELOG.md")" != 1 ]; then
    echo "changelog fragments: FAIL CHANGELOG.md has $(grep -c '^## Unreleased[[:space:]]*$' "$root/CHANGELOG.md") '## Unreleased' headings, want exactly 1"; bad=1
  fi
  added="$(unreleased_added "$basefile" "$root/CHANGELOG.md" 2>/dev/null)"
  na=0; [ -n "$added" ] && na="$(printf '%s\n' "$added" | wc -l | tr -d ' ')"
  if [ "$na" != 0 ]; then
    echo "changelog fragments: FAIL CHANGELOG.md gains $na line(s) under ## Unreleased; write the entry as"
    echo "  $FRAG_DIR_REL/<issue>-<slug>.md instead (a rewritten bullet: delete it there, write it here):"
    printf '%s\n' "$added" | head -5 | sed 's/^/    + /'
    bad=1
  fi
  echo "changelog fragments: base=$label fragments=$n unreleased-added=$na"
  [ "$bad" = 0 ] && echo "*** changelog fragments: every entry is a well-formed fragment, and none was added to CHANGELOG.md ***"
  return "$bad"
}

resolve_base() {
  [ -n "${1:-}" ] && { git -C "$ROOT" rev-parse --verify -q "$1^{commit}"; return; }
  [ -n "${ALATYR_CHANGELOG_BASE:-}" ] && { git -C "$ROOT" rev-parse --verify -q "$ALATYR_CHANGELOG_BASE^{commit}"; return; }
  git -C "$ROOT" merge-base origin/main HEAD 2>/dev/null && return 0
  git -C "$ROOT" merge-base main HEAD 2>/dev/null
}

cmd_check() {
  local base d rc
  base="$(resolve_base "${1:-}")" || base=""
  [ -n "$base" ] || { echo "changelog fragments: FAIL no base revision (give one, or fetch origin/main)"; return 2; }
  d="$(mktemp -d)"
  git -C "$ROOT" show "$base:CHANGELOG.md" > "$d/base" 2>/dev/null \
    || { echo "changelog fragments: FAIL the base $base has no CHANGELOG.md"; rm -rf "$d"; return 2; }
  check_tree "$ROOT" "$d/base" "$(git -C "$ROOT" rev-parse --short=8 "$base")"; rc=$?
  rm -rf "$d"; return "$rc"
}

## assemble DIR -> stdout: every fragment's body, ordered by issue number, then by name
assemble() {
  local dir="$1" f
  [ -d "$dir" ] || return 0
  for f in "$dir"/*.md; do
    [ -e "$f" ] || continue
    case "$(basename "$f")" in README.md) continue ;; esac
    printf '%s\t%s\n' "$(basename "$f" | cut -d- -f1)" "$f"
  done | sort -t "$(printf '\t')" -k1,1n -k2,2 | cut -f2- | while IFS= read -r f; do cat "$f"; done
}

self_test() {
  local d rc=0 n=0 out
  d="$(mktemp -d)"; trap 'rm -rf "$d"' RETURN
  chk() { n=$((n + 1)); if [ "$2" = "$3" ]; then echo "  ok   $1"; else echo "  FAIL $1: got [$2] want [$3]"; rc=1; fi; }
  printf '# C\n\n## Policy\n\ntext\n\n## Unreleased\n\n- **Old (#1).** It was.\n  more.\n\n## 0.1.0 — d\n\n- rel\n' > "$d/base"
  mk() { rm -rf "$d/t"; mkdir -p "$d/t/$FRAG_DIR_REL"; cp "$d/base" "$d/t/CHANGELOG.md"; printf 'x\n' > "$d/t/$FRAG_DIR_REL/README.md"; }
  run() { check_tree "$d/t" "$d/base" planted > "$d/out" 2>&1; echo "$?:$(grep -c '^changelog fragments: FAIL' "$d/out")"; }

  mk; chk "control: an untouched tree with no fragment is clean" "$(run)" "0:0"
  mk; printf -- '- **A fix (#12).** It moves.\n  On.\n- **And (#12).** Too.\n' > "$d/t/$FRAG_DIR_REL/12-a-fix.md"
  chk "control: a well-formed fragment of two bullets is clean" "$(run)" "0:0"
  mk; sed -i.b '/^- \*\*Old/,/^  more\.$/d' "$d/t/CHANGELOG.md"
  chk "control: deleting an Unreleased bullet passes" "$(run)" "0:0"
  mk; awk '/^## Unreleased$/ { print; print ""; print "## 0.2.0 — e"; next } { print }' "$d/base" > "$d/t/CHANGELOG.md"
  chk "control: a promotion that releases the section passes" "$(run)" "0:0"
  mk; sed -i.b 's/^text$/text, edited/' "$d/t/CHANGELOG.md"
  chk "control: an edit outside ## Unreleased passes" "$(run)" "0:0"

  mk; awk '{ print } /^  more\.$/ { print "- **New (#2).** Added."; }' "$d/base" > "$d/t/CHANGELOG.md"
  chk "plant: a bullet added under ## Unreleased is refused" "$(run)" "1:1"
  mk; sed -i.b 's/It was\./It was, reworded./' "$d/t/CHANGELOG.md"
  chk "plant: a reworded Unreleased bullet is refused" "$(run)" "1:1"
  mk; printf -- '- x\n' > "$d/t/$FRAG_DIR_REL/fix-12.md"
  chk "plant: a name that does not open with the issue is refused" "$(run)" "1:1"
  mk; printf -- '- x\n' > "$d/t/$FRAG_DIR_REL/12-Fix.md"
  chk "plant: an upper-case slug is refused" "$(run)" "1:1"
  mk; printf -- '- x\n' > "$d/t/$FRAG_DIR_REL/12-fix.txt"
  chk "plant: a name without .md is refused" "$(run)" "1:1"
  mk; : > "$d/t/$FRAG_DIR_REL/12-fix.md"
  chk "plant: an empty fragment is refused" "$(run)" "1:1"
  mk; printf '## 0.3.0\n- x\n' > "$d/t/$FRAG_DIR_REL/12-fix.md"
  chk "plant: a heading in a fragment is refused" "$(run)" "1:1"
  mk; printf -- '- x\n\n- y\n' > "$d/t/$FRAG_DIR_REL/12-fix.md"
  chk "plant: a blank line in a fragment is refused" "$(run)" "1:1"
  mk; printf -- '- x\n<<<<<<< HEAD\n' > "$d/t/$FRAG_DIR_REL/12-fix.md"
  chk "plant: a conflict marker in a fragment is refused" "$(run)" "1:1"
  mk; printf -- '- x\ncontinued flush\n' > "$d/t/$FRAG_DIR_REL/12-fix.md"
  chk "plant: an unindented continuation is refused" "$(run)" "1:1"
  mk; printf -- '- x\n   three spaces is a continuation too\n' > "$d/t/$FRAG_DIR_REL/12-fix.md"
  chk "control: a three-space continuation is still a continuation" "$(run)" "0:0"
  mk; printf -- ' - x\n' > "$d/t/$FRAG_DIR_REL/12-fix.md"
  chk "plant: a fragment that opens indented is refused" "$(run)" "1:1"
  mk; printf -- '- **A (#12).** It:\n  - one level;\n    - two levels,\n      continued.\n' > "$d/t/$FRAG_DIR_REL/12-fix.md"
  chk "control: a list nested two levels deep, with its continuation, is clean" "$(run)" "0:0"
  mk; printf -- '- x' > "$d/t/$FRAG_DIR_REL/12-fix.md"
  chk "plant: a fragment with no final newline is refused" "$(run)" "1:1"
  mk; printf -- '- x\n' > "$d/t/$FRAG_DIR_REL/12-fix.md"; mkdir "$d/t/$FRAG_DIR_REL/13-dir.md"
  chk "plant: a directory in changelog.d is refused" "$(run)" "1:1"
  mk; printf -- '- x\n' > "$d/t/$FRAG_DIR_REL/.12-fix.md"
  chk "plant: a hidden file in changelog.d is refused" "$(run)" "1:1"
  mk; printf -- '- x\r\n' > "$d/t/$FRAG_DIR_REL/12-fix.md"
  chk "plant: CRLF line ends in a fragment are refused" "$(run)" "1:1"
  mk; sed -i.b 's/^## Unreleased$/## Unreleased (next)/' "$d/t/CHANGELOG.md"; printf -- '- **New (#2).** Added.\n' >> "$d/t/CHANGELOG.md"
  chk "plant: a renamed Unreleased heading (the rule would read no section) is refused" "$(run)" "1:1"
  mk; rm "$d/t/CHANGELOG.md"; chk "plant: a deleted CHANGELOG.md is refused, not read as nothing added" "$(run)" "1:1"
  mk; chk "the coverage line names the base and both counts" \
    "$(check_tree "$d/t" "$d/base" planted | grep -c '^changelog fragments: base=planted fragments=0 unreleased-added=0$')" "1"

  mkdir -p "$d/a"; printf -- '- c\n' > "$d/a/100-c.md"; printf -- '- b\n  b2\n' > "$d/a/9-b.md"
  printf -- '- a\n' > "$d/a/9-a.md"; printf 'readme\n' > "$d/a/README.md"
  chk "assemble orders by issue NUMBER, then by name, and skips the README" "$(assemble "$d/a" | tr '\n' '|')" "- a|- b|  b2|- c|"
  chk "assemble of a missing directory is empty" "$(assemble "$d/none")" ""
  [ "$rc" = 0 ] && echo "changelog fragments self-test: $n checks, 0 failed" || echo "changelog fragments self-test: FAILED"
  return "$rc"
}

case "${1:-}" in
  --check) shift; cmd_check "$@" ;;
  --assemble) shift; assemble "${1:-$ROOT/$FRAG_DIR_REL}" ;;
  --self-test) self_test ;;
  -h|--help|'') sed -n '2,/^set -u/p' "${BASH_SOURCE[0]}" | sed '$d'; [ -n "${1:-}" ] ;;
  *) echo "changelog fragments: unknown argument '$1' (try --help)" >&2; exit 2 ;;
esac
