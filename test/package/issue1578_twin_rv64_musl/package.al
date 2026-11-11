## #1578 — a twin emit verb over a package keeps the manifest's Linux projections and replaces only the
## arch. This manifest is a supported x86_64 target with env musl (per-arch appendix §1: x86_64 Linux
## is gnu or musl). Under `alatyr aarch64` the composed target is still a row (aarch64 Linux admits
## musl), so it emits; under `alatyr riscv64` it is not (riscv64 Linux is gnu alone), so the verb must
## refuse it with a located Config diagnostic (Manifest appendix §3.1: a Target outside the set) rather
## than publish a riscv64/musl model no row describes.
##
## PARENT (696f9b12, the aarch64 leg of #1578), measured on native x86_64: `alatyr riscv64` on this
## manifest exited 0 with 691 bytes of assembly and nothing on stderr, where a located refusal was due.
app := Package(
  version = "0.1.0",
  source_dir = "src",
  target_dir = "target",
  targets = [
    Target(
      arch = Arch.x86_64,
      os = Os.linux,
      env = Env.musl,
      container = Container.elf,
      entry = "_start",
      output = "twin-rv64-musl",
    ),
  ],
)
## The program runs to 42 on every backend that may build this target. Composed with `alatyr riscv64`
## it is riscv64/musl, which no per-arch appendix §1 row describes, so that verb refuses it at line 18.
## spec: Tooling §2.7; per-arch appendix §1 (Linux/riscv64: gnu); Manifest appendix §3.1
## expect: run 42
## expect(riscv64): reject "has an unsupported Env for this Arch" "at line 18"
