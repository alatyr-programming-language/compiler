## #602 — the ADJACENCY GUARD on the parser's negative-literal fold, and the ONE thing in this
## change that no existing gate stage could see.
##
## `parser::p_factor` folds `-<int>` into a single `Expr::Num` whose RAW SPAN includes the `-`, and
## `alatyr fmt` replays a `Num`'s raw span VERBATIM. So the fold must fire only when the literal
## token abuts the `-` with nothing between them. Measured without the guard: `- (5)` folded to a
## node spanning from the `-` to the end of the literal — the text `- (5` — and `fmt` emitted that,
## exiting 0 while producing a file that no longer parses. `fmt` has no fail-loud channel for a
## wrong RENDERING, so that is a silent miscompile of the user's own source.
##
## Neither the per-file corpus manifest (0 rows moved) nor `fmt_corpus.sh` observed it, because no
## tracked file writes these spellings. This file writes all of them: parenthesised, doubled,
## space-separated, hexadecimal, underscore-separated, and negative zero. `fmt_check` asserts that
## `fmt` is idempotent and that the formatted source still passes `check`; the `run` rows assert
## that every value survives on all four backends, so a rendering that reparsed to a DIFFERENT
## program would be caught by its value and not only by its text.
main := fn() -> u64 {
  a := - (5)
  b := - -4
  c := -  7
  d := -0x10
  e := -1_000
  f := -0
  g := -(3)
  h := - ( - 2 )
  if a != 0 - 5 { return 1 }
  if b != 4 { return 2 }
  if c != 0 - 7 { return 3 }
  if d != 0 - 16 { return 4 }
  if e != 0 - 1000 { return 5 }
  if f != 0 { return 6 }
  if g != 0 - 3 { return 7 }
  if h != 2 { return 8 }
  return 42
}
