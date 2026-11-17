- **The shared IR takes a niche-folded `Option(ptr(T))` whatever its variant order (#1711).** Types
  §6.2 folds the single extra variant into the payload's niche whatever its position, but the builder
  took the one-word folded layout only when the nullary variant was discriminant 0. The compiler's own
  `src/ast.al` declares `Option` with `Some` first, so every function in `src/` with an `Option(ptr(T))`
  parameter was refused. The shape is now one nullary and one single-component variant in either order,
  and every folded variant test goes through one helper that tests by meaning (`None` is `word == 0`,
  `Some` is `word != 0`), never by discriminant: a `match` arm and the `?` operator. `?` on a folded
  operand also stopped reading its payload at byte 8 of the one-word object, which the IR verifier
  refused as an internal error (exit 70) even for the prelude's `None`-first `Option`.
