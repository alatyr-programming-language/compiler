## Issue #1808 — a module's parent comes from the module tree, not from its mangled identity. `src/p/_q.al`
## is the module `p::_q`, identity `p___q`: `_q` is an ordinary identifier (Grammar §2.2), and `p` is a
## directory with no file of its own (Modules §1). As text, `p___q` is also `p_` + `q`, and `src/p_.al` is a
## real module here, but it is not `_q`'s parent; Modules §6.6 demangles by the module tree. The walk climbs
## from `p::_q` to `p`, whose child `k` binds the name (Modules §5), so `k::C` written in `p::_q` is
## `p::k`'s `pub C := u64`, not the root's child `k` with `pub C := u8` (Declarations §5, §6.1). `rd(k::C, h)`
## reads all eight bytes of 10759 and divides by 256: 42. Taking the longest prefix with a file as the parent
## named `p_`; without `src/p_.al`, the longest prefix, also `p_`. Either way the walk skipped `p`, `rd` was
## registered at `u8`, and it answered 0.
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
      output = "issue1808-directory-parent-underscore",
    ),
  ],
)
## spec: Modules §1, §3, §5, §6.6; Declarations §5, §6.1; Grammar §2.2; Comptime §3.2
## expect: run 42
