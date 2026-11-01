## Issue #703 / Modules §2, MOD-3 — module `a` reads `z::cfg.x`, a field of the sibling `z`'s pub
## struct global, while `a` declares its own scalar `cfg`. `::` names `z`'s item, so the scalar-owner
## refusal must not answer for it: the owner is a struct. The program answers 42 (5 + 3 + 34). Today
## every backend still refuses the qualified struct-global field read as bare `invalid at line 2 in
## a`, a known deviation under #1336, and never with the scalar class.
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
      output = "issue703-global-module-scope-qualified",
    ),
  ],
)
## expect: run 42
