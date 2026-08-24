## Modules §1/§4/§6 — two sibling modules keep same-spelled scalar globals
## distinct. This is the silent-sharing face of external Proposal #4.
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
      output = "global-collision-scalar",
    ),
  ],
)
