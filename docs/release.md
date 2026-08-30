# Release, bootstrap, and provenance contract

A release is reproducible only when the compiler revision, canonical source-tree hash,
seed lineage, specification version, target matrix, and gate results are
recorded together. `scripts/release_manifest.sh` emits this data as stable JSON
without embedding credentials or host-specific paths.

## Required inputs

The manifest includes:

- the current Git commit and clean/dirty state;
- a SHA-256 of the canonical path/content source-tree snapshot;
- `seed/VERSION` and the seed source hashes;
- the specification version and pinned/post-tag revisions from `README.md`;
- every row in `docs/target-support.tsv`;
- tool versions and the status of the fixpoint, package, conformance, and
  contract gates.

Gate statuses are `pass`, `fail`, `not-run`, or `blocked`. `not-run` and
`blocked` are honest release states; they are never rewritten to `pass` because
an optional tool was missing. A release consumer can therefore distinguish a
verified artifact from a manifest collected in a constrained environment.

## Bootstrap and fixpoint

The source compiler is bootstrapped in the repository layout. The authoritative
sequence is Stage1 → Stage2 → Stage3 followed by the source, package, target,
and conformance gates. A release cannot claim fixpoint success from one direct
seed build, and it cannot move the compiler outside the repository layout to
make a check pass.

## Compatibility

The frozen language/spec version is the compatibility boundary. User-visible
stdlib additions are listed under `Unreleased` before release. Target rows and
artifact kinds are additive only when their semantics and gates are present;
otherwise the CLI reports the unsupported form and the release manifest keeps
the target non-production.

## Commands

```text
bash scripts/release_manifest_test.sh
bash scripts/full.sh
```

The first command validates deterministic manifest shape. The second is the
authoritative repository gate and must run in the documented Nix environment.
