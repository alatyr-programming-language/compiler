- **The merge queue composes through an append-only conflict in `scripts/e2e.sh` instead of sending
  it back (#1390).** Every fixture PR appends its `run` rows at the end of one list, so every second
  queued PR came back as "conflicts with main" for a hand rebase. A batch now composes through such a
  conflict when BOTH sides only added lines at one anchor: both runs are kept, ours first, and the
  merge commit says so (`scripts/land.sh --settle-append-only`, called by the queue from the base's
  copy). A conflict where either side rewrote or deleted a line, one in any other file, and one in a
  counted registry (`scripts/seed_forms.tsv`, `scripts/known-deviations.tsv`) stay refusals.
  `CHANGELOG.md` is not settled here: an entry is a `changelog.d/` fragment since #1566.
