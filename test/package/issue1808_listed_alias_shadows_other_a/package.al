## Issue #1808 — a listed member projection binds its names in the scope walk, whatever other module
## carries the same last segment. In `m`, `(a, b) := zz` binds `a` to the module `zz::a` (Modules §4.1.1),
## so `a::C` is `zz::a`'s `pub C := u64` (§4.2). The unrelated module `y::a` declares `pub C := u8`, and
## `m` cannot name it as `a` (Modules §3: it is a child of the sibling `y`). `rd(a::C, h)` reads all eight
## bytes of 10759 and divides by 256: 42. With the projection not seen as a binding, no scope bound `a`,
## the qualifier was ranked by its text, `a::C` named `y::a`'s `C`, `rd` was registered at `u8`, and it
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
      output = "issue1808-listed-alias-shadows-other-a",
    ),
  ],
)
## spec: Modules §3, §4.1, §4.1.1, §4.2, §5; Declarations §5, §6.1; Comptime §3.2
## expect: run 42
