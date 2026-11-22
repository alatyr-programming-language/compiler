## Issue #1808 — a module's children are those of its own path, not of another module spelling the same text.
## `src/p_/q/k.al` is the module `p_::q::k`, identity `p___q__k`; the directory `src/p/_q/` is the module
## `p::_q`, identity `p___q` (Modules §1, §6.6). `p___q__k` runs through the text `p___q` with a path
## separator after it, but it is not `p::_q`'s child: `p_::q` is a different path. Written in `p::_q::r`,
## `k::C` climbs `p::_q::r` -> `p::_q` -> `p`, whose child `k` binds it (Modules §5): `p::k`'s
## `pub C := u64`, not `p_::q::k`'s `pub C := u8` (Declarations §5, §6.1). `rd(k::C, h)` reads all eight
## bytes of 10759 and divides by 256: 42. Asking "has `p::_q` a child `k`?" by the identity's text alone
## took `p_::q::k`, registered `rd` at `u8`, and answered 0.
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
      output = "issue1808-mangled-twin-child",
    ),
  ],
)
## spec: Modules §1, §3, §5, §6.6; Declarations §5, §6.1; Grammar §2.2; Comptime §3.2
## expect: run 42
