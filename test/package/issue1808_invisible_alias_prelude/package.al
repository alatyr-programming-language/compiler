## Issue #1808 — a declaration in a module that cannot be named does not replace a prelude type. The
## sibling module `z` declares `pub u64 := u8`; `pub` reaches only `z`'s parent, never its sibling `m`
## (Modules §3), so `u64` written in `m` is the prelude's `u64` (Grammar §2.3 makes it an identifier,
## Declarations §6.1 lets `z` shadow it in its own scope). `m::rd(u64, h)` reads all eight bytes of
## 10759 and the root divides by 256: 42. Resolved to `z`'s alias, the instance was `rd` at `u8`, which
## read one byte (7) and answered 0.
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
      output = "issue1808-invisible-alias-prelude",
    ),
  ],
)
## spec: Modules §3; Declarations §6.1; Comptime §3.2
## expect: run 42
