## e2e — `{}`-template `print` holes filled by an INFERRED local (`L := …`, no `: T` annotation) or a
## module GLOBAL. Neither records a resolvable type span, so the hole previously matched no renderer
## arm and printed NOTHING silently. Now a scalar Var hole defaults to the int renderer (§7.1: a hole's
## default numeric type is i64). Prints "L 7 G 40" (verified manually) and returns 7 + 35 = 42.
mut G := 40
main := fn() -> u64 {
  L := 7
  std::fmt::print("L {} G {}\n", L, G)
  L + 35
}
