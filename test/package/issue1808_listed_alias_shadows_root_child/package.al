## Issue #1808 — a listed member projection binds its names in the scope walk. In `m`, `(a, b) := zz` is
## sugar for `a := zz::a` and `b := zz::b` (Modules §4.1.1), so `m` binds `a` to the module `zz::a` and
## `a::C` is `zz::a`'s `pub C := u64` (§4.2), even though the root has a child module `a` declaring
## `pub C := u8`: `m`'s own binding is the inner scope (Declarations §5, §6.1). `rd(a::C, h)` reads all
## eight bytes of 10759 and divides by 256: 42. With only a single `name := …` declaration counted as a
## binding, the walk passed `m`, `a::C` named the root's `a::C`, `rd` was registered at `u8`, and it
## answered 0.
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
      output = "issue1808-listed-alias-shadows-root-child",
    ),
  ],
)
## spec: Modules §3, §4.1, §4.1.1, §4.2, §5; Declarations §5, §6.1; Comptime §3.2
## expect: run 42
