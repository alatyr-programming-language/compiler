#!/usr/bin/env bash
# scripts/fixture_oracle.sh — what a FIXTURE declares its outcome to be. ONE implementation (#683).
#
# Two instruments ask this question and must not get two answers: `ir_diff.sh` compares the legacy x86
# path with the x86-via-IR path on one program, and `xbackend_diff.sh` compares four backends on one
# program. Both need the same fact — what does this file SAY it should do — and each had its own copy of
# the answer until this file existed. A second reader of the same declaration is the same defect class the
# IR removes from the emitters: one question, two places, free to drift.
#
# Source it:  . "$(dirname "$0")/fixture_oracle.sh"
#
# ## What counts as a declaration
#
# Only the header — the first 30 lines — and only these two shapes, because those are the two a fixture
# can state in a machine-readable way today:
#
#   ## build_reject ...            the program MUST be refused at compile time (the corpus manifest's
#                                  `reject_*` class spells its requirement in prose; this is the marker)
#   ## Expected ... exit: N        the program must RUN and exit N (also accepts `status: N`, `=N`, bare)
#   ## @target(<arch>)             the asm() body is written for <arch>; a walk on another backend is
#                                  not a divergence (#1041). Read here and nowhere else, for the same reason
#                                  as the two shapes above; `oracle_target` answers the arch or `none`, and
#                                  `oracle_targets` scans a whole test/ glob in ONE awk process (the per-
#                                  fixture loop cost ~3 800 subprocesses and 147 s of self-test time).
#
# A prose header that cites a spec section but states no number is NOT a declaration: `oracle` answers
# `none` and the row stays UNEXPLAINED, which is the honest verdict — the instrument says it cannot tell,
# rather than guessing from the name. `reject_*` in a FILENAME is likewise not a declaration: it is the
# manifest's registration class, and treating a filename as a requirement would let the repository encode a
# workaround as the spec (see test/reject_local_name_two_aggregate_types.al, where the fixture asserts a
# refusal the spec does not ask for).
#
# ## Output
#
#   reject          must be refused at compile time
#   exit:<N>      must run and exit N
#   none            declares nothing — the caller decides what that means, and UNEXPLAINED is usually right

# oracle <path> -> reject | exit:<N> | none
oracle() {
  local f="$1" hdr
  [ -f "$f" ] || { echo none; return; }
  hdr=$(head -n 30 "$f")
  if printf '%s\n' "$hdr" | grep -qiE '^##[[:space:]]*build_reject'; then echo reject; return; fi
  local n
  n=$(printf '%s\n' "$hdr" | grep -iE '^##[[:space:]]*expected' \
        | grep -oiE '(exit|status)[[:space:]]*[:=]?[[:space:]]*[0-9]+' | grep -oE '[0-9]+' | head -1)
  if [ -n "$n" ]; then echo "exit:$n"; else echo none; fi
}

# oracle_explains <path> <exit-code> — true when the fixture declares exactly this exit code. Used by
# xbackend_diff to tell "a backend answered differently, and the file said it would" from "…and nothing
# says why". A `reject` declaration explains a REFUSAL, never an exit number.
# oracle_target <path> — the architecture a fixture declares its asm() body written for, or `none`.
# Header only (first 30 lines), same scope rule as `oracle`. A SECOND, different declaration in the same
# header is an error, not a tie-break: two claims in one file mean the file does not answer the question,
# and silently taking the first (`grep -m1`) would let a fixture both claim and disclaim a backend.
oracle_target() { # path
  local f="$1" a
  [ -f "$f" ] || { echo none; return; }
  a=$(head -n 30 "$f" | grep -oE '^##[[:space:]]*@target\((x86_64|aarch64|riscv64|wasm)\)'         | sed -E 's/.*\((.*)\)/\1/' | sort -u)
  case "$a" in
    "") echo none ;;
    *$'
'*) echo "CONFLICT" >&2; echo none ;;
    *) echo "$a" ;;
  esac
}

# oracle_targets <glob> — path TAB arch, for every declaring fixture, in ONE awk process. Header-scoped
# (FNR<=30), first declaration per file wins, and a conflicting second one is reported to stderr rather
# than resolved silently. FILENAME is printed EXACTLY as the caller spelled it, so a caller that wants
# manifest-relative rows globs relative paths (`test/*.al` from the repository root).
oracle_targets() { # glob...
  awk 'FNR <= 30 && match($0, /^##[[:space:]]*@target\((x86_64|aarch64|riscv64|wasm)\)/) {
         a = substr($0, RSTART, RLENGTH); sub(/.*\(/, "", a); sub(/\)/, "", a)
         if (FILENAME in arch) { if (arch[FILENAME] != a) printf "CONFLICT %s: %s vs %s\n", FILENAME, arch[FILENAME], a > "/dev/stderr"
                                 next }
         arch[FILENAME] = a
       }
       END { for (fn in arch) printf "%s\t%s\n", fn, arch[fn] }' "$@"
  return 0
}

oracle_explains() { # path exit
  local o; o="$(oracle "$1")"
  case "$o" in
    "exit:$2") return 0 ;;
    *) return 1 ;;
  esac
}

# ## The `## expect:` directive (#1126)
#
# The machine-read statement of what the SPECIFICATION requires of a fixture — not of what any backend
# does today. One line per scope, anywhere in the file (the migration appends it at the END, because a
# line inserted above the code moves every `at line N` a diagnostic prints):
#
#   ## expect: run <N>               builds, and the process ends with status N (0..255, as `$?` reads it)
#   ## expect: trap                  builds, and dies by the language's checked trap — status 132 on
#                                    x86_64, 133 on aarch64 and riscv64, 134 on wasm
#   ## expect: accept                a valid program: it builds; no run result is claimed
#   ## expect: reject "<n>" ...      refused at compile time; each quoted needle (zero or more; `\"` and
#                                    `\\` escape) must appear in the diagnostic
#   ## expect(<backend>): <outcome>  the same, for one of x86_64 | aarch64 | riscv64 | wasm only. It
#                                    states a result the spec leaves to the backend (hardware-defined
#                                    `unchecked` division, an `@target` asm body) — never a defect;
#                                    a defect is a known deviation, not an expectation
#   ## spec: <citation>              optional; where the requirement is written (traceability only)
#
# A backend takes its scoped line, else the unscoped one, else the fixture states nothing for it. At
# most one line per scope. A line that starts like a directive and does not parse is reported as
# malformed, never skipped: a typo must not read as "states nothing". "Starts like a directive" is
# EXPECT_TRIGGER, matched against the lower-cased line: any run of `#`, optional blanks, then the word
# `expect` (so `## expect run 4`, `##expect: run 4` and `# Expect: trap` are all malformed, while
# `## Expected exit: 42` — the legacy shape `oracle` reads — is a different word and is not a trigger).
# Every reader of "does this file carry a directive" uses this one pattern.
EXPECT_TRIGGER='^#+[[:space:]]*expect([^a-z0-9_]|$)'
#
# expect_scan <file>... -> one TSV row per directive, in ONE awk process:
#   path  scope  outcome  needles  line
# scope is `*` or a backend; outcome is `run:N`, `trap`, `accept` or `reject`; needles are joined by
# the unit separator \037. A malformed line is the row `path  !  <reason>  <text>  line`.
expect_scan() { # file...
  awk -v US="$(printf '\037')" -v TRIG="$EXPECT_TRIGGER" '
    function bad(why) { printf "%s\t!\t%s\t%s\t%d\n", FILENAME, why, $0, FNR }
    tolower($0) ~ TRIG {
      line = $0
      if (!match(line, /^## expect(\((x86_64|aarch64|riscv64|wasm)\))?: +/)) { bad("not `## expect[(backend)]: <outcome>`"); next }
      head = substr(line, 1, RLENGTH); rest = substr(line, RLENGTH + 1); sub(/[ \t]+$/, "", rest)
      scope = "*"
      if (match(head, /\((x86_64|aarch64|riscv64|wasm)\)/)) scope = substr(head, RSTART + 1, RLENGTH - 2)
      if ((FILENAME SUBSEP scope) in seen) { bad("a second directive for scope " scope); next }
      needles = ""
      if (rest ~ /^run [0-9]+$/) {
        n = substr(rest, 5) + 0
        if (n > 255) { bad("a status is 0..255"); next }
        out = "run:" n
      } else if (rest == "trap" || rest == "accept") {
        out = rest
      } else if (rest ~ /^reject( |$)/) {
        out = "reject"; s = substr(rest, 7); ok = 1
        while (s != "") {
          sub(/^ +/, "", s); if (s == "") break
          if (substr(s, 1, 1) != "\"") { ok = 0; break }
          s = substr(s, 2); nd = ""; closed = 0
          while (s != "") {
            c = substr(s, 1, 1)
            if (c == "\\") { nd = nd substr(s, 2, 1); s = substr(s, 3); continue }
            s = substr(s, 2)
            if (c == "\"") { closed = 1; break }
            nd = nd c
          }
          if (!closed || nd == "" || (s != "" && substr(s, 1, 1) != " ")) { ok = 0; break }
          needles = needles (needles == "" ? "" : US) nd
        }
        if (!ok) { bad("a needle is a non-empty \"…\" string, space separated"); next }
      } else { bad("unknown outcome (run N | trap | accept | reject \"…\")"); next }
      seen[FILENAME SUBSEP scope] = 1
      printf "%s\t%s\t%s\t%s\t%d\n", FILENAME, scope, out, needles, FNR
    }' "$@"
  return 0
}

# fixture_oracle_selftest — planted: the two declared shapes, a prose-only header, a filename that looks
# like a declaration, and the trap that `oracle_explains` must not answer yes for a `reject` fixture.
fixture_oracle_selftest() {
  local d rc=0 o
  d="$(mktemp -d "${TMPDIR:-/tmp}/fixture-oracle.XXXXXX")" || return 2
  printf '## build_reject — a located diagnostic is due\nmain := fn() -> u64 { return 1 }\n' > "$d/r.al"
  printf '## a program that must trap\n## Expected: TRAP (SIGILL, exit 132)\nmain := fn() -> u64 { return 1 }\n' > "$d/t.al"
  printf '## cites Declarations §5 and nothing else\nmain := fn() -> u64 { return 1 }\n' > "$d/p.al"
  printf 'main := fn() -> u64 { return 1 }\n' > "$d/reject_by_name_only.al"
  chk() { if [ "$2" = "$3" ]; then echo "  ok   $1"; else echo "  FAIL $1 — got '$2', want '$3'"; rc=1; fi; }
  o="$(oracle "$d/r.al")";    chk "build_reject is read as a refusal"        "$o" "reject"
  o="$(oracle "$d/t.al")";    chk "a declared exit is read as exit:132"      "$o" "exit:132"
  o="$(oracle "$d/p.al")";    chk "prose without a number declares nothing"   "$o" "none"
  o="$(oracle "$d/reject_by_name_only.al")"; chk "a reject_* FILENAME is not a declaration" "$o" "none"
  oracle_explains "$d/t.al" 132; chk "the declared exit is explained"          "$?" "0"
  oracle_explains "$d/t.al" 42;  chk "an undeclared exit is NOT explained"     "$?" "1"
  oracle_explains "$d/r.al" 1;   chk "a build_reject fixture explains no exit number" "$?" "1"
  oracle_explains "$d/absent.al" 0; chk "a missing file explains nothing"      "$?" "1"
  rm -rf "$d"
  [ "$rc" = 0 ] && echo "fixture oracle self-test: 8 checks, 0 failed" \
               || echo "fixture oracle self-test: FAILED"
  return $rc
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  if [ "${1:-}" = "--self-test" ]; then
    fixture_oracle_selftest
    exit $?
  fi
  echo "usage: fixture_oracle.sh --self-test" >&2; exit 2
fi
