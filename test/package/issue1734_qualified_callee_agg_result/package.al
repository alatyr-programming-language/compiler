## Issue #1734, the control — the same program with the qualified call `m::mk()` instead of an alias.
## A bare type name in a callee's signature is resolved in the module whose text spells it (Modules
## §3), so the caller's own `S` cannot lay out `m`'s result whatever path reaches the callee.
## Answers 10 + 1 + 21 + 10 = 42.
##
## Base `b74089f3` (omen): x86_64 exits 39, and aarch64, riscv64 and wasm exit 23. The qualified
## call was no safer than the alias.
app := Package(
  version = "0.1.0",
  source_dir = "src",
  target_dir = "target",
  targets = [
    Target(
      arch = Arch.x86_64,
      os = Os.linux,
      env = Env.gnu,
      container = Container.elf,
      kind = Kind.executable,
      output = "issue1734-qualified-callee-agg-result",
    ),
  ],
)
## expect: run 42
