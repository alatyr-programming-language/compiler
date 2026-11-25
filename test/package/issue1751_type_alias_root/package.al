## Issue #1751 — the root's `S := n::S` makes `S(…)` in the root `n`'s struct (Modules §4.1: an alias is
## erased), although `m` declares its own `pub S` with other fields. Answers 40 + 2 = 42.
##
## NON-VACUOUS: at da8f96af this was refused ("unknown field name"): the parser's field-order lookup
## ranked bare record names and followed no alias, so it checked the fields against `m`'s `S`.
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
      output = "issue1751-type-alias-root",
    ),
  ],
)
## expect: run 42
