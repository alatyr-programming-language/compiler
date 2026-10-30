# Authority and the pin — rationale

Why the compiler answers to a tagged spec release, and what the pin does and does not claim.

Moved verbatim from `AGENTS.md` (#1130); the rule itself stays there in one line, and this file
keeps the reasons, measurements and history. Line citations are as of the move.

## Authority

- This is the canonical self-hosted Alatyr compiler. The language specification is the source of truth;
  the compiler conforms to it, never the reverse.
- Decide language questions in the specification before changing `src/`. If the specification is silent,
  stop and get the decision recorded; do not infer semantics from current behavior.
- **The pin.** This repository is answerable to specification revision **1.6.0** (tag `v1.6.0`,
  `01c75ab`). The pin names a TAGGED RELEASE and never a moving branch head: one number says what a range
  and two hashes used to, and the tag is what makes a citation resolve to exact text. It moved several
  revisions in one step, because the first candidates were tagged carrying defects an independent review
  found after each tag was pushed — a contradiction in Functions §1.4 over whether a heterogeneous
  `ptr`↔`usize` binding is admissible, and a derived `Pointer` walk whose mechanism was named as
  something outside the lattice. Both are resolved in the revision pinned here, which is the first of
  them that describes a mechanism the reference implementation can actually have. A tag is never
  rewritten, so earlier revisions stay citable; this tree answers to the one above.
- The pin records what the compiler is **answerable to**, not what it has already implemented: the tree
  may lag it, and each gap is an open issue. The number the compiler *reports* lives in
  `src/spec_revision.al` and is printed by `alatyr version` beside its own version, per TOOL-21
  (#1000); `scripts/spec_pin_check.sh` refuses a tree where that constant and the prose statements of
  it — README.md, this bullet, `scripts/package_cli_test.sh`'s expected `--version` line, and
  `seed/VERSION`'s CURRENT SEED pin note — drift apart. Move the pin only in a separate, explicit
  commit; never silently update it in a feature. Cite specification
  anchors, chapter sections, or issue numbers. Repository workstream tags are search tags, not
  specification citations.
