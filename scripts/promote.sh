#!/usr/bin/env bash
# scripts/promote.sh — a seed promotion, scripted (#1129).
#
# ## Why
#
# A promotion is the AGENTS.md "Reproducibility" procedure: bump the version FIRST, build Stage1 (the
# committed seed builds the tree), Stage2 (Stage1 builds it), Stage3 (Stage2 builds it), require the
# three to emit the same GAS once the `.L<N>` and `.Lra<N>_<k>` labels are normalized and Stage2 ==
# Stage3 in the binary, read the normalized seed-to-Stage1 delta, copy STAGE2 over seed/alatyr, append
# the evidence to seed/HISTORY.md, re-run scripts/fixpoint.sh on the promoted tree, and commit the
# whole thing atomically. It was done by hand, eleven times in two weeks and then not at all: five
# `reseed-owed` issues waited, and the hand-kept CURRENT SEED block of seed/VERSION still says
# "Promoted: 2026-10-15" and the 0.2.16 GAS count after the 0.2.17 promotion of 2026-10-24. Every
# mechanical step is here; the two judgements stay with a person: the one-sentence reading of the
# delta, and the WHY of the promotion.
#
# ## Usage (native x86_64 Linux, inside `nix develop`; the seed is a static x86_64 binary)
#
#   scripts/promote.sh prepare <new-version> [--worktree DIR] [--base REV]
#       A derived worktree (default: target/promote-<new-version> of this checkout, detached at REV,
#       default HEAD). There: the bump (package.al, seed/VERSION current-seed-version,
#       scripts/package_cli_test.sh), Stage1 -> Stage2 -> Stage3, the convergence checks, the
#       normalized seed->Stage1 delta (DIR/target/promote/delta.diff) and its summary (delta.txt),
#       Stage2 copied over seed/alatyr, the CURRENT SEED block brought to the promoted seed, and
#       scripts/fixpoint.sh on the promoted tree, which must reach its TOOL-1 FIXPOINT line. It writes
#       the seed/HISTORY.md entry, a CHANGELOG.md section and DIR/target/promote/COMMIT_MSG with every
#       measured fact filled in and the judgements marked PROMOTE-OWED. It prints the delta summary
#       and stops.
#   scripts/promote.sh commit DIR
#       Refuses while a PROMOTE-OWED marker is left, or when the changed files are not exactly the
#       atomic set; else one commit from COMMIT_MSG. Never pushes.
#   scripts/promote.sh gate DIR [--local | --push]
#       The full gate on the committed promotion: --local runs scripts/full.sh in DIR (the integrator's
#       machine; a lane never runs it on the shared box); --push (default) pushes the exact commit to
#       gate/promote-<version> for .github/workflows/gate.yml. Never pushes main.
#   scripts/promote.sh due [--owed N] [--seed-rows N] [--last YYYY-MM-DD] [--today YYYY-MM-DD]
#       Exit 0 when a promotion is due, 1 when not, 2 when it cannot tell. The cadence (#1129): a week
#       since the last promotion, or an open `reseed-owed` issue, or a live `seed` row in
#       scripts/seed_forms.tsv. Each input defaults to the tree and `gh`; the options replace them.
#   scripts/promote.sh --self-test
#       Planted inputs for every decision above that needs no seed: the version order, the label
#       normalization, the convergence verdict, the bump, the owed-marker and atomic-set refusals, and
#       the cadence.
set -u
export LC_ALL=C
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OWED=PROMOTE-OWED
## the atomic set (AGENTS.md "Reproducibility": bump, package_cli_test.sh, seed, current-seed-sha256,
## the appended entry, CHANGELOG.md)
ATOMIC="CHANGELOG.md package.al scripts/package_cli_test.sh seed/HISTORY.md seed/VERSION seed/alatyr"

die() { echo "promote: $*" >&2; exit 2; }

## ---- the deciders (pure; the self-test drives them) ---------------------------------------------------

## version_after OLD NEW -> 0 when NEW is a strictly greater MAJOR.MINOR.PATCH than OLD
version_after() {
  awk -v a="$1" -v b="$2" 'BEGIN {
    if (a !~ /^[0-9]+\.[0-9]+\.[0-9]+$/ || b !~ /^[0-9]+\.[0-9]+\.[0-9]+$/) exit 2
    split(a, x, "."); split(b, y, ".")
    for (i = 1; i <= 3; i++) { if (y[i] + 0 > x[i] + 0) exit 0; if (y[i] + 0 < x[i] + 0) exit 1 }
    exit 1 }'
}

## normalize_gas < GAS -> GAS with the two label families renumbered away (`.Lra` first: it is also a `.L`)
normalize_gas() { sed -E -e 's/\.Lra[0-9]+_[0-9]+/.LraN_K/g' -e 's/\.L[0-9]+/.LN/g'; }

## converged G1 G2 G3 B2 B3 -> 0 when Stage1 == Stage2 == Stage3 in normalized GAS and Stage2 == Stage3
## in the binary; else 1, naming what differs. Stage1's BINARY is not compared: the stale seed assembled
## it, so it differs by construction (seed/VERSION, "Stage2, and not all three binaries").
converged() {
  local g1="$1" g2="$2" g3="$3" b2="$4" b3="$5" bad=0
  [ -s "$g1" ] || { echo "  Stage1 emitted no GAS"; return 1; }
  cmp -s <(normalize_gas < "$g1") <(normalize_gas < "$g2") || { echo "  Stage1 and Stage2 GAS differ (normalized)"; bad=1; }
  cmp -s <(normalize_gas < "$g2") <(normalize_gas < "$g3") || { echo "  Stage2 and Stage3 GAS differ (normalized)"; bad=1; }
  cmp -s "$b2" "$b3" || { echo "  Stage2 and Stage3 binaries differ"; bad=1; }
  return "$bad"
}

## bump DIR NEW -> rewrite the three version sites of the tree at DIR; 2 when a site is not found once
bump() {
  local d="$1" new="$2" n
  n="$(grep -cE '^[[:space:]]*version[[:space:]]*=[[:space:]]*"[^"]*"' "$d/package.al")"
  [ "$n" -ge 1 ] || { echo "promote: package.al has no version field" >&2; return 2; }
  awk -v v="$new" '!done && /^[[:space:]]*version[[:space:]]*=[[:space:]]*"[^"]*"/ { sub(/"[^"]*"/, "\"" v "\""); done = 1 } { print }' \
    "$d/package.al" > "$d/package.al.new" && mv "$d/package.al.new" "$d/package.al"
  n="$(grep -c '^current-seed-version: ' "$d/seed/VERSION")"
  [ "$n" = 1 ] || { echo "promote: seed/VERSION has $n current-seed-version lines, want 1" >&2; return 2; }
  sed -i.bak -E "s/^current-seed-version: .*/current-seed-version: $new/" "$d/seed/VERSION" && rm -f "$d/seed/VERSION.bak"
  n="$(grep -cE "printf 'alatyr [0-9]+\.[0-9]+\.[0-9]+, spec " "$d/scripts/package_cli_test.sh")"
  [ "$n" = 1 ] || { echo "promote: scripts/package_cli_test.sh has $n expected --version lines, want 1" >&2; return 2; }
  sed -i.bak -E "s/printf 'alatyr [0-9]+\.[0-9]+\.[0-9]+, spec /printf 'alatyr $new, spec /" "$d/scripts/package_cli_test.sh" \
    && rm -f "$d/scripts/package_cli_test.sh.bak"
}

## owed_left DIR -> 0 (and the places) when a PROMOTE-OWED marker is still in the tree or the message
owed_left() { grep -n "$OWED" "$1/seed/HISTORY.md" "$1/CHANGELOG.md" "$1/target/promote/COMMIT_MSG" 2>/dev/null; }

## atomic_set_ok CHANGED-FILES -> 0 when the changed paths are exactly $ATOMIC
atomic_set_ok() {
  local want got
  want="$(printf '%s\n' $ATOMIC | sort)"; got="$(printf '%s\n' "$1" | grep -v '^$' | sort -u)"
  [ "$want" = "$got" ] && return 0
  echo "  changed:  $(printf '%s' "$got" | tr '\n' ' ')"; echo "  required: $(printf '%s' "$want" | tr '\n' ' ')"
  return 1
}

## is_due OWED SEEDROWS LAST TODAY -> 0 due (and why), 1 not due, 2 unknown
is_due() {
  local owed="$1" rows="$2" last="$3" today="$4" days
  case "$owed" in *[!0-9]*|'') echo "  cannot tell: owed='$owed'"; return 2 ;; esac
  case "$rows" in *[!0-9]*|'') echo "  cannot tell: seed-rows='$rows'"; return 2 ;; esac
  days="$(( ( $(date -u -d "$today" +%s 2>/dev/null || date -u -j -f %F "$today" +%s) - $(date -u -d "$last" +%s 2>/dev/null || date -u -j -f %F "$last" +%s) ) / 86400 ))" \
    || { echo "  cannot tell: dates '$last' '$today'"; return 2; }
  if [ "$owed" -gt 0 ]; then echo "  due: $owed open reseed-owed issue(s)"; return 0; fi
  if [ "$rows" -gt 0 ]; then echo "  due: $rows live seed row(s) in scripts/seed_forms.tsv"; return 0; fi
  if [ "$days" -ge 7 ]; then echo "  due: $days days since the last promotion ($last)"; return 0; fi
  echo "  not due: no reseed-owed issue, no live seed row, $days day(s) since $last"; return 1
}

## ---- the subcommands ------------------------------------------------------------------------------------

field() { sed -n "s/^$2: //p" "$1" | head -n 1; }

cmd_prepare() {
  local new="" wt="" base=HEAD
  while [ $# -gt 0 ]; do
    case "$1" in
      --worktree) wt="${2:-}"; shift 2 ;;
      --base) base="${2:-}"; shift 2 ;;
      -*) die "prepare: unknown option $1" ;;
      *) new="$1"; shift ;;
    esac
  done
  [ -n "$new" ] || die "prepare needs <new-version>"
  [ "$(uname -s)/$(uname -m)" = Linux/x86_64 ] || die "the seed is a static x86_64 Linux binary: run on native x86_64 (emulation is not a gate)"
  [ -n "$wt" ] || wt="$ROOT/target/promote-$new"
  [ ! -e "$wt" ] || die "$wt exists; remove it (git worktree remove) or pass --worktree"
  local old; old="$(field "$ROOT/seed/VERSION" current-seed-version)"
  version_after "$old" "$new" || die "$new is not a version after the current seed's $old"
  git -C "$ROOT" worktree add -q --detach "$wt" "$base" || die "git worktree add $wt $base failed"
  local P="$wt/target/promote"; mkdir -p "$P"
  cd "$wt" || die "cd $wt"
  ulimit -c 0
  local seed_sha_old; seed_sha_old="$(sha256sum seed/alatyr | cut -d' ' -f1)"
  echo "promote: $old -> $new in $wt (base $(git rev-parse --short HEAD))"
  bump "$wt" "$new" || die "the bump failed"
  echo "promote: bumped package.al, seed/VERSION, scripts/package_cli_test.sh"

  ## the stages: each compiler builds the tree into target/debug/alatyr, kept as target/stageN. Exactly
  ## where fixpoint.sh keeps them: a compiler finds lib/ relative to itself (AGENTS.md), and one copied
  ## to target/promote/ answered "cannot open source file" for every input (measured on omen).
  ## the manifest by its ABSOLUTE path, as fixpoint.sh passes it: a relative one is refused by the tree
  ## compiler's emit form ("cannot open source file", measured on omen)
  local cc=./seed/alatyr n M="$wt/package.al"
  ./seed/alatyr "$M" > "$P/gas_seed.s" 2>/dev/null; [ -s "$P/gas_seed.s" ] || die "the seed did not emit the tree's GAS"
  for n in 1 2 3; do
    rm -f target/debug/alatyr
    "$cc" build "$M" > "$P/build$n.log" 2>&1 || die "Stage$n build failed (see $P/build$n.log)"
    [ -x target/debug/alatyr ] || die "Stage$n: no target/debug/alatyr"
    cp target/debug/alatyr "$wt/target/stage$n"
    "$wt/target/stage$n" "$M" > "$P/gas$n.s" 2>/dev/null; [ -s "$P/gas$n.s" ] || die "Stage$n did not emit the tree's GAS"
    case "$("$wt/target/stage$n" --version)" in "alatyr $new, "*) ;; *) die "Stage$n answers '$("$wt/target/stage$n" --version)', not alatyr $new (#586: bump first)" ;; esac
    cc="$wt/target/stage$n"
  done
  converged "$P/gas1.s" "$P/gas2.s" "$P/gas3.s" "$wt/target/stage2" "$wt/target/stage3" || die "no convergence (above); nothing is promoted"
  printf 'main := fn() -> u64 { return 7 + 35 }\n' > "$P/smoke.al"
  "$wt/target/stage2" -o "$P/smoke" "$P/smoke.al" > /dev/null 2>&1; "$P/smoke"; local smoke=$?
  [ "$smoke" = 42 ] || die "Stage2 smoke answered $smoke, want 42"

  ## the delta, normalized, and a census of its line shapes (numbers folded) for the one-sentence reading
  diff -U0 <(normalize_gas < "$P/gas_seed.s") <(normalize_gas < "$P/gas1.s") > "$P/delta.diff"
  local hunks add del
  hunks="$(grep -c '^@@' "$P/delta.diff")"; add="$(grep -c '^+[^+]' "$P/delta.diff")"; del="$(grep -c '^-[^-]' "$P/delta.diff")"
  {
    echo "seed -> Stage1 delta, normalized (.L<N>, .Lra<N>_<k>): $hunks hunks, $add added, $del removed"
    echo "line shapes (digits folded), most frequent first:"
    grep -E '^[+-][^+-]' "$P/delta.diff" | sed -E 's/[0-9]+/N/g' | sort | uniq -c | sort -rn | head -n 20
  } > "$P/delta.txt"

  ## promote Stage2 and bring the CURRENT SEED block to it
  local gas_lines gas_sha bin_sha bin_size today
  gas_lines="$(wc -l < "$P/gas2.s" | tr -d ' ')"; gas_sha="$(sha256sum "$P/gas2.s" | cut -d' ' -f1)"
  bin_sha="$(sha256sum "$wt/target/stage2" | cut -d' ' -f1)"; bin_size="$(wc -c < "$wt/target/stage2" | tr -d ' ')"
  today="$(date -u +%F)"
  cp "$wt/target/stage2" seed/alatyr
  sed -i -E -e "s/^current-seed-sha256: .*/current-seed-sha256: $bin_sha/" \
    -e "s/^# Promoted: .*/# Promoted:      $today (see the last entry in seed\/HISTORY.md)/" \
    -e "s/^# GAS at promotion: .*/# GAS at promotion: $gas_lines lines/" \
    -e "s/^# GAS SHA-256: .*/# GAS SHA-256:   $gas_sha/" seed/VERSION

  ## the proof: fixpoint.sh on the promoted tree
  bash scripts/fixpoint.sh > "$P/fixpoint.log" 2>&1
  grep -q 'TOOL-1 FIXPOINT' "$P/fixpoint.log" || { tail -20 "$P/fixpoint.log" >&2; die "fixpoint.sh on the promoted tree did not converge (see $P/fixpoint.log)"; }
  local spec; spec="$("$wt/target/stage2" --version | sed -E 's/^alatyr [^,]*, //')"

  ## the record: measured facts filled in, the two judgements owed
  local entry="$P/history_entry"
  {
    echo "# ---------------------------------------------------------------------------------------------"
    echo "# $old -> $new   promoted $today   seed/alatyr := Stage2"
    echo "#"
    echo "# WHY: $OWED — the change whose emission the seed must carry, with its issue."
    echo "#"
    echo "# THE DELTA (normalized .L<N> / .Lra<N>_<k>): $hunks hunks, $add added, $del removed. One sentence:"
    echo "# $OWED — read target/promote/delta.txt and delta.diff; a delta that resists one sentence is the"
    echo "# signal to STOP."
    echo "#"
    echo "# CONVERGENCE (bump first; scripts/promote.sh on native x86_64):"
    echo "# Stage1 == Stage2 == Stage3 GAS byte-identical (normalized) at $gas_lines lines."
    echo "# GAS SHA-256 (Stage2): $gas_sha."
    echo "# Stage2 == Stage3 BINARY SHA-256:"
    echo "# $bin_sha ($bin_size B)."
    echo "# All three answer \`alatyr $new, $spec\`. smoke = $smoke."
    echo "# Superseded seed ($old) SHA-256:"
    echo "# $seed_sha_old."
    echo "#"
    echo "# scripts/fixpoint.sh was re-run on the promoted tree: $(grep 'TOOL-1 FIXPOINT' "$P/fixpoint.log" | head -1)"
    echo "# The full gate is \`scripts/promote.sh gate\` on the committed promotion; its run is named in the PR."
  } > "$entry"
  ## HISTORY.md's entries sit inside one fenced block: insert before its closing fence
  awk -v f="$entry" '{ L[NR] = $0 } END { for (i = NR; i > 0; i--) if (L[i] == "```") { last = i; break }
    for (i = 1; i <= NR; i++) { if (i == last) { while ((getline x < f) > 0) print x; print "" } print L[i] } }' \
    seed/HISTORY.md > "$P/HISTORY.md" && cp "$P/HISTORY.md" seed/HISTORY.md
  awk -v v="$new" -v d="$today" -v o="$OWED" '!done && /^## [0-9]+\.[0-9]+\.[0-9]+ / {
      print "## " v " — " d; print ""; print "- " o " — what the promotion carries, and the version class (CHANGELOG.md \"Versioning policy\")."; print ""; done = 1 }
    { print }' CHANGELOG.md > "$P/CHANGELOG.md" && cp "$P/CHANGELOG.md" CHANGELOG.md
  {
    echo "chore(seed): promote $old -> $new — $OWED one line on what the seed now carries"
    echo
    echo "$OWED: why (the issue whose emission the seed must carry)."
    echo
    echo "Bump came FIRST (package.al, seed/VERSION current-seed-version, scripts/package_cli_test.sh),"
    echo "then Stage1 ($old seed builds the tree) -> Stage2 -> Stage3 on native x86_64 by scripts/promote.sh."
    echo "Stage1 == Stage2 == Stage3 GAS (normalized) at $gas_lines lines (sha256 $gas_sha);"
    echo "Stage2 == Stage3 binary ($bin_sha, $bin_size B); all three answer"
    echo "\`alatyr $new, $spec\`; smoke = $smoke. Superseded seed $seed_sha_old."
    echo
    echo "Seed->Stage1 delta, normalized: $hunks hunks, $add added, $del removed. $OWED: the one sentence."
    echo
    echo "scripts/fixpoint.sh on the promoted tree: TOOL-1 FIXPOINT."
  } > "$P/COMMIT_MSG"
  echo
  cat "$P/delta.txt"
  echo
  echo "promote: PREPARED in $wt — nothing is committed or pushed."
  echo "  Read target/promote/delta.txt (and delta.diff) and replace every $OWED in seed/HISTORY.md,"
  echo "  CHANGELOG.md and target/promote/COMMIT_MSG; then: scripts/promote.sh commit $wt"
}

cmd_commit() {
  local wt="${1:-}"; [ -d "$wt/.git" ] || [ -f "$wt/.git" ] || die "commit needs the prepared worktree"
  cd "$wt" || die "cd $wt"
  if owed_left "$wt"; then die "the lines above still say $OWED: the delta sentence and the why are a person's"; fi
  atomic_set_ok "$(git status --porcelain --untracked-files=all | grep -v ' target/' | cut -c4-)" \
    || die "the changed files are not the atomic promotion set (AGENTS.md, Reproducibility)"
  # shellcheck source=attribution.sh
  . "$ROOT/scripts/attribution.sh"
  attribution_trailer_check "the promotion message" "$(cat target/promote/COMMIT_MSG)" || die "remove the trailer from target/promote/COMMIT_MSG"
  git add -- $ATOMIC && git commit -q -F target/promote/COMMIT_MSG || die "git commit failed"
  echo "promote: COMMITTED $(git rev-parse HEAD) in $wt — not pushed. Next: scripts/promote.sh gate $wt"
}

cmd_gate() {
  local wt="${1:-}" how="${2:---push}" v
  [ -d "$wt" ] || die "gate needs the prepared worktree"
  cd "$wt" || die "cd $wt"
  [ -z "$(git status --porcelain --untracked-files=no)" ] || die "uncommitted changes: commit first, the gate verdict is for an exact commit"
  v="$(field seed/VERSION current-seed-version)"
  case "$how" in
    --local) bash scripts/full.sh ;;
    --push)  git push origin "HEAD:refs/heads/gate/promote-$v" && echo "promote: pushed $(git rev-parse HEAD) to gate/promote-$v; the verdict is its gate.log" ;;
    *) die "gate: --local or --push" ;;
  esac
}

cmd_due() {
  local owed="" rows="" last="" today; today="$(date -u +%F)"
  while [ $# -gt 0 ]; do
    case "$1" in
      --owed) owed="${2:-}"; shift 2 ;; --seed-rows) rows="${2:-}"; shift 2 ;;
      --last) last="${2:-}"; shift 2 ;; --today) today="${2:-}"; shift 2 ;;
      *) die "due: unknown option $1" ;;
    esac
  done
  [ -n "$owed" ] || owed="$(gh issue list --state open --label reseed-owed --limit 500 --json number --jq length 2>/dev/null)" || owed=""
  [ -n "$rows" ] || rows="$(awk -F'\t' '$0 !~ /^#/ && NF >= 2 && $2 == "seed"' "$ROOT/scripts/seed_forms.tsv" | grep -c '')"
  [ -n "$last" ] || last="$(git -C "$ROOT" log -1 --format=%cs -- seed/alatyr)"
  is_due "$owed" "$rows" "$last" "$today"
}

self_test() {
  local d rc=0 n=0 got
  mkdir -p "$ROOT/target" && d="$(mktemp -d "$ROOT/target/promote-selftest.XXXXXX")" || return 2
  chk() { n=$((n + 1)); if [ "$2" = "$3" ]; then echo "  ok   $1"; else echo "  FAIL $1 — got [$2], want [$3]"; rc=1; fi; }
  version_after 0.2.17 0.2.18; got=$?; version_after 0.2.17 0.3.0; got="$got$?"; version_after 0.2.17 1.0.0; got="$got$?"
  chk "a later patch, minor or major is after"                     "$got" "000"
  version_after 0.2.17 0.2.17; got=$?; version_after 0.2.17 0.2.9; got="$got$?"; version_after 0.10.0 0.9.9; got="$got$?"
  chk "the same, an earlier, and a numerically earlier version are not (no string order)" "$got" "111"
  version_after 0.2.17 v0.2.18; chk "a malformed version is refused, not ordered" "$?" "2"
  got="$(printf '.L12:\n\tjmp .L7\n.Lra3_14:\n\tcall .Lra10_2\n\tmovq $123, %%rax\n' | normalize_gas | tr '\n' '|')"
  chk "normalization folds both label families and leaves other numbers" "$got" ".LN:|	jmp .LN|.LraN_K:|	call .LraN_K|	movq \$123, %rax|"
  printf 'a\n.L1:\n' > "$d/g1"; printf 'a\n.L9:\n' > "$d/g2"; printf 'a\n.L4:\n' > "$d/g3"; printf 'B' > "$d/b2"; printf 'B' > "$d/b3"
  converged "$d/g1" "$d/g2" "$d/g3" "$d/b2" "$d/b3" > /dev/null; chk "converged: the same GAS up to labels and the same Stage2/3 binary" "$?" "0"
  printf 'b\n.L1:\n' > "$d/g3"; got="$(converged "$d/g1" "$d/g2" "$d/g3" "$d/b2" "$d/b3")"; chk "Stage3 GAS that differs beyond labels is no convergence" "$?:$got" "1:  Stage2 and Stage3 GAS differ (normalized)"
  cp "$d/g2" "$d/g3"; printf 'C' > "$d/b3"; converged "$d/g1" "$d/g2" "$d/g3" "$d/b2" "$d/b3" > /dev/null; chk "a Stage2/Stage3 binary difference is no convergence" "$?" "1"
  : > "$d/g0"; converged "$d/g0" "$d/g0" "$d/g0" "$d/b2" "$d/b2" > /dev/null; chk "an empty Stage1 GAS is no convergence, not a match of nothing" "$?" "1"
  mkdir -p "$d/t/seed" "$d/t/scripts"
  printf 'pkg := package {\n  name = "alatyr"\n  version = "0.2.17"\n}\ndep := { version = "0.1.0" }\n' > "$d/t/package.al"
  printf '# head\ncurrent-seed-sha256: abc\ncurrent-seed-version: 0.2.17\n' > "$d/t/seed/VERSION"
  printf "  printf 'alatyr 0.2.17, spec 1.6.0 (x)\\\\n' >\"\$want\"\n" > "$d/t/scripts/package_cli_test.sh"
  bump "$d/t" 0.2.18; got="$?:$(grep -c '"0.2.18"' "$d/t/package.al"):$(grep -c '"0.1.0"' "$d/t/package.al"):$(field "$d/t/seed/VERSION" current-seed-version):$(grep -c "alatyr 0.2.18, spec 1.6.0" "$d/t/scripts/package_cli_test.sh")"
  chk "the bump moves the first package version, the CURRENT SEED line and the --version line, nothing else" "$got" "0:1:1:0.2.18:1"
  printf "  printf 'alatyr 0.2.18, spec 1.6.0\\\\n'\n  printf 'alatyr 0.2.18, spec 1.6.0\\\\n'\n" > "$d/t/scripts/package_cli_test.sh"
  bump "$d/t" 0.2.19 2> /dev/null; chk "two expected --version lines are refused, not both rewritten" "$?" "2"
  mkdir -p "$d/w/seed" "$d/w/target/promote"; printf 'ok\n' > "$d/w/seed/HISTORY.md"; printf 'ok\n' > "$d/w/CHANGELOG.md"; printf 'msg\n' > "$d/w/target/promote/COMMIT_MSG"
  owed_left "$d/w" > /dev/null; chk "no marker left: nothing owed" "$?" "1"
  printf "# $OWED x\n" >> "$d/w/seed/HISTORY.md"; owed_left "$d/w" > /dev/null; chk "a marker left in the entry is owed" "$?" "0"
  atomic_set_ok "$(printf '%s\n' $ATOMIC)" > /dev/null; chk "exactly the atomic set is accepted" "$?" "0"
  atomic_set_ok "$(printf '%s\n' $ATOMIC src/cli.al)" > /dev/null; chk "a source file in the promotion commit is refused" "$?" "1"
  atomic_set_ok "$(printf '%s\n' $ATOMIC | grep -v CHANGELOG)" > /dev/null; chk "a promotion without its CHANGELOG entry is refused" "$?" "1"
  is_due 1 0 2026-10-29 2026-10-30 > /dev/null; got=$?; is_due 0 2 2026-10-29 2026-10-30 > /dev/null; got="$got$?"; is_due 0 0 2026-10-23 2026-10-30 > /dev/null; got="$got$?"
  chk "due on an owed issue, on a live seed row, and after a week" "$got" "000"
  is_due 0 0 2026-10-24 2026-10-30 > /dev/null; chk "not due: nothing owed, six days" "$?" "1"
  is_due "" 0 2026-10-24 2026-10-30 > /dev/null; chk "an unanswered gh is 'cannot tell', never 'not due'" "$?" "2"
  rm -rf "$d"
  [ "$rc" = 0 ] && echo "promote self-test: $n checks, 0 failed" || echo "promote self-test: FAILED"
  return "$rc"
}

case "${1:-}" in
  prepare) shift; cmd_prepare "$@" ;;
  commit)  shift; cmd_commit "$@" ;;
  gate)    shift; cmd_gate "$@" ;;
  due)     shift; cmd_due "$@" ;;
  --self-test) self_test ;;
  -h|--help|'') sed -n '2,/^set -u/p' "${BASH_SOURCE[0]}" | sed '$d'; [ -n "${1:-}" ] ;;
  *) die "unknown command '$1' (try --help)" ;;
esac
