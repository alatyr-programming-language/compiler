## AMBIGENUM — Modules §1/§4 and Types §4.1.
## The package deliberately contains two nominal pub Error enums. The root match receives
## wide::Error through Result, but the bare payload span loses that module identity.
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
      output = "ambig-enum-name-collision",
    ),
  ],
)
