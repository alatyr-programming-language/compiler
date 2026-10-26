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
# workaround as the spec. `test/reject_local_name_two_aggregate_types.al` is the case that proves the
# rule: its NAME says refuse, the spec (§6.1) says valid, and until the slice-9 flip it carried only
# prose — so `oracle` answered `none` and the row stayed UNEXPLAINED rather than letting the name
# invent a requirement. It now declares `## Expected exit: 109`, the value three backends agree on.
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
