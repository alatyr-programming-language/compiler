## #716 / Types §4.2, §4.3 — `bool` to an integer is the numeric class, always explicit, so a comparison
## result is not an arithmetic operand. The parent accepted this and ran it to 42: `check_expr`'s `Bin`
## arm, which refuses it, had never run. `u64(10 > 3) + 41` is the conforming spelling.
main := fn() -> u64 {
  return (10 > 3) + 41
}
