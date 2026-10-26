#!/usr/bin/env bash
# scripts/attribution.sh — the ONE definition of what an attribution trailer is and how to refuse it.
#
# Sourced, never executed: `scripts/land.sh` calls the decider at landing (PHASE 2, over the PR body
# and every commit in BASE..HEAD), and `scripts/hooks/pre-commit` calls it before a commit is created.
# Both read this file, so the two can never disagree about the same message — a private copy of the
# pattern in the hook is the same defect class as a private `*_field_is_scalar` in an emitter: one
# place decides, the rest alias it.
#
# WHY THE RULE EXISTS. A commit records who wrote it. Every commit in this repository is authored and
# committed under the owner's identity, and an agent working here has no standing to add a co-author
# trailer: GitHub renders `Co-Authored-By:` as a SECOND AUTHOR OF RECORD, so the trailer is not a
# courtesy note but a false statement about authorship in the permanent record — and it is the kind of
# false statement no later reader can audit, because there is no such co-author to ask. Nine such
# commits reached main before this decider existed, all naming an AI model. The prohibition had been
# given in conversation and never written where the next session reads it, which is the failure mode
# #600 removed for the other shape rules: a decision no self-test can call is a decision nothing can
# plant against. An agent's contribution is recorded where it IS true and reviewable — in the PR
# discussion, the review, and the gate evidence — not in the author field.
#
# SCOPE, and its boundary. Anchored to trailer syntax at line start, so prose that MENTIONS the
# words (this file, `AGENTS.md`, and the commit that adds this rule) is not refused; only an actual
# trailer is. Case-insensitive, because the tooling has emitted several casings. Hyphen or space both
# match, because "Generated with:" and "Generated-with:" are the same claim. In prose and commit
# bodies, write "co-author trailer" without the colon — the colon is what makes it a trailer.
ATTRIBUTION_TRAILER_RE='^[[:space:]]*(co[- ]authored[- ]by|co[- ]author|assisted[- ]by|ai[- ]assisted|generated[- ]with|generated[- ]by)[[:space:]]*:'

## Returns 0 to allow, 1 to refuse. Reads only its arguments — no repository state — so the land
## self-test drives the real decision without a merge, a network call, or a git object.
attribution_trailer_check() { # object message
  local hit
  hit="$(printf '%s\n' "$2" | grep -inE "$ATTRIBUTION_TRAILER_RE" | head -n 3 || true)"
  [ -z "$hit" ] && return 0
  printf '  REFUSE: %s carries an attribution trailer. Every commit here is authored under the owner'"'"'s\n' "$1"
  printf '          identity; GitHub renders this as a second author of record, which is not true.\n'
  printf '          Remove the trailer. The contribution belongs in the PR discussion and the gate\n'
  printf '          evidence, not in authorship. Matched:\n'
  printf '%s\n' "$hit" | sed 's/^/            /'
  return 1
}
