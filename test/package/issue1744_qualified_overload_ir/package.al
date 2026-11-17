## Issue #1744: a module-path call whose callee is one of an overload set stays refused by the shared
## IR builder, because its symbol carries the per-signature suffix (Q3 of docs/ir-slice-2.md). The
## call keeps the legacy emitter, which picks the member by the argument's type. Expected exit 42:
## the `u64` member answers 40 + 1, and the `u8` one, reached from inside `m`, answers 1.
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
      output = "issue1744-qualified-overload-ir",
    ),
  ],
)
## expect: run 42
