## Modules §1 / §6 — nested files under `source_dir` form qualified modules. `geometry/vec.al`
## must be emitted as `geometry__vec`; the package root remains the anonymous entry context.
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
      entry = "_start",
      output = "nested-modules",
    ),
  ],
)
