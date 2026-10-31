## #1154 — a written unsigned `0 - z` is a borrow-checked subtraction (Concurrency §6.5, spec v1.6.0),
## so it traps only when it borrows: `0 - 0` is 0. The unary `-q` beside it is the negation modulo
## 2^64 (§6.3) and does not trap. The trapping half is `trap_written_zero_sub_unsigned`.
##
## Expected: 42 on all four backends.
## Measured on the parent (#1268 `72c89d45`, native x86_64): 42 on all four backends.
main := fn() -> u64 {
  mut z : u64 = 0
  w : u64 = 0 - z
  if w != 0 { return 4 }
  mut q : u64 = 21
  b := -q                                 ## 2^64 - 21
  if -b != 21 { return 2 }
  return 42
}
