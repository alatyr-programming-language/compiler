## Issue #1751 — a struct literal whose head is a TYPE alias is the aliased struct (Modules §4.1: an
## alias is erased), resolved in the module that spells it, whatever another module declares:
## - `m`'s `pub T := S` (its own `S`) and `T(…)` in `m`, while the root declares its own `T`;
## - `k`'s `S := n::S`, written `S(…)` in `k`, while the root declares its own `S`.
## Answers 10 (root) + 10 (m) + 22 (k) = 42.
##
## NON-VACUOUS: at da8f96af both shapes were refused ("non-trailing field unwritten"): the parser's
## field-order lookup ranked bare record names from the module being parsed and followed no alias.
## The root-alias shape is `test/package/issue1751_type_alias_root`.
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
      output = "issue1751-type-alias-child",
    ),
  ],
)
## expect: run 42
