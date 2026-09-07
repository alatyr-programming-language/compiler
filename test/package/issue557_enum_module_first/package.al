## Issue #557 / Control Flow §5.1 + Modules §1 — exhaustiveness must not depend on the ORDER in which
## a package's modules are checked. Module membership is a set, not a sequence, so the same program
## must get the same verdict whichever file name the enum's module happens to sort under.
## The enum's module sorts BEFORE the consuming module.
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
      output = "issue557-enum-module-first",
    ),
  ],
)
