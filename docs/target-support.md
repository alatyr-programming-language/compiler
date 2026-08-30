# Target support contract

This is the user-facing target contract for the compiler at the current pinned specification
revision. The machine-readable source is [`target-support.tsv`](target-support.tsv); the contract gate
checks that the table and the CLI's fail-loud boundaries remain aligned.

## Status vocabulary

- `yes` means the operation is implemented and covered by the corresponding local gate.
- `check-only` means configuration, parsing, and semantic validation are supported, but no artifact is
  produced by that operation.
- `test-only` means the cross backend is exercised by `alatyr test` and the corpus harness, not by the
  ordinary package `build`/`run` path.
- `unsupported` means the CLI rejects the request with a located configuration diagnostic before
  invoking an assembler, linker, emulator, or producing an artifact.

## Machine and backend matrix

| surface | `build` | `check` | `emit` | `assemble` | `run` | boundary |
| --- | --- | --- | --- | --- | --- | --- |
| Linux `x86_64` / GNU / ELF | yes | yes | yes (`alatyr` dump) | yes (`as`) | yes | reference package target |
| Linux `aarch64` / GNU / ELF | unsupported by package build | yes | yes (`aarch64`) | test-only | test-only (`qemu-aarch64`) | cross target test path |
| Linux `riscv64` / GNU / ELF | unsupported by package build | yes | yes (`riscv64`) | test-only | test-only (`qemu-riscv64`) | cross target test path |
| WASM additive backend | not a `Target.arch` value | check through corpus input | yes (`wat`) | test-only (`wat2wasm`) | test-only (`wasmtime`) | no invented WASM `Arch` enum value |
| `i386`, `aarch32`, `riscv32` | unsupported | unsupported | unsupported | unsupported | unsupported | located `Target.arch` rejection |
| 64-bit non-Linux `Machine` variants | unsupported by artifact commands | check-only | unsupported | unsupported | unsupported | validation is available; linker/ABI is not |

The cross rows are intentionally not advertised as ordinary package builds. A missing cross assembler,
linker, emulator, or WASM tool is an environment failure for the conformance gate; it is never converted
into a partial green result.

## Artifact kinds

On the supported Linux `x86_64` machine, `Kind.executable`, `Kind.object`, and `Kind.static_lib` have
artifact-producing paths. `Kind.source` is a validation-only target for `check`. `Kind.shared_lib` is
not implemented. The CLI applies this rule consistently to `check`, `build`, `run`, and `test`, and
locates the rejection at the manifest's `kind` field.

The current target contract is deliberately narrower than the enum vocabulary. Adding a target or
artifact kind requires its linker/ABI, positive smoke test, negative unsupported-shape test, and a
reviewed update to both the TSV and this document.

## Verification

```sh
bash scripts/contract_check.sh
bash scripts/package_cli_test.sh
bash scripts/corpus_manifest.sh --check
```

The last command requires all four backend toolchains. `scripts/full.sh --force-sweeps` is the
authoritative integration command when the declared runner is available.
