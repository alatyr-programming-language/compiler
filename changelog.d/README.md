# changelog.d — one entry, one file

A user-visible change writes its `CHANGELOG.md` entry here, as a **new file of its own**, never as a
line under `CHANGELOG.md`'s `## Unreleased` (#1566). Two PRs then never edit the same path, so the
entry cannot conflict at a rebase or in the merge queue.

- **Name:** `<issue>-<slug>.md`, for example `1416-brand-scalar-field.md`. The issue is the one the entry
  cites first. The slug uses lower-case letters, digits and single hyphens.
- **Body:** one or more bullets in `CHANGELOG.md`'s style, each continuation line indented two spaces or
  more (a nested item and its continuation go deeper). No blank line, no heading. What goes in an
  entry, and whether a change needs one, is `CHANGELOG.md`'s versioning policy.
- **To correct an entry** that is already under `## Unreleased`, delete it there and write the new
  text here.
- **Release:** `scripts/promote.sh` releases the fragments in issue order, after the section's own
  entries, under `## <version> — <date>`, and deletes them in the same atomic promotion commit.

`scripts/changelog_fragments.sh --check` holds the name, the body, and the addition rule. The full gate
runs it.
