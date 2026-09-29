## #716 / Types §4.2, §4.4 — `bitcast` reinterprets a block as a type of EQUAL bit width, and a `bool` is
## one byte, so `bitcast(i64, u < 0)` has no conforming reading. The parent accepted it: the comparison's
## `bool` type was never computed, because `check_expr`'s `Bin` and `Unchecked` arms had never run.
f := fn(u : usize) -> i64 { unchecked bitcast(i64, u < 0) }
main := fn() -> u64 {
  return u64(f(5)) + 42
}
