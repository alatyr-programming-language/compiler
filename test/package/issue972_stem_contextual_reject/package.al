## Issue #972 / spec#192, spec#199 — `scoped` is a contextual keyword (Grammar §2.3): an ordinary identifier
## outside its position, so whether it may be a module stem is undecided (latent spec#199). Until it is
## decided the compiler refuses a scanned `src/scoped.al` with a located diagnostic (spec AGENTS.md).
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
      output = "issue972-stem-contextual-reject",
    ),
  ],
)
## expect: reject "src/scoped.al" "segment `scoped`, a contextual keyword"
