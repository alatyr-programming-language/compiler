# Alatyr compiler (self-hosted)

![conforms to spec 1.0.0](https://img.shields.io/badge/spec-1.0.0-blue)
![status: self-hosted, pre-release](https://img.shields.io/badge/status-self--hosted%2C%20pre--release-orange)
![license Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-green)

The reference **Alatyr** compiler, written in Alatyr. It compiles itself to a byte-for-byte
reproducible binary — the TOOL-1 fixpoint. x86_64 / Linux / ELF, freestanding (raw syscalls, no libc).

The working guarantee is **correct, or loudly wrong**: a trap or a located rejection is an acceptable
outcome, a clean compile that returns the wrong answer is not. The open
[issues](https://github.com/alatyr-programming-language/compiler/issues) are honest about where that
guarantee does not yet hold and what the cross-backend coverage actually is — read them before deciding
what this is ready for.

The supported-target and artifact contract is [documented in the repository](docs/target-support.md);
the machine-readable matrix is [docs/target-support.tsv](docs/target-support.tsv). Linux x86_64 is the
production build/run target. AArch64, RISC-V64, and WAT rows marked `test-only` or `check-only` are
explicit probes, not portability promises. Package semantics, standard-library boundaries, safety, and
release provenance are documented in [docs/package-tooling.md](docs/package-tooling.md),
[docs/stdlib.md](docs/stdlib.md), [docs/safety.md](docs/safety.md), and
[docs/release.md](docs/release.md).

## Quick start

```sh
nix develop                              # as / ld
seed/alatyr build package.al             # bootstrap: build the compiler -> target/debug/alatyr
target/debug/alatyr build package.al     # rebuild it with itself
./scripts/fixpoint.sh                    # verify reproducibility (seed == Stage1 == Stage2)
bash scripts/contract_check.sh            # validate target/package/stdlib/release contracts
bash scripts/release_manifest_test.sh    # validate deterministic release metadata
```

## Layout

- `package.al` — manifest (`source_dir = "src"`, `target_dir = "target"`).
- `src/` — the compiler (one module per file).
- `lib/` — the standard library. It ships **with** the compiler and is injected ambiently, so it is
  part of the toolchain rather than a dependency — nothing in a manifest brings it in, and a first
  build needs no network. The specification's stdlib appendix defines its surface.
- `seed/alatyr` — frozen static bootstrap binary (+ `VERSION`, the lineage log).
- `target/` — build artifacts (gitignored).
- `test/`, `scripts/` — the fixtures and the gates.

Cross-language benchmarks live in a separate repository,
[`benchmarks`](https://github.com/alatyr-programming-language/benchmarks).

The language is defined by the [specification](https://github.com/alatyr-programming-language/spec),
which is the source of truth: the toolchain conforms to it, never the other way round. This tree
is answerable to spec revision **1.0.0** (tag `v1.0.0`) plus the post-tag commits up to spec `main`
`b4e7979` — `AGENTS.md` carries the full pin and moves it in its own commit. The pin is an obligation,
not a claim of completeness: where the tree lags it, the gap is an open issue — today that is the
`help`/`version` surface and the diagnostic for an unrecognised argument
([#192](https://github.com/alatyr-programming-language/compiler/issues/192)). The Rust
compiler that bootstrapped the first self-host binary is frozen and not published; `seed/VERSION`
records the lineage.
