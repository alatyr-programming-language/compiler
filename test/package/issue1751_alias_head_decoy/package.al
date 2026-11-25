## Issue #1751 — a struct literal spelled through a module alias (`g := geo`, then `g::S(…)`) is
## `geo`'s `S` (Modules §4.1, §4.2: an alias is erased; Types §4.1, nominal types), even when a module
## declared LATER (`zz`) has its own `pub S` with another layout. Answers 40 + 2 = 42, and the
## out-of-order `g::S(b = 2, a = 40)` binds each value by name (Types §9.3): 42 again.
##
## NON-VACUOUS: at da8f96af (omen, native x86_64) every backend answered 2 (x86_64 measured; the issue measured 0 on all five columns with its decoy).
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
      output = "issue1751-alias-head-decoy",
    ),
  ],
)
## expect: run 42
