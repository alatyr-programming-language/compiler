## Codegen §3.5 / CG-10 — an @inline aggregate parameter must receive the complete
## logical value. The fixture also exercises the str→view bytes(...) builtin at the
## same inline call boundary.
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
      output = "inline-aggregate",
    ),
  ],
)
