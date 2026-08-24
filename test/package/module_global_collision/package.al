## Modules §1 / §6 — same-spelled globals in different source modules are distinct declarations
## and therefore distinct path-qualified linker symbols. The fixture covers both a folded scalar
## constant and a stored byte array; either bare-name lookup leaking across modules changes exit 42.
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
      output = "module-global-collision",
    ),
  ],
)
