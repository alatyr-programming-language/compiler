## Issue #1808 — a qualifier resolves the way a bare name does: scope by scope, from the spelling module up
## to the root, and the first scope that binds the name wins (Declarations §5, §6.1; Modules §3, §5). In
## `m`, `k := z` binds `k` to the module `z` (Modules §4.1), so `k::C` is `z`'s `pub C := u64` (§4.2), even
## though the root has a child module `k` declaring `pub C := u8`: `m`'s own binding is the inner scope.
## `rd(k::C, h)` reads all eight bytes of 10759 and divides by 256: 42. With the qualifier ranked as a
## module path before `m`'s binding was asked, `k::C` named the root's `k::C`, `rd` was registered at
## `u8`, and it answered 0.
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
      output = "issue1808-module-alias-shadows-root-child",
    ),
  ],
)
## spec: Modules §3, §4.1, §4.2, §5; Declarations §5, §6.1; Comptime §3.2
## expect: run 42
