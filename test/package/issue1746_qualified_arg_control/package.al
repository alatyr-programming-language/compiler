## Issue #1746 — the conforming control of the two `issue1746_qualified_arg_*_reject` packages: the
## same qualified calls, `util::len` (an intrinsic name) and `util::pick` (a plain one), each given a
## `u64`, and a struct `S` passed to the qualified `util::first`, whose parameter is `S` resolved in
## `util`. Every argument conforms, so the program runs: 4 + 2 + 3 + 33 = 42.
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
      output = "issue1746-qualified-arg-control",
    ),
  ],
)
## expect: run 42
