#!/usr/bin/env bash
# scripts/spec_pin_check_test.sh — the gate-of-the-gate for scripts/spec_pin_check.sh (issue #1000).
#
# WHY THIS EXISTS AND NOT JUST THE CHECK. `spec_pin_check.sh` compares five statements of one number,
# and on a healthy tree it never reaches its own failure verdict — so a decider that always agreed, or
# that silently compared nothing, would print the same green line forever. AGENTS.md states the rule:
# "a green gate that never fails its own planted defect is not evidence". Thirteen planted trees drive
# the decider directly, and FOUR of them are CONTROLS that must stay green:
#
#   1. an agreeing tree (the baseline — without it every refusal below is just an always-fail script).
#      Its DECOYS ride along and must not fire: a compiler version in README prose, a retired revision
#      in AGENTS.md outside "The pin", an append-only promotion entry in seed/VERSION, and the word
#      `inspect` in package_cli_test.sh — extraction that over-fires fails here;
#   2. the same tree with NO specification checkout beside it (the tag half must SKIP, out loud);
#   3. the same tree with a checkout whose `v1.1.0` tag exists (the tag half must PASS, count itself,
#      and name the commit it resolved);
#   4. a seed/VERSION with no `spec-pin:` line at all — skipped, named in the same verdict line, and
#      still green: the skip is said out loud so it cannot rot into a silent hole.
#
# The nine plants then refuse: SIX disagreements (README, AGENTS.md, package_cli_test.sh, seed/VERSION,
# a README that cites TWO revisions, and a specification checkout with no tag for the cited release), and
# THREE refusals for a missing or ambiguous constant (absent, twice, malformed) — those exit 2 rather
# than agreeing with 0, because a check that cannot say what the pin IS must not report agreement.
#
# Run standalone:  bash scripts/spec_pin_check_test.sh
# Wired into the gate at `scripts/full.sh --self-test`, which every full run executes first.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$ROOT/scripts/spec_pin_check.sh"

## A minimal tree that AGREES on 1.1.0, decoys included. Every case edits ONE thing out of a copy of
## this, so a failure names the site that moved and nothing else can be blamed for it.
sp_repo() { # dir
  local d="$1"
  mkdir -p "$d/src" "$d/scripts" "$d/seed" || return 1
  printf '## the pin, in code.\npub SPEC_REVISION := "1.1.0"\n' > "$d/src/spec_revision.al"
  cat > "$d/README.md" <<'EOF'
![conforms to spec 1.1.0](https://img.shields.io/badge/spec-1.1.0-blue)

Released as 0.2.16 of the compiler — a number that is NOT the pin and never moves with it.

This tree is answerable to specification revision **1.1.0** (tag `v1.1.0`, spec commit `65a0c9b`).

$ target/debug/alatyr --version
alatyr 0.2.16, spec 1.1.0
EOF
  cat > "$d/AGENTS.md" <<'EOF'
## Authority

- **The pin.** This repository is answerable to specification revision **1.1.0** (tag `v1.1.0`,
  `65a0c9b`), a tagged release.
- A promotion releases `v0.2.16`; that is the compiler's version, not the pin, and it sits outside
  "The pin" on purpose.
EOF
  cat > "$d/scripts/package_cli_test.sh" <<'EOF'
# inspect the artifact, then compare the version line.
printf 'alatyr 0.2.16, spec 1.1.0\n' >"$want"
EOF
  cat > "$d/seed/VERSION" <<'EOF'
# ─── CURRENT SEED ─────────────────────────────────────────────
current-seed-sha256: 0000000000000000000000000000000000000000000000000000000000000000
current-seed-version: 0.2.16
# spec-pin: 1.1.0 (tag v1.1.0, spec commit 65a0c9b)

# Self-promoted 2026-10-15 — the append-only record.
# The specification pin (1.0.0 plus post-tag commits to b4e7979) did not move.
EOF
  return 0
}

## One case: run the decider over a planted tree, assert the exit status AND that its output says the
## named thing. `want` may be repeated; every one must appear in stdout or stderr.
sp_case() { # label root want-rc [needle …]
  local label="$1" root="$2" want_rc="$3" out rc bad=0
  shift 3
  out="$(bash "$CHECK" "$root" 2>&1)"
  rc=$?
  if [ "$rc" != "$want_rc" ]; then
    echo "FAIL spec pin self-test [$label]: rc=$rc, want $want_rc" >&2
    printf '%s\n' "$out" | sed 's/^/      /' >&2
    return 1
  fi
  local n
  for n in "$@"; do
    case "$out" in
      *"$n"*) ;;
      *) echo "FAIL spec pin self-test [$label]: verdict never mentioned '$n'" >&2
         printf '%s\n' "$out" | sed 's/^/      /' >&2
         bad=1 ;;
    esac
  done
  [ "$bad" = 0 ] || return 1
  echo "ok   spec pin self-test [$label]: rc=$rc"
  return 0
}

## A specification checkout with a tag, for the two cases that need one.
sp_spec() { # dir tag…
  local d="$1"; shift
  mkdir -p "$d" || return 1
  git -C "$d" init -q || return 1
  git -C "$d" config user.email spec@example.invalid
  git -C "$d" config user.name "spec pin self-test"
  printf '# specification\n' > "$d/spec.md"
  git -C "$d" add -A >/dev/null 2>&1
  git -C "$d" commit -qm "release" >/dev/null 2>&1 || return 1
  local t
  for t in "$@"; do git -C "$d" tag "$t" >/dev/null 2>&1 || return 1; done
  return 0
}

main() {
  local st bad=0
  if [ ! -f "$CHECK" ]; then
    echo "FAIL spec pin self-test: no decider at $CHECK" >&2
    return 1
  fi
  st="$(mktemp -d)" || return 1
  # shellcheck disable=SC2064
  trap "rm -rf '$st'" RETURN
  ## Deterministic by construction: every case names its specification checkout. The default points at a
  ## path that does not exist, so the tag half SKIPs in every case unless the case plants a checkout and
  ## points at it (cases 3 and 9). Without this the half would depend on what happens to sit beside the
  ## temporary directory, and a skip that depends on the machine is not evidence either way.
  export ALATYR_SPEC_ROOT="$st/no-spec"

  ## 1 — THE CONTROL. Everything agrees; the decoys (a compiler version in README prose, a retired
  ##     revision outside AGENTS.md "The pin", an append-only entry in seed/VERSION, the word
  ##     `inspect`) must not fire.
  sp_repo "$st/agree" || return 1
  sp_case control "$st/agree" 0 "spec pin: revision=1.1.0" "sites=5" || bad=1

  ## 2 — CONTROL: no specification checkout. The tag half SKIPS and says why; it does not pass quietly.
  sp_case no-spec-repo "$st/agree" 0 "tag=SKIPPED" "spec-repo(no tagged checkout" || bad=1

  ## 3 — CONTROL: a checkout WITH the tag. The half must run, count itself, and name the commit it
  ##     resolved — a `tag=SKIPPED` here would mean the half is decoration.
  mkdir -p "$st/tagged" || return 1
  sp_repo "$st/tagged/compiler" && sp_spec "$st/tagged/spec" v1.1.0
  ALATYR_SPEC_ROOT="$st/tagged/spec" sp_case tag-exists "$st/tagged/compiler" 0 "tag=v1.1.0@" "sites=6" || bad=1

  ## 4 — the plant: README moves. The refusal names README.md and BOTH numbers.
  sp_repo "$st/readme" && sed 's/1\.1\.0/1.0.0/g' "$st/agree/README.md" > "$st/readme/README.md"
  sp_case readme-disagrees "$st/readme" 1 "README.md cites 1.0.0" "src/spec_revision.al is 1.1.0" || bad=1

  ## 5 — the plant: AGENTS.md moves. This is the pin commit half-done, the shape #1000 would leave
  ##     behind if the pin bullet and the constant could drift apart.
  sp_repo "$st/agents" && sed 's/1\.1\.0/1.0.0/g' "$st/agree/AGENTS.md" > "$st/agents/AGENTS.md"
  sp_case agents-disagrees "$st/agents" 1 "AGENTS.md 'The pin' cites 1.0.0" || bad=1

  ## 6 — the plant: the expected `--version` line moves. CHANGELOG.md calls this file "the one that
  ##     gets forgotten"; here it is the only thing that forgot.
  sp_repo "$st/pkgtest" && sed 's/, spec 1\.1\.0/, spec 1.0.0/' "$st/agree/scripts/package_cli_test.sh" \
    > "$st/pkgtest/scripts/package_cli_test.sh"
  sp_case package-cli-disagrees "$st/pkgtest" 1 "package_cli_test.sh expects ', spec 1.0.0'" || bad=1

  ## 7 — the plant: seed/VERSION's pin note moves.
  sp_repo "$st/seed" && sed 's/spec-pin: 1\.1\.0/spec-pin: 1.2.0/' "$st/agree/seed/VERSION" \
    > "$st/seed/seed/VERSION"
  sp_case seed-disagrees "$st/seed" 1 "seed/VERSION's CURRENT SEED pin note says 1.2.0" || bad=1

  ## 8 — the plant: README cites TWO revisions. An ambiguous claim is not an agreement.
  sp_repo "$st/ambig" && printf '\nEarlier builds answered specification revision **1.0.0**.\n' \
    >> "$st/ambig/README.md"
  sp_case readme-two-revisions "$st/ambig" 1 "README.md cites 1.0.0/1.1.0" || bad=1

  ## 9 — the plant: a checkout with NO tag for the cited revision. The compiler pins tagged releases,
  ##     so citing an untagged number is refused rather than skipped.
  mkdir -p "$st/untagged" || return 1
  sp_repo "$st/untagged/compiler" && sp_spec "$st/untagged/spec" v9.9.9
  ALATYR_SPEC_ROOT="$st/untagged/spec" sp_case tag-missing "$st/untagged/compiler" 1 "no tag 'v1.1.0'" || bad=1

  ## 10 — the plant: no constant. Refuse (2): there is nothing to compare, so "agreed" would be a lie.
  sp_repo "$st/noconst" && rm -f "$st/noconst/src/spec_revision.al"
  sp_case constant-absent "$st/noconst" 2 "declares the pin 0 time" || bad=1

  ## 11 — the plant: TWO constants. Refuse (2): the check must not pick one.
  sp_repo "$st/twoconst" && printf 'pub SPEC_REVISION := "1.0.0"\n' >> "$st/twoconst/src/spec_revision.al"
  sp_case constant-twice "$st/twoconst" 2 "declares the pin 2 time" || bad=1

  ## 12 — the plant: a malformed constant (a hash, not a release number). Refuse (2), and prove the
  ##     control above is not passing merely because its line happens to match.
  sp_repo "$st/malformed" && printf '## the pin, in code.\npub SPEC_REVISION := "b4e7979"\n' \
    > "$st/malformed/src/spec_revision.al"
  sp_case constant-malformed "$st/malformed" 2 "declares the pin 0 time" || bad=1

  ## 13 — CONTROL: seed/VERSION carries no `spec-pin:` line. Skipped, named, still green — the skip is
  ##      said out loud so it cannot become a silent hole when the pin next moves.
  sp_repo "$st/noseedpin" && grep -v 'spec-pin:' "$st/agree/seed/VERSION" > "$st/noseedpin/seed/VERSION"
  sp_case seed-note-absent "$st/noseedpin" 0 "sites=4" "seed/VERSION(no 'spec-pin:' line" || bad=1

  if [ "$bad" = 0 ]; then
    echo "spec pin: gate-of-the-gate OK — 13 planted trees (4 controls green, 6 disagreements named, 3 refusals)"
  else
    echo "*** spec pin: gate-of-the-gate FAILED — the pin decider is not doing what it claims ***" >&2
  fi
  return "$bad"
}

main
exit $?
