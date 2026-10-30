#!/usr/bin/env bash
# scripts/spec_pin_check.sh — the specification pin is ONE number, and this refuses a tree where the
# places that state it disagree (issue #1000).
#
# WHY THIS EXISTS. TOOL-21 (spec v1.1.0, Tooling §4) says `version` MUST identify the implementation and
# MUST report the revision of the specification it conforms to — "reporting only the former leaves a user
# unable to tell what the toolchain implements". The compiler now answers both axes (`alatyr <version>,
# spec <revision>`), and the revision half is a number that lives in FIVE places at once:
#
#   src/spec_revision.al              pub SPEC_REVISION := "<rev>"      — the one the binary bakes
#   README.md                        the badge and the prose pin sentence  — what a visitor reads
#   AGENTS.md                        "**The pin.**"                        — what an agent is told
#   scripts/package_cli_test.sh      the expected `alatyr <version>, spec <rev>` line
#   seed/VERSION                     `# spec-pin: <rev>` in CURRENT SEED    — what the seed is under
#
# Four of those five are prose, and prose drifts. `CHANGELOG.md` already records that the expected
# `--version` line "is the one that gets forgotten" when a version moves; a revision move across four
# documents by hand is the same failure with four times the surface, and nothing in the tree noticed it
# because nothing compared them. This script is that comparison. It is a refusal, not a warning: a tree
# where README says 1.0.0 and the binary answers 1.1.0 is a tree that lies about what it implements,
# which is the exact defect #1000 was filed about, one level up.
#
# WHAT IS AUTHORITATIVE HERE is the constant in `src/spec_revision.al`, because that is the copy the
# compiler bakes into the artifact a user runs — the other four are claims ABOUT it. The specification
# repository remains the authority on what exists; this one only checks that its five statements name the
# same one, plus that the tag it cites is real (below).
#
# THE TAG HALF, and why it may be skipped. The compiler pins TAGGED RELEASES only — a release number,
# never a bare commit hash — so `v<revision>` must exist in the specification checkout. That checkout is a
# SIBLING repository, found by walking up from this tree (a lane worktree at `.worktrees/<lane>/` has it
# two levels up) or named by `$ALATYR_SPEC_ROOT`, and it is not part of this one: on a machine that has
# only this repository — every GitHub gate runner included — there is nothing to ask, and the half reports
# SKIPPED with the reason rather than passing silently. A skip that is not said out loud is how a check
# becomes decoration.
#
# WHAT IT DELIBERATELY DOES NOT READ: the dated promotion entries (in `seed/HISTORY.md` since #1130). They are
# APPEND-ONLY records, and dozens of them end with "The specification pin (1.0.0 plus post-tag commits to
# b4e7979) did not move." — a true statement about the promotion that wrote it and a FALSE one about
# today. Scanning them would make this check permanently red, or would force rewriting history; both are
# worse than the keyed line it reads instead (`# spec-pin:`, which exists only in CURRENT SEED). Same
# reason for the other files: this reads CITATIONS of the pin, not every version number in the tree —
# `package.al`'s 0.2.16 is the compiler's own version and never moves with the pin (CHANGELOG.md,
# "Versioning policy").
#
# Usage:  bash scripts/spec_pin_check.sh [<root>]
# Exit:   0 = every site agrees;  1 = a site disagrees (it is named, with both numbers);
#         2 = the check could not be performed (no constant, or two of them — a check that cannot say
#             which number is the pin must not report agreement).
set -u

## Every citation of the pin in one file, one per line, deduplicated. `pat` is the LINE filter that
## marks a line as a CITATION of the specification revision, so an unrelated version number elsewhere in
## the same document (a compiler release, a fixture's `version = "0.1.0"`) is not read as a pin claim.
## It filters LINES, so every number on a cited line is taken as a citation of it — that is right for
## prose (the badge line and the pin sentence carry nothing else) and wrong for a test's expected output
## line, which names the compiler's version beside the revision; that site is extracted by its own
## anchored pattern below, and the difference is stated rather than smoothed over.
cites() { # file line-filter
  local f="$1" pat="$2"
  [ -f "$f" ] || return 0
  grep -nE "$pat" "$f" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | sort -u
}

## AGENTS.md's pin is a BULLET, not a keyword. Scoping to "**The pin.**" and its indented continuation
## is what keeps the rest of that file — which carries `v0.2.0`, `0.1.0` and `0.2.1` as compiler
## versions — out of the comparison.
agents_pin_block() { # file
  awk '
    /^- \*\*The pin\.\*\*/ { inpin = 1 }
    inpin && !/^- \*\*The pin\.\*\*/ && !/^  / { inpin = 0 }
    inpin { print }
  ' "$1" 2>/dev/null
}

## THE DECIDER. The self-test drives this against planted trees: on a tree that agrees, this check never
## reaches its own failure verdict, so a neutered decider would print the same green line forever.
pin_check() { # root
  local root="$1" const_file readme_f agents_f pkgtest_f seed_f
  ## `sites` starts at ONE: the constant is itself a site, and it is the one the other four are
  ## compared against. A `sites=` that counted only the prose would understate what was joined.
  local rev n bad=0 sites=1 skip="" spec_root tag_state tag_rev tag_commit
  local checked="src/spec_revision.al"

  const_file="$root/src/spec_revision.al"
  readme_f="$root/README.md"
  agents_f="$root/AGENTS.md"
  pkgtest_f="$root/scripts/package_cli_test.sh"
  seed_f="$root/seed/VERSION"

  ## THE CONSTANT — the one copy the binary bakes. Zero or two of them is not a disagreement to report,
  ## it is a check that cannot say what the pin IS, so it refuses (2) rather than agreeing (0).
  n="$(grep -cE '^pub SPEC_REVISION := "[0-9]+\.[0-9]+\.[0-9]+"$' "$const_file" 2>/dev/null)"
  n="${n:-0}"
  if [ "$n" != "1" ]; then
    echo "spec pin: FAIL — $const_file declares the pin $n time(s); it must declare it exactly once as" >&2
    echo "  'pub SPEC_REVISION := \"<major>.<minor>.<patch>\"'. Refusing to guess which one is the pin." >&2
    return 2
  fi
  rev="$(sed -n 's/^pub SPEC_REVISION := "\(.*\)"$/\1/p' "$const_file")"

  ## SITE 1 — README.md: the badge and the prose pin sentence. A README that cites NO revision is a
  ## README that does not say what this tool implements, which is #1000 in its published form.
  local r
  r="$(cites "$readme_f" '[Ss]pec(ification)? revision|conforms to spec|badge/spec-')"
  if [ -z "$r" ]; then
    echo "spec pin: FAIL — README.md cites no specification revision at all (badge or prose), so what" >&2
    echo "  this tree implements is unstated where every visitor reads it." >&2
    bad=1
  elif [ "$r" != "$rev" ]; then
    echo "spec pin: FAIL — README.md cites $(printf '%s' "$r" | tr '\n' '/' | sed 's|/$||'), the" >&2
    echo "  constant in src/spec_revision.al is $rev." >&2
    bad=1
  else
    sites=$((sites + 1)); checked="$checked README.md"
  fi

  ## SITE 2 — AGENTS.md "The pin".
  local a
  a="$(agents_pin_block "$agents_f" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | sort -u)"
  if [ -z "$a" ]; then
    echo "spec pin: FAIL — AGENTS.md has no '- **The pin.**' bullet citing a revision, so the agent-" >&2
    echo "  facing pin is missing and nothing ties it to src/spec_revision.al." >&2
    bad=1
  elif [ "$a" != "$rev" ]; then
    echo "spec pin: FAIL — AGENTS.md 'The pin' cites $(printf '%s' "$a" | tr '\n' '/' | sed 's|/$||')," >&2
    echo "  the constant in src/spec_revision.al is $rev. The pin moves in its own explicit commit" >&2
    echo "  (AGENTS.md, Authority) — and it moves EVERYWHERE at once, or not at all." >&2
    bad=1
  else
    sites=$((sites + 1)); checked="$checked AGENTS.md"
  fi

  ## SITE 3 — the expected `--version` line. CHANGELOG.md calls this file "the one that gets forgotten";
  ## it is the only site that asserts the ANSWER rather than a claim about it, so a drift here turns the
  ## gate red with a diagnostic that never names a version. Anchored on ', spec ' (with the comma and a
  ## space) so that the word `inspect` — which appears in this file — cannot match.
  local p
  p="$(grep -oE ', spec [0-9]+\.[0-9]+\.[0-9]+' "$pkgtest_f" 2>/dev/null |
       grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | sort -u)"
  if [ -z "$p" ]; then
    echo "spec pin: FAIL — scripts/package_cli_test.sh expects no ', spec <revision>' half in the" >&2
    echo "  --version output, so it no longer pins what TOOL-21 requires the tool to answer." >&2
    bad=1
  elif [ "$p" != "$rev" ]; then
    echo "spec pin: FAIL — scripts/package_cli_test.sh expects ', spec $(printf '%s' "$p" | tr '\n' '/')'" >&2
    echo "  and the constant in src/spec_revision.al is $rev." >&2
    bad=1
  else
    sites=$((sites + 1)); checked="$checked scripts/package_cli_test.sh"
  fi

  ## SITE 4 — seed/VERSION's CURRENT SEED pin note, a KEYED line. Keyed rather than a region scan
  ## because that file is append-only history: its dated entries cite the pin as it stood at each
  ## promotion, and a region scan would read those as claims about today.
  local s
  s="$(grep -oE 'spec-pin:[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+' "$seed_f" 2>/dev/null |
       grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | sort -u)"
  if [ -z "$s" ]; then
    skip="$skip seed/VERSION(no 'spec-pin:' line in CURRENT SEED)"
  elif [ "$s" != "$rev" ]; then
    echo "spec pin: FAIL — seed/VERSION's CURRENT SEED pin note says $(printf '%s' "$s" | tr '\n' '/' | sed 's|/$||')," >&2
    echo "  the constant in src/spec_revision.al is $rev. The seed answers what it was compiled from;" >&2
    echo "  if the pin moved, say so there, in the pin commit." >&2
    bad=1
  else
    sites=$((sites + 1)); checked="$checked seed/VERSION"
  fi

  ## THE TAG — the pin cites a tagged release, so the tag must exist. Skipped, out loud, when this
  ## machine holds only this repository. The search walks UP from the tree, because a lane worktree sits
  ## at `.worktrees/<lane>/` and its sibling specification checkout is two levels up, not one; a
  ## candidate must be a git work tree AND hold `spec/120-tooling.md`, so an unrelated directory named
  ## `spec` cannot raise a false refusal. `$ALATYR_SPEC_ROOT` overrides the search (the self-test uses it
  ## to make both halves deterministic).
  spec_root=""
  if [ -n "${ALATYR_SPEC_ROOT:-}" ]; then
    spec_root="$ALATYR_SPEC_ROOT"
  else
    local up="$root"
    while [ "$up" != "/" ]; do
      if git -C "$up/spec" rev-parse --is-inside-work-tree >/dev/null 2>&1 &&
         [ -f "$up/spec/spec/120-tooling.md" ]; then spec_root="$up/spec"; break; fi
      up="$(dirname "$up")"
    done
  fi
  tag_state="SKIPPED"
  if [ -n "$spec_root" ] && git -C "$spec_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    tag_rev="$(git -C "$spec_root" rev-parse -q --verify "refs/tags/v$rev" 2>/dev/null)"
    if [ -z "$tag_rev" ]; then
      echo "spec pin: FAIL — the specification checkout at $spec_root has no tag 'v$rev', and the" >&2
      echo "  compiler pins tagged releases only. Either tag the release it pins or move the pin to a" >&2
      echo "  revision that is tagged; do not cite a number that does not exist." >&2
      bad=1
      tag_state="MISSING"
    else
      tag_commit="$(git -C "$spec_root" rev-parse --short "v$rev^{commit}" 2>/dev/null)"
      tag_state="v$rev@$tag_commit"
      sites=$((sites + 1)); checked="$checked tag:v$rev"
    fi
  else
    skip="$skip spec-repo(no tagged checkout found above $root; set ALATYR_SPEC_ROOT)"
  fi

  if [ "$bad" != "0" ]; then
    echo "*** spec pin: the tree states DIFFERENT specification revisions — see above. ***" >&2
    return 1
  fi

  ## The proof-of-work line. scripts/full.sh refuses a run where this is absent, so "agreed" can be
  ## told apart from "compared nothing". `sites=` counts what was actually compared, and every skipped
  ## half is named in the same line rather than left to silence.
  echo "spec pin: revision=$rev sites=$sites tag=$tag_state${skip:+ skipped=$skip}"
  echo "spec pin: OK — $checked all state specification revision $rev."
  [ -z "$skip" ] || echo "spec pin: NOT CHECKED:$skip."
  return 0
}


ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
pin_check "$ROOT"
exit $?
