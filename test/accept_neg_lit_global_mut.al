## #637 (found by the #602 research, and closed by the same normalisation) — a MUTABLE module-level
## binding initialised from a written negative literal materialised the WRONG BYTES in `.data`.
##
## `lower::global_init_value` and its three non-x86 twins walk the initializer to fold it into the
## word they write, and none had an arm for the parser's `Unchecked(Bin(17, Num(0), Num(9)))`, so
## the value fell through to zero. Measured on the parent, THIS program returns 1 on all four
## backends: `G` reads 0 on x86_64 and wasm and traps 133 on aarch64 and riscv64. Under the
## normalisation the initializer IS a `Num`, so the arm that was already there folds it, and the
## program returns 42 on all four.
##
## The compiler's own source carried this defect: `src/regalloc.al`'s `mut RA_SPILL_BASE := -64`
## emitted `.quad 0`, and it is the ONE non-instruction hunk in this change's emission delta
## (`.quad 0` -> `.quad -64`). It was invisible because every entry point re-assigns the global
## before reading it.
##
## `K` is the IMMUTABLE spelling and `Gi` the annotated one — both were wrong the same way and both
## must move together. NOT here: `mut H := 0 - 9`, the same value written as a binary subtraction.
## That form needs constant folding of `Bin(op, Num, Num)` in the three non-x86 initializer walks,
## which is #590's third row and is deliberately outside this unit; asserting it here would freeze
## a defect (it answers 0 on wasm and traps on aarch64/riscv64 both before and after).
mut G := -9
mut Gi : i64 = -9
K := -9

main := fn() -> u64 {
  if G != 0 - 9 { return 1 }
  if Gi != 0 - 9 { return 2 }
  if K != 0 - 9 { return 3 }
  G = G - 1
  if G != 0 - 10 { return 4 }
  return 42
}
