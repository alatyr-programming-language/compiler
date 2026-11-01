## Issue #703 / Modules §2, §5 — module `a` reads a field of its own SCALAR global `cfg`, while the
## later module `z` declares a struct global of the same spelling. The owner resolves in `a`'s scope,
## so the read is refused at line 2 in a. Expected: check and build rc 1 with the located diagnostic.
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
      output = "issue703-global-module-scope-reject",
    ),
  ],
)
## expect: reject "a scalar has no field to name"
