## Issue #403 — the OVER-TIGHTENING control. Closing the bare-spelling hole must not reject any of
## the shapes Modules §3 and Stdlib §1 make legal, so every one of them is exercised here and the
## exit code is a SUM: any single shape being refused, or answering wrong, misses 42.
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
      output = "issue403-bare-private-legal",
    ),
  ],
)
