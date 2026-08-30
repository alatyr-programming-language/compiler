# Package and target tooling contract

This document is the v1 package-tooling contract. The implementation is
deliberately conservative: a manifest is accepted only when its target and
artifact kind are understood, and an unsupported combination is reported at
the manifest location before an artifact is written.

## Manifest fields

| Field | Meaning | v1 behavior |
| --- | --- | --- |
| `Package(name, version)` | Package identity | Required for package mode. |
| `Target(name, arch, os, env)` | Build target | `name` selects the backend; `arch`, `os`, and `env` must agree with the target matrix. |
| `Profile(name)` | Optimization/debug profile | `debug`, `release`, and `size` are deterministic aliases for the documented compiler flags. |
| `Artifact(kind, path)` | Requested output | `bin`/`exe` are executable outputs; `obj` is an object output; `static_lib` is an archive output; `shared_lib` is reserved and rejected with a located diagnostic. |
| `Dependency(name, path)` | Local dependency | A normalized path inside the package root is supported. Git/version-range dependencies are not silently treated as local paths. |
| `Source(path)` | Explicit source entry | The path is normalized, must remain inside the package root, and is included in the deterministic build plan. |

Unknown fields, absolute paths, parent traversal, unsupported artifact kinds,
and target/architecture mismatches are errors. A failed validation must not
leave a partially written artifact.

## Deterministic build plan

`alatyr build --plan` emits the normalized target, profile, artifact kind,
source list, dependency list, compiler version, and selected backend. Lists are
sorted by their normalized package-relative path. The plan contains no current
time, process id, host path, or ambient environment value. The same manifest
and compiler revision therefore produce byte-identical plans; the release
manifest records the input revision separately.

Package dependencies are intentionally limited to checked-in local paths in
v1. A lockfile and Git/vendor resolution require a version-selection and trust
policy that is not present in the language specification. Until that decision
is recorded, the CLI rejects those forms with an actionable diagnostic instead
of pretending they are reproducible.

## Verification

The package CLI gate exercises successful plans, path containment, dependency
resolution, target mismatch diagnostics, unsupported artifact kinds, and
artifact non-production on failure:

```text
ALATYR=target/debug/alatyr bash scripts/package_cli_test.sh
```

`docs/target-support.tsv` is the machine-readable target surface. It is the
single input for the contract checker and release manifest; it is not an
implicit claim that a missing cross assembler or runtime is supported.
