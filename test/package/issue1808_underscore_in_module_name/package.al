## Issue #1808 — a `__` inside a module's own name is no scope separator. `src/a__b.al` is the top-level
## module `a__b` (a `__` within a declared name is a lint, not an error, Modules §6.6), and `src/a__k.al` is
## the top-level module `a__k`; there is no module `a`. The scope walk climbs from `a__b` straight to the
## package root, whose `k := z` binds `k` to the module `z` (Modules §4.1, §5), so `k::C` written in `a__b`
## is `z`'s `pub C := u64` (Declarations §5, §6.1). `rd(k::C, h)` reads all eight bytes of 10759 and divides
## by 256: 42. Cutting `a__b` at its `__` gave the parent `a`, a module that does not exist, and took `a__k`
## for its child `k`: `rd` was registered at `a__k`'s `u8`, and it answered 0.
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
      output = "issue1808-underscore-in-module-name",
    ),
  ],
)
k := z
## spec: Modules §1, §3, §4.1, §5, §6.6; Declarations §5, §6.1; Comptime §3.2
## expect: run 42
