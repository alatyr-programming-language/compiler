## Modules §1/§4/§6 — two sibling modules keep same-spelled byte-array globals
## distinct. This preserves the external Proposal #4 package boundary: the
## linker must not concatenate or otherwise merge the two module symbols.
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
      output = "global-collision-bytes",
    ),
  ],
)
