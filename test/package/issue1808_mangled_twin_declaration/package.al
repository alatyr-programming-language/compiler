## Issue #1808 — two modules whose identities spell the same text are still two modules. `src/p_/q.al` is the
## module `p_::q` and the directory `src/p/_q/` is the module `p::_q`; both spell `p___q`, and neither has a
## parent the other names (Modules §1, §6.6). `p::_q` has no file and declares nothing; `p_::q` declares
## `k := y`. Written in `p::_q::r`, `k::C` climbs `p::_q::r` -> `p::_q` -> `p`, whose child `k` binds it
## (Modules §5): `p::k`'s `pub C := u64`, not `y`'s `pub C := u8` (Declarations §5, §6.1). `rd(k::C, h)` reads
## all eight bytes of 10759 and divides by 256: 42. Every emitted symbol is distinct (`p___q__ff`,
## `p___q__r__…`), so Modules §6.7 does not make the package ill-formed. Asking "does `p::_q` declare `k`?" by
## the identity's text alone took `p_::q`'s alias, registered `rd` at `u8`, and answered 0.
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
      output = "issue1808-mangled-twin-declaration",
    ),
  ],
)
## spec: Modules §1, §3, §5, §6.6, §6.7; Declarations §5, §6.1; Grammar §2.2; Comptime §3.2
## expect: run 42
