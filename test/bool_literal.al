## Regression (`check`/build parity — the distinct `BoolLit` AST node). `true`/`false` are a distinct
## bool-literal node (not `Num`), so `check` types them `bool` (tag 2), not `int` (tag 1): a bool
## BINDING (`ok : bool = true`), ASSIGNMENT (`ok = false`), ARGUMENT (`pick(true)`), and RETURN
## (`-> bool { return true }`) all type-check — while `x : bool = 1` (a `Num`) stays a mismatch (see
## reject_local_type_mismatch). Lower/comptime treat `BoolLit` identically to `Num` (a word-sized 0/1),
## so this stays byte-identical at the fixpoint. Runtime: exercises each form and returns 42.
pick := fn(b : bool) -> u64 { if b { return 40 } return 0 }
neg := fn(b : bool) -> bool { return b }
main := fn() -> u64 {
  mut ok : bool = true            ## typed bool binding from a bool literal
  ok = false                      ## assignment of a bool literal
  if ok { return 1 }
  a := pick(true)                 ## bool literal as a call argument -> 40
  keep : bool = neg(true)         ## bool-returning fn, bool binding
  b : u64 = 2
  if keep { return a + b }        ## 40 + 2 = 42
  9
}
