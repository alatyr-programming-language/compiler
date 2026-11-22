## Issue #1808 — a qualifier the spelling module binds as a module alias names the module the alias binds,
## whatever other module carries the same last segment. In `m`, `k := zz::a` binds `k` to the module
## `zz::a` (Modules §4.1), so `k::C` is `zz::a`'s `pub C := u64` (§4.2). The unrelated module `y::k`
## declares `pub C := u8`, and `m` cannot even name it as `k` (Modules §3: it is a child of the sibling
## `y`). `rd(k::C, h)` reads all eight bytes of 10759 and divides by 256: 42. With a module whose last
## segment is `k` taken before `m`'s binding was asked, `k::C` named `y::k`'s `C`, `rd` was registered at
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
      output = "issue1808-path-alias-shadows-other-k",
    ),
  ],
)
## spec: Modules §3, §4.1, §4.2; Declarations §1.3, §5, §6.1; Comptime §3.2
## expect: run 42
