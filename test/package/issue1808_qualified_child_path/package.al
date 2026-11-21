## Issue #1808 — a qualified path into a child module names that child's declaration. `src/m/k.al` is the
## module `m::k` (Modules §1), so `k::C` written in `m` navigates to `m::k`'s `pub C := u64` (§2, §3),
## not to `m`'s own `C := u8`. They are two instances of `rd` (Comptime §3.2). `rd(k::C, h)` reads all
## eight bytes of 10759 and divides by 256: 42. With the qualifier matched only against whole module
## paths, `k::C` fell back to `m`'s own `C`, the two calls shared the instance at `u8`, and it answered 0.
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
      output = "issue1808-qualified-child-path",
    ),
  ],
)
## spec: Modules §1, §2, §3; Declarations §1.3; Comptime §3.2
## expect: run 42
