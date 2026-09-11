## Issue #655 — the checker used to decide "is this a library module I should TRUST?" by looking for
## `__` in the mangled module name, and the parser mangles a nested submodule `src/geo/child.al` to
## `geo__child`. Every nested submodule of every package therefore looked like ambient stdlib and was
## skipped WHOLESALE by `sema::check_program`: a name bound nowhere passed `check` AND `build`, and
## the program linked. `src/geo/child.al` below is that program. The driver now publishes which
## modules came from a library path, so the question is answered by provenance and this rejects.
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
      output = "issue655-nested-unbound-reject",
    ),
  ],
)
