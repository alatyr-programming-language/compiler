## Issue #703 / Modules §2, §5 — sibling modules each declare `cfg` and `lim`, one as a struct
## global and one as a scalar, in BOTH module orders. A field read resolves the owner in its own
## module's scope, so every read here is legal. Expected exit 42 (12 from `a`, 7 from `z`, plus 23).
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
      output = "issue703-global-module-scope",
    ),
  ],
)
## expect: run 42
