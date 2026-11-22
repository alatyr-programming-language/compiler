## Issue #1808 — the scope walk climbs the module tree, not a split of the mangled identity. The module
## `p_::q` has the identity `p___q`, which as text is `p_` + `q` or `p` + `_q` (an identifier may begin or
## end with `_`, Grammar §2.2); Modules §6.6 demangles by the module tree. `q`'s parent is `p_`, whose
## `k := z` binds `k` to the module `z` (Modules §4.1), so `k::C` written in `p_::q` is `z`'s
## `pub C := u64`, not the root's child `k` with `pub C := u8` (Declarations §5, §6.1). `rd(k::C, h)` reads
## all eight bytes of 10759 and divides by 256: 42. Cutting `p___q` at its first `__` gave the parent `p`,
## a module that does not exist: the walk skipped `p_`, `rd` was registered at `u8`, and it answered 0.
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
      output = "issue1808-underscore-module-parent",
    ),
  ],
)
## spec: Modules §1, §3, §4.1, §4.2, §6.6; Declarations §5, §6.1; Grammar §2.2; Comptime §3.2
## expect: run 42
