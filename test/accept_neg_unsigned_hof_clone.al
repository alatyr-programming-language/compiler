## #1154 — the unary `-x` over `u64` stays the negation modulo 2^64 (no overflow member, Concurrency
## §6.3, spec v1.6.0) where the driver CLONES the body it sits in.
##
## The parser records the zero it builds for `-x` (`ast::neg_zero_is`), and a written `0 - x` over an
## unsigned operand is now a borrow-checked subtraction (§6.5). A clone that dropped the record would
## turn the negation into that subtraction and trap. `negate` is called once with a CAPTURING closure,
## which makes the driver deep-clone it (`parser::clone_expr`, the §6.2 HOF specialization; see
## `twice_capture_multisite`), and once with a plain fn, which keeps the original body.
##
## Expected: 42 on x86_64. aarch64 / riscv64 / wasm trap 133 / 133 / 134 at their lambda-value stub
## (#1195), as `twice_capture_multisite` does; the negation is never reached there.
## Measured on the parent (#1268 `72c89d45`, native x86_64): 42 / 133 / 133 / 134, the same.
negate := fn(T : type, g : T, x : T) -> T { return -g(x) }
inc := fn(n : u64) -> u64 { return n + 1 }
main := fn() -> u64 {
  c := 1
  f := fn(n : u64) -> u64 { return n + c }
  a := negate(u64, f, 10)                 ## the clone: -(10 + 1) = 2^64 - 11
  b := negate(u64, inc, 20)               ## the original: -(20 + 1) = 2^64 - 21
  if -a != 11 { return 1 }
  if -b != 21 { return 2 }
  if a - b != 10 { return 3 }
  return 42
}
