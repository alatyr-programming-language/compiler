## Issue #1808 — a module's child is a whole path segment, never one that a path separator splits.
## `src/a__b.al` is the top-level module `a__b`, and `src/a/b/k.al` is the module `a::b::k`, identity
## `a__b__k` (Modules §1, §6.6). Its text starts with `a__b` with a path separator after it, but the `__`
## inside that text is a separator too: it runs through `a::b`, not through `a__b`. Written in `m`,
## `a__b::k::C` climbs `m` -> root, whose child `a__b` is the file `src/a__b.al` (Modules §5); its `k := z`
## binds `k` to the module `z` (Modules §4.1), so `C` is `z`'s `pub C := u64` (Declarations §5, §6.1).
## `rd(a__b::k::C, h)` reads all eight bytes of 10759 and divides by 256: 42. Matching the child segment's
## text without asking whether a separator falls inside it took `a::b::k`'s `pub C := u8`, registered
## `rd` at `u8`, and answered 0.
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
      output = "issue1808-split-segment-root-child",
    ),
  ],
)
## spec: Modules §1, §3, §4.1, §5, §6.6; Declarations §5, §6.1; Comptime §3.2
## expect: run 42
