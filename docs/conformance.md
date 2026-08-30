# Cross-backend conformance

The compiler treats a backend difference as a conformance observation, not as a reason to widen the
accepted language silently. The committed oracle is `scripts/corpus.manifest` and is produced by
`scripts/corpus_manifest.sh`.

## Observation record

Each row is keyed by `(backend, path)` and has this shape:

```text
backend<TAB>path<TAB>phase<TAB>exit<TAB>stdout_sha256<TAB>stderr_sha256
```

`phase` is `compile`, `assemble`, `link`, or `run`; build-phase timeouts carry a `_timeout` suffix.
An error row is still useful evidence: it says where the backend stopped and preserves normalized
diagnostic bytes. A `run` row is the only row that claims an executable was actually observed.

The four observed surfaces are `x86_64`, `aarch64`, `riscv64`, and `wasm`. Artifact paths are relative
to the checkout, the child environment is fixed, and host-specific paths are normalized before hashing.
This makes a comparison meaningful across checkout directories.

## Fail-closed rules

- Every tracked `test/*.al` contributes one row per backend unless an explicit, tracked quarantine pair
  exists.
- A missing cross toolchain is an environment error; a three-backend manifest cannot be blessed.
- Each backend must reach `run` for at least one source and produce at least two distinct exit codes.
  These checks prevent an always-failing or always-returning runner from looking green.
- A mismatch is joined by `(backend, path)` and classified as `NO-LONGER-RUNS`, `EXIT-CHANGED`,
  `OUTPUT-CHANGED`, `PHASE-CHANGED`, `DETAIL-CHANGED`, `NOW-RUNS`, `ADDED`, or `REMOVED`.
  Positional reading of a diff is not a conformance analysis.
- The oracle is never regenerated in a feature branch. A behavior transition is reviewed after local
  integration and recorded in a separate one-file oracle commit.

## Checks for semantic drift

The x86 front end type-checks the same input before each non-x86 emitter. A rejected program therefore
cannot become a valid-looking non-x86 artifact through an emit-only path. Backend-specific unsupported
forms remain explicit traps or located rejections. The package and target contract is documented in
[`target-support.md`](target-support.md), while lowering ownership is documented in
[`lowering.md`](lowering.md).

Run the gate from the declared development shell:

```sh
nix develop -c bash scripts/corpus_manifest.sh --check
nix develop -c bash scripts/full.sh --force-sweeps
```

`FULL GATE: GREEN` without `sweeps: STATUS=RAN` is not evidence that the non-x86 sweeps executed.
