- **A changelog entry is a file of its own, `changelog.d/<issue>-<slug>.md` (#1566).** Contributors
  no longer add a line under `## Unreleased`. Each entry is a new file, so two PRs never conflict over
  this file, and `scripts/promote.sh` releases the fragments with the version. The full gate now
  refuses a line added under `## Unreleased`: a PR opened before this change moves its bullet into
  a fragment at its next rebase. No compiler behaviour changes.
