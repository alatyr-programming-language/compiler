## AMBIGENUM reverse-order regression — Modules §1/§4 and Types §4.1.
## The narrow declaration is aaa_narrow.al, so the package walk sees it before wide.al.
## The same nominal collision must still fail loudly instead of depending on declaration order.
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
      output = "ambig-enum-name-collision-reverse",
    ),
  ],
)
