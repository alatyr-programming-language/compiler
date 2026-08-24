## TOOL-7 — the exclusion keys off the manifest's `Target.entry`, NOT a hardcoded `_start`: this
## package names `launch` as its entry (supplied by `@export("launch")`, Modules §6.3). `build`/`run`
## link with `ld -e launch`; the test artifact links neither `launch` nor the `_start` the program also
## declares for itself, and supplies the runner's entry instead.
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
      entry = "launch",
      output = "tool7-entry-named",
    ),
  ],
)
