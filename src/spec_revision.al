## selfhost::spec_revision — the ONE place this compiler states which specification revision it is
## answerable to (issue #1000).
##
## TOOL-21 (spec v1.1.0, Tooling §4) makes this a MUST: `version` MUST identify the implementation and
## MUST report the revision of the specification it conforms to, because "an implementation's own version
## and the revision are separate axes, and reporting only the former leaves a user unable to tell what
## the toolchain implements". `app.version` (TOOL-15) answers the first axis; this constant is the
## second. Before this file existed the second axis had no home in the tree: `cli_version` printed only
## `alatyr <version>`, and the revision lived in prose (README, AGENTS.md) that nothing tied to the
## binary.
##
## THE FORM, and why it is a plain constant. `app.version` is the only field TOOL-15 injects into a
## package-owned module today; no second injection mechanism is invented for a number that changes once
## per specification release. So the revision is an ordinary `pub` source constant, and the copy in
## `cli_version`'s output is a compile-time constant like the version beside it — no file read, no
## environment lookup, nothing that could make `version` depend on the working directory (TOOL-21 says
## both introspection commands are valid from any directory).
##
## ONE NUMBER, FOUR PLACES. This is the specification pin in code, and `scripts/spec_pin_check.sh` is
## what keeps it from drifting: it refuses a tree where this constant, README.md, AGENTS.md "The pin",
## `scripts/package_cli_test.sh`'s expected `--version` line and `seed/VERSION`'s CURRENT SEED pin note
## do not all carry the same revision, and — when a checkout of the specification repository is reachable
## — it requires the tag `v<revision>` to exist there. The compiler pins TAGGED RELEASES only: a
## release number, never a bare commit hash. The pin itself moves only in its own explicit commit
## (AGENTS.md, Authority); this file moves with it.

pub SPEC_REVISION := "1.6.0"

## Where the known deviations from SPEC_REVISION are published (Overview §6; TOOL-21 at spec 9438d00;
## compiler#1000). SPEC_REVISION is this compiler's TARGET revision, not a conformance claim, so
## `version` names it as a target and points here. The table lists, per issue, the rule not met and
## the observable difference; scripts/known-deviations.tsv holds the fixture rows the gate holds to
## it (#1126). On `main`, so the list is the one kept current with the build that names it.
pub KNOWN_DEVIATIONS := "https://github.com/alatyr-programming-language/compiler/blob/main/scripts/known-deviations.issues.tsv"
