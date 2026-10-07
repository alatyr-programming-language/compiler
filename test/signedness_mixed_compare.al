## e2e — Types §4.2/§4.3/§4.5: an ordering compare of an `i64` and a `usize` is refused at check time.
## Neither operand converts implicitly (signed<->unsigned is a NUMERIC conversion, always explicit),
## and no `<` takes one of each, so the program is ill-formed on every backend; before the refusal each
## backend answered it by its own shape rule (`setl` against `setb`).
main := fn() -> u64 {
  x : i64 = 0 - 1
  y : usize = 3
  if x < y { return 1 }
  2
}
