## Issue #1734, the checker's half — the aliased callee's `-> S` is `m`'s `S` for the checker too, so
## `v.b` names a field `m`'s `S` declares; the caller's own `S` has no such field and is not the type
## of `v`. Answers 10 + 1 + 21 + 10 = 42.
##
## Base `740c73fe` (omen): refused at check with `invalid at line 6 in main` on every backend. The
## fix makes x86_64 answer 42; the twins still trap (#1740).
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
      output = "issue1734-alias-callee-agg-result-check",
    ),
  ],
)
## expect: run 42
