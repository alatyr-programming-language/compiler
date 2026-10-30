#!/usr/bin/env bash
# PILOTS stage (#1125): build the pilot packages under pilots/ with the tree compiler and run them.
#
# A pilot is an ordinary package written the way a user would write one, so it reaches shapes the
# corpus does not. This stage builds each one from a scratch copy under target/pilots/ (the tree is
# never written to) and checks two things per pilot:
#
#   library  `alatyr test` exits 0 and prints one `: ok` line for every `@test` in its sources. The
#            count is checked because the runner stops at the first failure without a summary
#            (#1145), so rc 0 alone does not show that every test ran.
#   program  `alatyr build` exits 0, and the built program exits with the pilot's stated value
#            (0 for json-consumer: its exit code is the number of the first failed check).
#   cli      `alatyr build` exits 0, and every case under the pilot's cases/ runs as stated:
#            <name>.args (one argument per line), <name>.stdin (optional; /dev/null otherwise),
#            <name>.out (the exact standard output) and <name>.rc (the exit status). A case with a
#            nonzero status must also write something to standard error. Cases run in the pilot's
#            directory, so an argument may name a data file under cases/.
#
# Usage (inside `nix develop`):
#   bash scripts/pilots.sh                 # ALATYR defaults to target/debug/alatyr
#   bash scripts/pilots.sh --self-test     # proves the stage fails on a planted wrong check
#
# The last line is `pilots: libraries=<n> tests=<n> programs=<n> cases=<n> failed=<n>`. The exit status is
# 1 when anything failed or nothing ran: a stage that checked nothing is not green.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ALATYR="${ALATYR:-$ROOT/target/debug/alatyr}"
case "$ALATYR" in /*) ;; *) ALATYR="$ROOT/$ALATYR" ;; esac
TIMEOUT="${ALATYR_PILOT_TIMEOUT:-60}"

# The pilots and what they are. `lib <dir>` runs `alatyr test`; `prog <dir> <rc>` builds and runs.
# A consumer comes after the library it depends on, so a library failure is reported first.
PILOTS=(
  "lib json"
  "prog json-consumer 0"
  "lib wc"
  "cli wc"
)

# The artifact path from the compiler's `built: … artifact=<path>` line. The default name is not
# the manifest binding yet (#1143), so the path is read rather than assumed.
artifact_of() {
  sed -nE 's/^built: .* artifact=(.*)$/\1/p' "$1" | tail -1
}

# run_pilots <pilots-copy-dir> — checks every row of PILOTS inside that copy; prints one line per
# row and the summary; returns 0 only when every row passed and at least one ran.
run_pilots() {
  local dir="$1" libs=0 tests=0 progs=0 cases=0 failed=0 row kind name want log rc due got art
  local c cn in args
  for row in "${PILOTS[@]}"; do
    read -r kind name want <<<"$row"
    log="$dir/$name.log"
    case "$kind" in
      lib)
        libs=$((libs + 1))
        due="$(cat "$dir/$name"/src/*.al | grep -cE '^[[:space:]]*@test\(')"
        (cd "$dir/$name" && timeout "$TIMEOUT" "$ALATYR" test) > "$log" 2>&1
        rc=$?
        got="$(grep -cE ': ok$' "$log")"
        tests=$((tests + got))
        if [ "$rc" = 0 ] && [ "$got" = "$due" ] && [ "$due" != 0 ]; then
          echo "  ok    $name: alatyr test rc=0, $got/$due tests ok"
        else
          echo "  FAIL  $name: alatyr test rc=$rc, $got/$due tests ok (log: $log)"
          sed 's/^/          /' "$log" | tail -5
          failed=$((failed + 1))
        fi
        ;;
      prog)
        progs=$((progs + 1))
        (cd "$dir/$name" && timeout "$TIMEOUT" "$ALATYR" build) > "$log" 2>&1
        rc=$?
        art="$(artifact_of "$log")"
        if [ "$rc" != 0 ] || [ -z "$art" ] || [ ! -x "$art" ]; then
          echo "  FAIL  $name: alatyr build rc=$rc, artifact '${art:-none}' (log: $log)"
          sed 's/^/          /' "$log" | tail -5
          failed=$((failed + 1))
          continue
        fi
        (cd "$dir/$name" && timeout "$TIMEOUT" "$art") >> "$log" 2>&1
        rc=$?
        if [ "$rc" = "$want" ]; then
          echo "  ok    $name: built, ran to $rc"
        else
          echo "  FAIL  $name: built, ran to $rc where $want is due (log: $log)"
          failed=$((failed + 1))
        fi
        ;;
      cli)
        progs=$((progs + 1))
        (cd "$dir/$name" && timeout "$TIMEOUT" "$ALATYR" build) > "$log" 2>&1
        rc=$?
        art="$(artifact_of "$log")"
        if [ "$rc" != 0 ] || [ -z "$art" ] || [ ! -x "$art" ]; then
          echo "  FAIL  $name: alatyr build rc=$rc, artifact '${art:-none}' (log: $log)"
          sed 's/^/          /' "$log" | tail -5
          failed=$((failed + 1))
          continue
        fi
        due=0
        got=0
        for c in "$dir/$name"/cases/*.rc; do
          [ -e "$c" ] || continue
          due=$((due + 1))
          cn="$(basename "$c" .rc)"
          in="/dev/null"
          [ -e "$dir/$name/cases/$cn.stdin" ] && in="$dir/$name/cases/$cn.stdin"
          args=()
          [ -s "$dir/$name/cases/$cn.args" ] && mapfile -t args < "$dir/$name/cases/$cn.args"
          (cd "$dir/$name" && timeout "$TIMEOUT" "$art" "${args[@]}" < "$in" \
            > "$dir/$name.$cn.stdout" 2> "$dir/$name.$cn.stderr")
          rc=$?
          want="$(cat "$c")"
          if [ "$rc" != "$want" ]; then
            echo "  FAIL  $name/$cn: exited $rc where $want is due"
            failed=$((failed + 1))
          elif ! cmp -s "$dir/$name.$cn.stdout" "$dir/$name/cases/$cn.out"; then
            echo "  FAIL  $name/$cn: standard output differs from cases/$cn.out"
            diff "$dir/$name/cases/$cn.out" "$dir/$name.$cn.stdout" | head -6 | sed 's/^/          /'
            failed=$((failed + 1))
          elif [ "$rc" != 0 ] && [ ! -s "$dir/$name.$cn.stderr" ]; then
            echo "  FAIL  $name/$cn: exited $rc with nothing on standard error"
            failed=$((failed + 1))
          else
            got=$((got + 1))
            cases=$((cases + 1))
          fi
        done
        if [ "$due" = 0 ]; then
          echo "  FAIL  $name: no cases under cases/ — a CLI pilot that runs nothing is not green"
          failed=$((failed + 1))
        elif [ "$got" = "$due" ]; then
          echo "  ok    $name: built; $got/$due command-line cases as stated"
        else
          echo "  FAIL  $name: built; $got/$due command-line cases as stated (failures above)"
        fi
        ;;
      *)
        echo "  FAIL  unknown pilot kind '$kind' in row '$row'"
        failed=$((failed + 1))
        ;;
    esac
  done
  echo "pilots: libraries=$libs tests=$tests programs=$progs cases=$cases failed=$failed"
  [ "$failed" = 0 ] && [ $((libs + progs)) != 0 ]
}

# A fresh copy of pilots/ under target/, so builds never write into the tree.
fresh_copy() {
  local dir="$1"
  rm -rf "$dir"
  mkdir -p "$dir"
  cp -R "$ROOT/pilots/." "$dir/"
  find "$dir" -type d -name target -prune -exec rm -rf {} +
}

if [ ! -x "$ALATYR" ]; then
  echo "pilots: FAIL — no compiler at $ALATYR"
  exit 1
fi

if [ "${1:-}" = "--self-test" ]; then
  # The planted defect: consumer check 3 expects a value its document does not render to, so the
  # consumer must exit with exactly 3 (not a crash, not another check) and the stage must fail.
  D="$ROOT/target/pilots-self-test"
  fresh_copy "$D"
  sed -i.bak 's/round_trip(a, "true", "true")/round_trip(a, "true", "false")/' "$D/json-consumer/src/main.al"
  rm -f "$D/json-consumer/src/main.al.bak"
  if ! grep -q 'round_trip(a, "true", "false")' "$D/json-consumer/src/main.al"; then
    echo "pilots self-test: FAIL — the planted check was not found to plant"
    exit 1
  fi
  if run_pilots "$D" > "$D/run.log" 2>&1; then
    echo "pilots self-test: FAIL — the stage passed with a planted wrong check"
    cat "$D/run.log"
    exit 1
  fi
  if ! grep -qE 'FAIL  json-consumer: built, ran to 3 where 0 is due' "$D/run.log"; then
    echo "pilots self-test: FAIL — the stage failed, but not with the planted check's exit 3"
    cat "$D/run.log"
    exit 1
  fi
  echo "pilots self-test: ok (a planted wrong check fails the stage)"
  rm -rf "$D"
  exit 0
fi

D="$ROOT/target/pilots"
fresh_copy "$D"
run_pilots "$D"
